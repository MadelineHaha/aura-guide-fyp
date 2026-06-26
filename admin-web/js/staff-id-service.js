import { doc, getDoc, onSnapshot } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { trackFirestoreListener } from "./firestore-realtime.js";

export const STAFF_COUNTER_PATH = ["system", "healthcareStaffCounter"];

/** @param {number|string} next */
export function formatStaffId(next) {
  const value = Number(next) || 1;
  return `S${String(value).padStart(5, "0")}`;
}

/** Reads the next staff ID that will be assigned on create. */
export async function fetchNextStaffIdPreview() {
  const snap = await getDoc(doc(db, ...STAFF_COUNTER_PATH));
  const next = snap.exists() ? Number(snap.data().next) || 1 : 1;
  return formatStaffId(next);
}

/** Real-time preview of the next staff ID from system/healthcareStaffCounter. */
export function subscribeNextStaffIdPreview(onData, onError) {
  const unsub = onSnapshot(
    doc(db, ...STAFF_COUNTER_PATH),
    (snap) => {
      const next = snap.exists() ? Number(snap.data().next) || 1 : 1;
      onData(formatStaffId(next));
    },
    onError,
  );
  trackFirestoreListener(unsub);
  return unsub;
}
