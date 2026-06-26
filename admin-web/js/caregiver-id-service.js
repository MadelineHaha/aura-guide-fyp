import { doc, getDoc, onSnapshot } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { trackFirestoreListener } from "./firestore-realtime.js";

export const CAREGIVER_COUNTER_PATH = ["system", "caregiverCounter"];

/** @param {number|string} next */
export function formatCaregiverId(next) {
  const value = Number(next) || 1;
  return `V${String(value).padStart(5, "0")}`;
}

export async function fetchNextCaregiverIdPreview() {
  const snap = await getDoc(doc(db, ...CAREGIVER_COUNTER_PATH));
  const next = snap.exists() ? Number(snap.data().next) || 1 : 1;
  return formatCaregiverId(next);
}

export function subscribeNextCaregiverIdPreview(onData, onError) {
  const unsub = onSnapshot(
    doc(db, ...CAREGIVER_COUNTER_PATH),
    (snap) => {
      const next = snap.exists() ? Number(snap.data().next) || 1 : 1;
      onData(formatCaregiverId(next));
    },
    onError,
  );
  trackFirestoreListener(unsub);
  return unsub;
}
