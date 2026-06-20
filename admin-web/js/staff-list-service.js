import {
  collection,
  getDocs,
  onSnapshot,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { HEALTHCARE_STAFF_COLLECTION } from "./staff-auth.js";
import { trackFirestoreListener } from "./firestore-realtime.js";

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
    .sort((a, b) => a.name.localeCompare(b.name));
}

export async function fetchActiveStaff() {
  const snap = await getDocs(collection(db, HEALTHCARE_STAFF_COLLECTION));
  return mapActiveStaffDocs(snap.docs);
}

function isCaregiverRole(role) {
  const value = String(role || "").trim().toLowerCase();
  return value === "caregiver" || value === "nurse";
}

export async function fetchActiveCaregivers() {
  const staff = await fetchActiveStaff();
  return staff.filter((member) => isCaregiverRole(member.role));
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
