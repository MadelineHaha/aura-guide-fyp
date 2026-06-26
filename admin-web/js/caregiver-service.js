import {
  collection,
  doc,
  getDocs,
  onSnapshot,
  serverTimestamp,
  updateDoc,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { auth, db, functions } from "./firebase.js";
import { LOG_ACTIONS } from "./activity-log-actions.js";
import { logStaffActivity } from "./activity-logs-service.js";
import { trackFirestoreListener } from "./firestore-realtime.js";
import { comparePrefixedIds } from "./id-sort.js";
import { httpsCallable } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-functions.js";
import { formatCallableError, shouldFallbackToDirectInvite, isFirestorePermissionDenied } from "./callable-error.js";
import { createCaregiverDirect } from "./staff-invite-client.js";
import { assertEmailAvailableForInvite } from "./email-uniqueness-service.js";
import { updatePatient } from "./user-patients-service.js";

export const CAREGIVER_COLLECTION = "caregiver";

function mapCaregiverDoc(docSnap) {
  const data = docSnap.data() || {};
  const connectedPatients = Array.isArray(data.connectedPatients) ? data.connectedPatients : [];
  const connectedUserIds = Array.isArray(data.connectedUserIds)
    ? data.connectedUserIds
    : connectedPatients.map((entry) => entry.userId).filter(Boolean);

  return {
    uid: docSnap.id,
    caregiverId: data.caregiverId || data.caregiverID || "",
    name: data.name || "",
    email: data.email || "",
    phone: data.phone || "",
    status: data.status || "Active",
    role: "caregiver",
    connectedUserIds,
    connectedPatients,
    createdAt: data.createdAt,
  };
}

function sortCaregivers(caregivers) {
  return [...caregivers].sort((a, b) =>
    comparePrefixedIds(a.caregiverId, b.caregiverId),
  );
}

export async function fetchCaregivers() {
  const snap = await getDocs(collection(db, CAREGIVER_COLLECTION));
  return sortCaregivers(snap.docs.map(mapCaregiverDoc));
}

export function subscribeCaregivers(onData, onError) {
  const unsub = onSnapshot(
    collection(db, CAREGIVER_COLLECTION),
    (snap) => {
      onData(sortCaregivers(snap.docs.map(mapCaregiverDoc)));
    },
    onError,
  );
  trackFirestoreListener(unsub);
  return unsub;
}

function formatCaregiverCallableError(error, fallback = "Could not complete the request.") {
  return formatCallableError(error, fallback);
}

export async function createCaregiver({
  name,
  email,
  phone = "",
  connectedPatients = [],
}) {
  const trimmedPatients = connectedPatients
    .map((entry) => ({
      patientDocId: String(entry.patientDocId || entry.id || "").trim(),
      userId: String(entry.userId || entry.userID || "").trim().toUpperCase(),
      name: String(entry.name || "").trim(),
    }))
    .filter((entry) => entry.patientDocId && entry.userId);

  if (trimmedPatients.length === 0) {
    throw new Error("Select at least one patient to connect.");
  }

  const normalizedEmail = String(email || "").trim().toLowerCase();
  await assertEmailAvailableForInvite(normalizedEmail);

  const continueUrl = `${window.location.origin}/html/login.html`;
  const inviteCaregiver = httpsCallable(functions, "inviteCaregiver");

  try {
    const result = await inviteCaregiver({
      name,
      email: normalizedEmail,
      phone,
      connectedPatients: trimmedPatients,
      continueUrl,
    });
    await logStaffActivity({
      action: LOG_ACTIONS.CREATE_STAFF,
      details: `Created caregiver ${name.trim()} via Cloud Function.`,
      type: "info",
    });
    return {
      ok: true,
      uid: result?.data?.uid,
    };
  } catch (error) {
    if (shouldFallbackToDirectInvite(error)) {
      try {
        const direct = await createCaregiverDirect({
          name,
          email: normalizedEmail,
          phone,
          connectedPatients: trimmedPatients,
          continueUrl,
        });
        await logStaffActivity({
          action: LOG_ACTIONS.CREATE_STAFF,
          details: `Created caregiver ${name.trim()} via email link invite.`,
          type: "info",
        });
        return {
          ok: true,
          uid: direct.inviteId,
        };
      } catch (fallbackError) {
        throw new Error(formatCaregiverCallableError(fallbackError, "Could not save the caregiver account."));
      }
    }

    const message = isFirestorePermissionDenied(error)
      ? "You do not have permission to invite caregiver accounts."
      : formatCaregiverCallableError(error, "Could not save the caregiver account.");
    throw new Error(message);
  }
}

export async function updateCaregiver(uid, fields) {
  const caregiverRef = doc(db, CAREGIVER_COLLECTION, uid);
  const payload = { updatedAt: serverTimestamp() };

  if (Object.hasOwn(fields, "name")) payload.name = fields.name.trim();
  if (Object.hasOwn(fields, "email")) payload.email = fields.email.trim().toLowerCase();
  if (Object.hasOwn(fields, "phone")) payload.phone = fields.phone.trim();
  if (Object.hasOwn(fields, "status")) {
    const status = String(fields.status || "").trim();
    if (status === "Active" || status === "Inactive") {
      payload.status = status;
    }
  }

  await updateDoc(caregiverRef, payload);
  await logStaffActivity({
    action: LOG_ACTIONS.UPDATE_STAFF,
    details: `Updated caregiver profile ${uid}.`,
    type: "info",
  });
}

export async function deactivateCaregiver(uid, status = "Inactive") {
  await updateCaregiver(uid, { status });
}

export async function updateCaregiverConnections({
  caregiverUid,
  caregiverName,
  caregiverId,
  connectedPatients,
}) {
  const trimmedPatients = connectedPatients
    .map((entry) => ({
      patientDocId: String(entry.patientDocId || entry.id || "").trim(),
      userId: String(entry.userId || entry.userID || "").trim().toUpperCase(),
      name: String(entry.name || "").trim(),
    }))
    .filter((entry) => entry.patientDocId && entry.userId);

  const connectedUserIds = trimmedPatients.map((entry) => entry.userId);

  await updateDoc(doc(db, CAREGIVER_COLLECTION, caregiverUid), {
    connectedUserIds,
    connectedPatients: trimmedPatients,
    updatedAt: serverTimestamp(),
  });

  for (const patient of trimmedPatients) {
    await updatePatient(patient.patientDocId, {
      assignedCaregiverId: caregiverUid,
      assignedCaregiverName: caregiverName,
      assignedCaregiverPublicId: caregiverId,
    });
  }

  await logStaffActivity({
    action: LOG_ACTIONS.UPDATE_STAFF,
    details: `Updated connected patients for caregiver ${caregiverId || caregiverUid}.`,
    type: "info",
  });
}
