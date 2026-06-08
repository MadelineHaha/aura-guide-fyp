import {
  collection,
  deleteField,
  doc,
  getDoc,
  getDocs,
  onSnapshot,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";

import {

  ref,

  uploadBytes,

} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-storage.js";

import { db, storage } from "./firebase.js";

import { todayDateString } from "./appointments-service.js";
import { formatTypedSentence } from "./text-format.js";

import { fetchActiveStaff } from "./staff-list-service.js";
import { HEALTHCARE_STAFF_COLLECTION } from "./staff-auth.js";
import { trackFirestoreListener } from "./firestore-realtime.js";



export const HEALTH_RECORDS_COLLECTION = "healthrecords";

export const HEALTH_RECORD_COUNTER_PATH = ["system", "healthRecordCounter"];



const RECORD_TYPE_MAX = 50;

const TITLE_MAX = 100;

const FILE_PATH_MAX = 255;

const USER_ID_PATTERN = /^U\d{5}$/;

const STAFF_ID_PATTERN = /^S\d{5}$/;

export const MAX_FILE_BYTES = 2 * 1024 * 1024;

export const MAX_FILE_SIZE_MESSAGE =

  "The file uploaded should be maximum 2 MB.";



/** Files at or below this size are stored in Firestore (one fast write). */

export const INLINE_FILE_MAX_BYTES = 750 * 1024;

const STORAGE_UPLOAD_TIMEOUT_MS = 25_000;



const ALLOWED_FILE_TYPES = {

  pdf: "PDF",

  jpg: "JPG",

  jpeg: "JPG",

  png: "PNG",

  doc: "DOC",

  docx: "DOCX",

};

const OTHER_RECORD_TYPE_PATTERN = /^[A-Za-z0-9 ]+$/;

export const PRESET_RECORD_TYPES = [
  "Eye Examination",
  "General Checkup",
  "Lab Results",
  "Imaging",
  "Prescription Update",
];

/** e.g. "the record is good" → "The record is good." */
export function capitalizeClinicalSummary(text) {
  return formatTypedSentence(text);
}

/** e.g. "lab report" → "Lab Report" */
export function capitalizeOtherRecordType(text) {
  const trimmed = String(text || "")
    .trim()
    .replace(/\s+/g, " ");
  if (!trimmed) return trimmed;
  return trimmed
    .toLowerCase()
    .split(" ")
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(" ");
}

/**
 * Validates and formats text before save.
 * @returns {{ recordType: string, title: string } | { error: string }}
 */
export function prepareHealthRecordInput({ recordType, title, isOtherRecordType }) {
  const typeRaw = String(recordType || "").trim();
  const titleRaw = String(title || "").trim();

  if (isOtherRecordType) {
    if (!typeRaw) {
      return { error: "Please enter a record type." };
    }
    if (
      !OTHER_RECORD_TYPE_PATTERN.test(typeRaw) ||
      !/[A-Za-z0-9]/.test(typeRaw)
    ) {
      return {
        error:
          "Specify Record Type can only contain letters, numbers, and spaces.",
      };
    }
    return {
      recordType: capitalizeOtherRecordType(typeRaw),
      title: capitalizeClinicalSummary(titleRaw),
    };
  }

  return {
    recordType: typeRaw,
    title: capitalizeClinicalSummary(titleRaw),
  };
}

function fileExtension(fileName) {

  const parts = String(fileName || "").toLowerCase().split(".");

  return parts.length > 1 ? parts.pop() : "";

}



export function resolveFileType(fileName) {

  const ext = fileExtension(fileName);

  return ALLOWED_FILE_TYPES[ext] || null;

}



function staffDisplayName(staff) {

  if (!staff?.name) return staff?.staffID || "—";

  const role = (staff.role || "").toLowerCase();

  if (role.includes("doctor") || role.includes("dr")) {

    return staff.name.startsWith("Dr.") ? staff.name : `Dr. ${staff.name}`;

  }

  return staff.name;

}



function readFileAsBase64(file) {

  return new Promise((resolve, reject) => {

    const reader = new FileReader();

    reader.onload = () => {

      const result = String(reader.result || "");

      const base64 = result.includes(",") ? result.split(",")[1] : result;

      resolve(base64);

    };

    reader.onerror = () => reject(new Error("Could not read the selected file."));

    reader.readAsDataURL(file);

  });

}



function withTimeout(promise, ms, message) {

  return Promise.race([

    promise,

    new Promise((_, reject) => {

      setTimeout(() => reject(new Error(message)), ms);

    }),

  ]);

}



/**

 * Validates add-health-record form data against ERD constraints.

 * @returns {string|null} Error message or null if valid.

 */

function validateHealthRecordFile(file) {
  if (!file) return null;
  const fileType = resolveFileType(file.name);
  if (!fileType) {
    return "File type must be PDF, JPG, PNG, DOC, or DOCX.";
  }
  if (file.size > MAX_FILE_BYTES) {
    return MAX_FILE_SIZE_MESSAGE;
  }
  return null;
}

export function validateHealthRecordInput({
  recordType,
  title,
  file,
  userId,
  staffId,
  requireFile = true,
}) {

  const type = String(recordType || "").trim();

  const titleText = String(title || "").trim();



  if (!type) {

    return "Record type is required.";

  }

  if (type.length > RECORD_TYPE_MAX) {

    return `Record type must be ${RECORD_TYPE_MAX} characters or less.`;

  }

  if (!titleText) {

    return "Clinical Summary is required.";

  }

  if (titleText.length > TITLE_MAX) {

    return `Clinical Summary must be ${TITLE_MAX} characters or less.`;

  }

  if (!userId || !USER_ID_PATTERN.test(userId)) {

    return "Patient User ID is missing or invalid.";

  }

  if (!staffId || !STAFF_ID_PATTERN.test(staffId)) {

    return "Your staff profile is missing a valid Staff ID (e.g. S00001).";

  }

  if (requireFile && !file) {
    return "Please upload a report file.";
  }
  return validateHealthRecordFile(file);
}



function buildFilePath(userId, recordId, fileName) {

  const ext = fileExtension(fileName);

  const path = `healthrecords/${userId}/${recordId}.${ext}`;

  if (path.length > FILE_PATH_MAX) {

    throw new Error("File path is too long. Use a shorter file name.");

  }

  return path;

}



function buildRecordPayload({

  recordId,

  dateCreated,

  recordType,

  title,

  fileType,

  filePath,

  userId,

  staffId,

  fileData = null,

}) {

  const payload = {

    recordId,

    dateCreated,

    recordType,

    title,

    fileType,

    filePath,

    userId,

    staffId,

    createdAt: serverTimestamp(),

  };

  if (fileData) {

    payload.fileData = fileData;

  }

  return payload;

}



/** One transaction: counter + full record (fast path for reports ≤ 750 KB). */

async function createInlineHealthRecord({

  userId,

  recordType,

  title,

  fileType,

  filePath,

  staffId,

  fileData,

}) {

  const counterRef = doc(db, ...HEALTH_RECORD_COUNTER_PATH);

  const dateCreated = todayDateString();



  return runTransaction(db, async (transaction) => {

    const counterSnap = await transaction.get(counterRef);

    const next = counterSnap.exists()

      ? Number(counterSnap.data().next) || 1

      : 1;

    const recordId = `H${String(next).padStart(5, "0")}`;

    const recordRef = doc(db, HEALTH_RECORDS_COLLECTION, recordId);



    transaction.set(counterRef, { next: next + 1 }, { merge: true });

    transaction.set(

      recordRef,

      buildRecordPayload({

        recordId,

        dateCreated,

        recordType,

        title,

        fileType,

        filePath: buildFilePath(userId, recordId, filePath),

        userId,

        staffId,

        fileData,

      }),

    );



    return {
      recordId,
      dateCreated,
      filePath: buildFilePath(userId, recordId, filePath),
    };

  });

}



/** Reserve the next HNNNNN id (used before Firebase Storage upload). */

async function reserveHealthRecordId() {

  const counterRef = doc(db, ...HEALTH_RECORD_COUNTER_PATH);

  return runTransaction(db, async (transaction) => {

    const counterSnap = await transaction.get(counterRef);

    const next = counterSnap.exists()

      ? Number(counterSnap.data().next) || 1

      : 1;

    const recordId = `H${String(next).padStart(5, "0")}`;

    transaction.set(counterRef, { next: next + 1 }, { merge: true });

    return recordId;

  });

}



async function createStorageHealthRecord({

  userId,

  staffId,

  recordType,

  title,

  fileType,

  file,

  fileName,

  onPhase,

}) {

  const trimmedType = recordType.trim();

  const trimmedTitle = title.trim();

  const dateCreated = todayDateString();



  onPhase?.("assigning-id");

  const recordId = await reserveHealthRecordId();

  const filePath = buildFilePath(userId, recordId, fileName);



  onPhase?.("uploading");

  const storageRef = ref(storage, filePath);

  try {

    await withTimeout(

      uploadBytes(storageRef, file, {

        contentType: file.type || "application/octet-stream",

      }),

      STORAGE_UPLOAD_TIMEOUT_MS,

      "Upload timed out. Check your connection or deploy storage.rules, then try again.",

    );

  } catch (error) {

    const code = error?.code || "";

    if (code === "storage/unauthorized" || code === "storage/unauthenticated") {

      throw new Error(

        "Upload blocked. Enable Firebase Storage and deploy storage.rules.",

      );

    }

    throw error;

  }



  onPhase?.("saving");

  await setDoc(
    doc(db, HEALTH_RECORDS_COLLECTION, recordId),
    buildRecordPayload({
      recordId,
      dateCreated,
      recordType: trimmedType,
      title: trimmedTitle,
      fileType,
      filePath,
      userId,
      staffId,
    }),
  );

  return { recordId, dateCreated, filePath };

}



export function mapHealthRecordDoc(docSnap, staffByStaffId) {

  const data = docSnap.data();

  const staffId = data.staffId || data.staffID || "";

  const staff = staffByStaffId?.get(staffId);

  return {

    recordId: data.recordId || docSnap.id,

    type: data.recordType || "—",

    description: data.title || "—",

    doctor: staff ? staffDisplayName(staff) : staffId || "—",

    dateCreated: data.dateCreated || "—",

    fileType: data.fileType || "—",

    filePath: data.filePath || "",

  };

}



/** True when Firestore blocked the list read (often before any records exist). */

export function isHealthRecordsAccessError(error) {

  const code = error?.code || "";

  const msg = (error?.message || "").toLowerCase();

  return (

    code === "permission-denied" ||

    msg.includes("insufficient permissions") ||

    msg.includes("missing or insufficient permissions")

  );

}



function mapHealthRecordsSnap(snap, staffByStaffId) {
  if (snap.empty) return [];
  return snap.docs
    .map((docSnap) => mapHealthRecordDoc(docSnap, staffByStaffId))
    .sort((a, b) => String(b.dateCreated).localeCompare(String(a.dateCreated)));
}

export async function fetchHealthRecordsByUserId(userId) {
  const q = query(
    collection(db, HEALTH_RECORDS_COLLECTION),
    where("userId", "==", userId),
  );
  const snap = await getDocs(q);
  if (snap.empty) return [];
  const staffList = await fetchActiveStaff();
  const staffByStaffId = new Map(
    staffList.map((staff) => [staff.staffID, staff]),
  );
  return mapHealthRecordsSnap(snap, staffByStaffId);
}

/** Real-time health records for one patient (modal / detail view). */
export function subscribeHealthRecordsByUserId(userId, onData, onError) {
  const trimmedUserId = String(userId || "").trim();
  let staffByStaffId = new Map();
  let recordsSnap = null;

  function emit() {
    if (!recordsSnap) return;
    onData(mapHealthRecordsSnap(recordsSnap, staffByStaffId));
  }

  const recordsQuery = query(
    collection(db, HEALTH_RECORDS_COLLECTION),
    where("userId", "==", trimmedUserId),
  );

  const unsubs = [
    onSnapshot(
      collection(db, HEALTHCARE_STAFF_COLLECTION),
      (snap) => {
        const staffList = snap.docs
          .map((docSnap) => {
            const data = docSnap.data();
            return {
              staffID: data.staffID || "",
              name: data.name || "",
              status: data.status || "",
            };
          })
          .filter((staff) => staff.status === "Active" && staff.staffID);
        staffByStaffId = new Map(staffList.map((staff) => [staff.staffID, staff]));
        emit();
      },
      onError,
    ),
    onSnapshot(
      recordsQuery,
      (snap) => {
        recordsSnap = snap;
        emit();
      },
      onError,
    ),
  ];

  const stopAll = () => {
    for (const unsub of unsubs) {
      if (typeof unsub === "function") unsub();
    }
  };
  trackFirestoreListener(stopAll);
  return stopAll;
}



function formatStaffDoctorName(name) {

  const trimmed = String(name || "").trim();

  if (!trimmed) return "Staff";

  return trimmed.startsWith("Dr.") ? trimmed : `Dr. ${trimmed}`;

}



export async function createHealthRecord({

  userId,

  staffId,

  recordType,

  title,

  file,

  staffName = "",

  onPhase,

}) {

  const validationError = validateHealthRecordInput({

    recordType,

    title,

    file,

    userId,

    staffId,

  });

  if (validationError) {

    throw new Error(validationError);

  }



  const fileType = resolveFileType(file.name);

  const trimmedType = recordType.trim();

  const trimmedTitle = formatTypedSentence(title);



  let recordId;

  let dateCreated;

  let filePath;



  if (file.size <= INLINE_FILE_MAX_BYTES) {

    onPhase?.("saving");

    const fileData = await readFileAsBase64(file);

    const inline = await createInlineHealthRecord({

      userId,

      recordType: trimmedType,

      title: trimmedTitle,

      fileType,

      filePath: file.name,

      staffId,

      fileData,

    });

    recordId = inline.recordId;

    dateCreated = inline.dateCreated;

    filePath = inline.filePath;

  } else {

    const stored = await createStorageHealthRecord({

      userId,

      staffId,

      recordType: trimmedType,

      title: trimmedTitle,

      fileType,

      file,

      fileName: file.name,

      onPhase,

    });

    recordId = stored.recordId;

    dateCreated = stored.dateCreated;

    filePath = stored.filePath;

  }



  return {

    recordId,

    type: trimmedType,

    description: trimmedTitle,

    doctor: formatStaffDoctorName(staffName),

    dateCreated,

    fileType,

    filePath,

  };

}

export async function fetchHealthRecordById(recordId) {
  const snap = await getDoc(doc(db, HEALTH_RECORDS_COLLECTION, recordId));
  if (!snap.exists()) return null;
  const data = snap.data();
  return {
    recordId: data.recordId || snap.id,
    recordType: data.recordType || "",
    title: data.title || "",
    fileType: data.fileType || "",
    filePath: data.filePath || "",
    userId: data.userId || "",
    staffId: data.staffId || data.staffID || "",
    dateCreated: data.dateCreated || "",
    hasInlineFile: Boolean(data.fileData),
  };
}

async function applyUpdatedHealthRecordFile(payload, { file, userId, recordId, onPhase }) {
  const fileType = resolveFileType(file.name);
  if (file.size <= INLINE_FILE_MAX_BYTES) {
    onPhase?.("saving");
    payload.fileType = fileType;
    payload.filePath = buildFilePath(userId, recordId, file.name);
    payload.fileData = await readFileAsBase64(file);
    return;
  }

  const filePath = buildFilePath(userId, recordId, file.name);
  onPhase?.("uploading");
  const storageRef = ref(storage, filePath);
  try {
    await withTimeout(
      uploadBytes(storageRef, file, {
        contentType: file.type || "application/octet-stream",
      }),
      STORAGE_UPLOAD_TIMEOUT_MS,
      "Upload timed out. Check your connection or deploy storage.rules, then try again.",
    );
  } catch (error) {
    const code = error?.code || "";
    if (code === "storage/unauthorized" || code === "storage/unauthenticated") {
      throw new Error(
        "Upload blocked. Enable Firebase Storage and deploy storage.rules.",
      );
    }
    throw error;
  }

  onPhase?.("saving");
  payload.fileType = fileType;
  payload.filePath = filePath;
  payload.fileData = deleteField();
}

export async function updateHealthRecord({
  recordId,
  userId,
  recordType,
  title,
  file,
  staffId,
  staffName = "",
  onPhase,
}) {
  const validationError = validateHealthRecordInput({
    recordType,
    title,
    file,
    userId,
    staffId,
    requireFile: false,
  });
  if (validationError) {
    throw new Error(validationError);
  }

  const trimmedType = recordType.trim();
  const trimmedTitle = formatTypedSentence(title);
  const payload = {
    recordType: trimmedType,
    title: trimmedTitle,
    updatedAt: serverTimestamp(),
  };

  if (file) {
    await applyUpdatedHealthRecordFile(payload, {
      file,
      userId,
      recordId,
      onPhase,
    });
  }

  onPhase?.("saving");
  await updateDoc(doc(db, HEALTH_RECORDS_COLLECTION, recordId), payload);

  const existing = await fetchHealthRecordById(recordId);
  return {
    recordId,
    type: trimmedType,
    description: trimmedTitle,
    doctor: formatStaffDoctorName(staffName),
    dateCreated: existing?.dateCreated || "",
    fileType: file ? resolveFileType(file.name) : existing?.fileType || "",
    filePath: payload.filePath || existing?.filePath || "",
  };
}


