import {
  collection,
  doc,
  getDoc,
  getDocs,
  onSnapshot,
  query,
  runTransaction,
  serverTimestamp,
  Timestamp,
  updateDoc,
  where,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { auth, db } from "./firebase.js";
import { LOG_ACTIONS } from "./activity-log-actions.js";
import { logStaffActivity } from "./activity-logs-service.js";
import { trackFirestoreListener } from "./firestore-realtime.js";

export const USERS_COLLECTION = "users";
export const USER_COUNTER_PATH = ["system", "userCounter"];

export function computeAge(birthDate, referenceDate = new Date()) {
  const ref = referenceDate;
  let age = ref.getFullYear() - birthDate.getFullYear();
  const monthDiff = ref.getMonth() - birthDate.getMonth();
  if (monthDiff < 0 || (monthDiff === 0 && ref.getDate() < birthDate.getDate())) {
    age -= 1;
  }
  return age;
}

function birthDateFromFirestore(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

function formatLastVisit(value) {
  const date = birthDateFromFirestore(value);
  if (!date) return "—";
  return date.toISOString().slice(0, 10);
}

/** Maps Firestore user status to table filter/display status. */
function displayStatus(data) {
  const clinical = (data.clinicalStatus || "").toLowerCase();
  if (["stable", "monitoring", "critical"].includes(clinical)) return clinical;
  const account = (data.status || "").toLowerCase();
  if (account === "inactive") return "monitoring";
  return "stable";
}

export function mapUserDoc(docSnap) {
  const data = docSnap.data();
  const birthDate = birthDateFromFirestore(data.birthDate);
  const clinicalStatus = displayStatus(data);
  return {
    id: docSnap.id,
    name: data.name || "—",
    patientId: data.userId || data.userID || "—",
    age: birthDate ? computeAge(birthDate) : "—",
    condition: data.condition || "—",
    lastVisit: formatLastVisit(data.lastVisit || data.createdAt),
    status: clinicalStatus,
    email: data.email || "",
    phone: data.phone || data.emergencyContact || "",
    address: data.address || "",
    birthDate,
    createdAt: birthDateFromFirestore(data.createdAt),
    accountStatus: data.status || "Active",
  };
}

function sortPatients(patients) {
  return [...patients].sort((a, b) => a.name.localeCompare(b.name));
}

export async function fetchPatients() {
  const snap = await getDocs(collection(db, USERS_COLLECTION));
  return sortPatients(snap.docs.map(mapUserDoc));
}

export async function fetchPatientByUserId(patientUserId) {
  const trimmedId = String(patientUserId || "").trim();
  if (!trimmedId) return null;

  for (const field of ["userId", "userID"]) {
    const snap = await getDocs(
      query(collection(db, USERS_COLLECTION), where(field, "==", trimmedId)),
    );
    if (!snap.empty) {
      return mapUserDoc(snap.docs[0]);
    }
  }

  return null;
}

/** Real-time patient list; fires when any user document changes. */
export function subscribePatients(onData, onError) {
  const unsub = onSnapshot(
    collection(db, USERS_COLLECTION),
    (snap) => {
      onData(sortPatients(snap.docs.map(mapUserDoc)));
    },
    onError,
  );
  trackFirestoreListener(unsub);
  return unsub;
}

function dateOnlyUtc(dateStr) {
  const [y, m, d] = dateStr.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d));
}

function todayDateString() {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export async function createPatient({ name, email, birthDate, address }) {
  if (birthDate > todayDateString()) {
    throw new Error("Birthdate cannot be in the future.");
  }

  const usersRef = collection(db, USERS_COLLECTION);
  const counterRef = doc(db, ...USER_COUNTER_PATH);
  const newRef = doc(usersRef);
  const staffUid = auth.currentUser?.uid || "";

  await runTransaction(db, async (transaction) => {
    const counterSnap = await transaction.get(counterRef);
    const next = counterSnap.exists() ? Number(counterSnap.data().next) || 1 : 1;
    const userId = `U${String(next).padStart(5, "0")}`;

    transaction.set(counterRef, { next: next + 1 }, { merge: true });
    transaction.set(newRef, {
      userId,
      name: name.trim(),
      email: email.trim().toLowerCase(),
      birthDate: Timestamp.fromDate(dateOnlyUtc(birthDate)),
      address: address.trim(),
      voiceProfile: "",
      emergencyContact: "",
      settings: {
        fontScale: 1.0,
        notificationsEnabled: true,
        fallDetectionEnabled: true,
        voiceAssistantEnabled: true,
        languageCode: "en",
      },
      accessibilityPreferences: {
        fontScale: 1.0,
        notificationsEnabled: true,
        fallDetectionEnabled: true,
        voiceAssistantEnabled: true,
        languageCode: "en",
      },
      status: "Active",
      createdAt: serverTimestamp(),
      registeredByStaff: staffUid,
    });
  });

  return newRef.id;
}

export function dateToInputValue(date) {
  if (!date) return "";
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function patientUserIdFromData(data, fallback = "—") {
  return (
    data?.userId ||
    data?.userID ||
    data?.patientId ||
    fallback
  );
}

export async function updatePatient(docId, fields) {
  const patientRef = doc(db, USERS_COLLECTION, docId);
  const beforeSnap = await getDoc(patientRef);
  const patientUserId = beforeSnap.exists()
    ? patientUserIdFromData(beforeSnap.data(), docId)
    : docId;

  const payload = { updatedAt: serverTimestamp() };

  if (Object.hasOwn(fields, "email")) {
    payload.email = fields.email.trim().toLowerCase();
  }
  if (Object.hasOwn(fields, "phone")) {
    payload.phone = fields.phone.trim();
  }
  if (Object.hasOwn(fields, "condition")) {
    payload.condition = fields.condition.trim();
  }
  if (Object.hasOwn(fields, "clinicalStatus")) {
    payload.clinicalStatus = fields.clinicalStatus.toLowerCase();
  }
  if (Object.hasOwn(fields, "address")) {
    payload.address = fields.address.trim();
  }
  if (Object.hasOwn(fields, "birthDate")) {
    if (!fields.birthDate) {
      throw new Error("Please select a birthdate.");
    }
    if (fields.birthDate > todayDateString()) {
      throw new Error("Birthdate cannot be in the future.");
    }
    payload.birthDate = Timestamp.fromDate(dateOnlyUtc(fields.birthDate));
  }
  if (Object.hasOwn(fields, "status")) {
    payload.status = fields.status;
  }

  await updateDoc(patientRef, payload);
  await logStaffActivity({
    action: LOG_ACTIONS.UPDATE_PATIENT,
    details: `Updated patient profile ${patientUserId}.`,
    type: "info",
  });
}

export async function deactivatePatient(docId) {
  await updatePatient(docId, { status: "Inactive" });
}
