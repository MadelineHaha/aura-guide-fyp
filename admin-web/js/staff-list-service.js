import {
  collection,
  getDocs,
  onSnapshot,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { HEALTHCARE_STAFF_COLLECTION } from "./staff-auth.js";
import { CAREGIVER_COLLECTION } from "./caregiver-service.js";
import { trackFirestoreListener } from "./firestore-realtime.js";
import { comparePrefixedIds } from "./id-sort.js";

function mapActiveStaffDocs(docs) {
  return docs
    .map((docSnap) => {
      const data = docSnap.data();
      return {
        uid: docSnap.id,
        staffID: data.staffID || "",
        name: data.name || "",
        role: data.role || "",
        status: data.status || "",
      };
    })
    .filter((staff) => staff.status === "Active" && staff.staffID)
    .sort((a, b) => comparePrefixedIds(a.staffID, b.staffID));
}

export async function fetchActiveStaff() {
  const snap = await getDocs(collection(db, HEALTHCARE_STAFF_COLLECTION));
  return mapActiveStaffDocs(snap.docs);
}

function mapActiveCaregiverDocs(docs) {
  return docs
    .map((docSnap) => {
      const data = docSnap.data();
      const caregiverId = data.caregiverId || data.caregiverID || "";
      return {
        uid: docSnap.id,
        staffID: caregiverId,
        caregiverId,
        name: data.name || "",
        role: "caregiver",
        status: data.status || "",
        connectedUserIds: Array.isArray(data.connectedUserIds) ? data.connectedUserIds : [],
      };
    })
    .filter((caregiver) => caregiver.status === "Active" && caregiver.caregiverId)
    .sort((a, b) => comparePrefixedIds(a.caregiverId, b.caregiverId));
}

export async function fetchActiveCaregivers() {
  const snap = await getDocs(collection(db, CAREGIVER_COLLECTION));
  return mapActiveCaregiverDocs(snap.docs);
}

/** Real-time active staff list. */
export function subscribeActiveStaff(onData, onError) {
  const unsub = onSnapshot(
    collection(db, HEALTHCARE_STAFF_COLLECTION),
    (snap) => {
      onData(mapActiveStaffDocs(snap.docs));
    },
    onError,
  );
  trackFirestoreListener(unsub);
  return unsub;
}

function mapAllStaffDocs(docs) {
  return docs
    .map((docSnap) => {
      const data = docSnap.data();
      return {
        uid: docSnap.id,
        staffID: data.staffID || data.staffId || "",
        name: data.name || "",
        email: data.email || "",
        phone: data.phone || "",
        role: data.role || "",
        specialty: data.specialty || "",
        status: data.status || "",
      };
    })
    .sort((a, b) => comparePrefixedIds(a.staffID, b.staffID));
}

export async function fetchAllStaff() {
  const snap = await getDocs(collection(db, HEALTHCARE_STAFF_COLLECTION));
  return mapAllStaffDocs(snap.docs);
}

/** Real-time staff list including inactive accounts (administration). */
export function subscribeAllStaff(onData, onError) {
  const unsub = onSnapshot(
    collection(db, HEALTHCARE_STAFF_COLLECTION),
    (snap) => {
      onData(mapAllStaffDocs(snap.docs));
    },
    onError,
  );
  trackFirestoreListener(unsub);
  return unsub;
}
