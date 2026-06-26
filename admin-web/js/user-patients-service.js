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
import { auth, db, functions } from "./firebase.js";
import { LOG_ACTIONS } from "./activity-log-actions.js";
import { logStaffActivity } from "./activity-logs-service.js";
import { trackFirestoreListener } from "./firestore-realtime.js";
import { comparePrefixedIds } from "./id-sort.js";
import { httpsCallable } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-functions.js";
import {
  formatCallableError,
  shouldFallbackToDirectInvite,
  isFirestorePermissionDenied,
} from "./callable-error.js";
import { createStaffDirect } from "./staff-invite-client.js";
import { assertEmailAvailableForInvite } from "./email-uniqueness-service.js";

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

/** Maps Firestore user status to table filter/display status. */
function displayStatus(data) {
  const account = (data.status || "").toLowerCase();
  if (account === "inactive") return "inactive";
  return "active";
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
    lastVisit: "—",
    status: clinicalStatus,
    email: data.email || "",
    gender: data.gender || "—",
    phone: data.phone || data.emergencyContact || "",
    address: data.address || "",
    birthDate,
    createdAt: birthDateFromFirestore(data.createdAt),
    accountStatus: data.status || "Active",
    assignedDoctorId: data.assignedDoctorId || "",
    assignedDoctorName: data.assignedDoctorName || "",
    assignedTherapistId: data.assignedTherapistId || "",
    assignedTherapistName: data.assignedTherapistName || "",
    assignedCaregiverId: data.assignedCaregiverId || "",
    assignedCaregiverName: data.assignedCaregiverName || "",
  };
}

function sortPatients(patients) {
  return [...patients].sort((a, b) =>
    comparePrefixedIds(a.patientId, b.patientId),
  );
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

function formatPatientCallableError(error, fallback = "Could not complete the request.") {
  return formatCallableError(error, fallback);
}

function shouldFallbackToDirectCreate(error) {
  return shouldFallbackToDirectInvite(error);
}

function generateOnboardingPin() {
  return String(Math.floor(1000 + Math.random() * 9000));
}

function defaultPatientSettings() {
  return {
    fontScale: 1.0,
    notificationsEnabled: true,
    fallDetectionEnabled: true,
    voiceAssistantEnabled: true,
    languageCode: "en",
  };
}

/** Creates a pending patient profile directly in Firestore (admin staff only). */
async function createPatientDirect({ name, birthDate, address, gender = "", phone = "" }) {
  const onboardingPin = generateOnboardingPin();
  const counterRef = doc(db, ...USER_COUNTER_PATH);
  const pendingRef = doc(collection(db, USERS_COLLECTION));
  const staffUid = auth.currentUser?.uid || "";

  const userId = await runTransaction(db, async (transaction) => {
    const counterSnap = await transaction.get(counterRef);
    const next = counterSnap.exists() ? Number(counterSnap.data().next) || 1 : 1;
    const assignedUserId = `U${String(next).padStart(5, "0")}`;
    const settings = defaultPatientSettings();

    transaction.set(counterRef, { next: next + 1 }, { merge: true });
    transaction.set(pendingRef, {
      userId: assignedUserId,
      name: name.trim(),
      email: "",
      birthDate: Timestamp.fromDate(dateOnlyUtc(birthDate)),
      address: address.trim(),
      gender: gender.trim(),
      phone: phone.trim(),
      voiceProfile: "",
      emergencyContact: "",
      settings,
      status: "Active",
      pin: onboardingPin,
      onboardingPin,
      onboardingPending: true,
      emailPending: true,
      createdAt: serverTimestamp(),
      registeredByStaff: staffUid,
    });
    transaction.set(doc(db, "onboardingPins", onboardingPin), {
      pin: onboardingPin,
      pendingDocId: pendingRef.id,
      userId: assignedUserId,
      onboardingPending: true,
      createdAt: serverTimestamp(),
    });

    return assignedUserId;
  });

  return {
    ok: true,
    pendingDocId: pendingRef.id,
    userId,
    pin: onboardingPin,
    onboardingPin,
  };
}

export async function createPatient({ name, birthDate, address, gender = "", phone = "" }) {
  if (birthDate > todayDateString()) {
    throw new Error("Birthdate cannot be in the future.");
  }

  const invitePatient = httpsCallable(functions, "invitePatient");

  try {
    const result = await invitePatient({
      name,
      birthDate,
      address,
      gender,
      phone,
    });
    const data = result?.data || {};
    await logStaffActivity({
      action: LOG_ACTIONS.CREATE_PATIENT,
      details: `Created patient ${name.trim()} (${data.userId || "—"}).`,
      type: "info",
    });
    return data;
  } catch (error) {
    const code = error?.code || "";
    if (code === "functions/already-exists") {
      throw new Error("An account with this email already exists.");
    }
    if (code === "functions/permission-denied") {
      throw new Error("You do not have permission to create patient accounts.");
    }
    if (shouldFallbackToDirectCreate(error)) {
      throw new Error(
        "Patient mobile login requires the invitePatient Cloud Function. Deploy functions with: firebase deploy --only functions:invitePatient",
      );
    }
    throw new Error(formatPatientCallableError(error, "Could not create patient."));
  }
}

export async function createStaff({ name, email, role, phone = "" }) {
  const normalizedEmail = String(email || "").trim().toLowerCase();
  await assertEmailAvailableForInvite(normalizedEmail);

  const continueUrl = `${window.location.origin}/html/login.html`;
  const inviteHealthcareStaff = httpsCallable(functions, "inviteHealthcareStaff");

  try {
    const result = await inviteHealthcareStaff({
      name,
      email: normalizedEmail,
      role,
      phone,
      continueUrl,
    });
    
    await logStaffActivity({
      action: LOG_ACTIONS.CREATE_STAFF,
      details: `Created ${role} ${name.trim()} (${normalizedEmail}) via Cloud Function.`,
      type: "info",
    });
    return result?.data?.uid;
  } catch (error) {
    if (shouldFallbackToDirectInvite(error)) {
      try {
        const direct = await createStaffDirect({
          name,
          email: normalizedEmail,
          role,
          phone,
          continueUrl,
        });
        await logStaffActivity({
          action: LOG_ACTIONS.CREATE_STAFF,
          details: `Created ${role} ${name.trim()} (${normalizedEmail}) via email link invite.`,
          type: "info",
        });
        return direct.inviteId;
      } catch (fallbackError) {
        throw new Error(formatPatientCallableError(fallbackError, "Could not save the staff account."));
      }
    }

    const message = isFirestorePermissionDenied(error)
      ? "You do not have permission to invite staff accounts."
      : formatPatientCallableError(error, "Could not save the staff account.");
    throw new Error(message);
  }
}

export async function deactivateStaff(uid, status = "Inactive") {
  const staffRef = doc(db, "healthcarestaff", uid);
  await updateDoc(staffRef, { status });
}

export async function updateStaff(uid, fields) {
  const staffRef = doc(db, "healthcarestaff", uid);
  const payload = { updatedAt: serverTimestamp() };
  if (Object.hasOwn(fields, "name")) payload.name = fields.name.trim();
  if (Object.hasOwn(fields, "email")) payload.email = fields.email.trim().toLowerCase();
  if (Object.hasOwn(fields, "phone")) payload.phone = fields.phone.trim();
  if (Object.hasOwn(fields, "specialty")) payload.specialty = fields.specialty.trim();
  if (Object.hasOwn(fields, "status")) {
    const status = String(fields.status || "").trim();
    if (status === "Active" || status === "Inactive") {
      payload.status = status;
    }
  }
  await updateDoc(staffRef, payload);
  await logStaffActivity({
    action: LOG_ACTIONS.UPDATE_STAFF,
    details: `Updated staff profile ${uid}.`,
    type: "info",
  });
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
  if (Object.hasOwn(fields, "assignedDoctorId")) {
    payload.assignedDoctorId = fields.assignedDoctorId;
    payload.assignedDoctorName = fields.assignedDoctorName;
  }
  if (Object.hasOwn(fields, "gender")) {
    payload.gender = fields.gender.trim();
  }
  if (Object.hasOwn(fields, "assignedCaregiverId")) {
    payload.assignedCaregiverId = fields.assignedCaregiverId;
    payload.assignedCaregiverName = fields.assignedCaregiverName;
  }
  if (Object.hasOwn(fields, "assignedCaregiverPublicId")) {
    payload.assignedCaregiverPublicId = fields.assignedCaregiverPublicId;
  }
  if (Object.hasOwn(fields, "assignedTherapistId")) {
    payload.assignedTherapistId = fields.assignedTherapistId;
    payload.assignedTherapistName = fields.assignedTherapistName;
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
