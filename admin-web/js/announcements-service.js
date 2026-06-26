import {
  addDoc,
  collection,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  getDocs,
  writeBatch,
  doc,
  setDoc,
  updateDoc,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { trackFirestoreListener } from "./firestore-realtime.js";

export const ANNOUNCEMENTS_COLLECTION = "announcements";

export const ANNOUNCEMENT_TYPES = [
  "Broadcast Message",
  "Clinic Closure Notice",
  "Maintenance Announcement",
  "Emergency Announcement",
];

function mapAnnouncementDoc(docSnap) {
  const data = docSnap.data() || {};
  const created = data.createdAt?.toDate?.() || null;
  return {
    id: docSnap.id,
    type: data.type || "Broadcast Message",
    title: data.title || "",
    message: data.message || "",
    createdBy: data.createdByName || "Admin",
    createdAtLabel: created
      ? created.toLocaleString("en-GB", {
          day: "numeric",
          month: "short",
          year: "numeric",
          hour: "2-digit",
          minute: "2-digit",
        })
      : "—",
    timestamp: data.createdAt || null,
    status: data.status || "Active",
  };
}

export function subscribeAnnouncements(onData, onError) {
  const q = query(
    collection(db, ANNOUNCEMENTS_COLLECTION),
    orderBy("createdAt", "desc"),
  );
  const unsub = onSnapshot(
    q,
    (snap) => {
      const items = snap.docs
        .map(mapAnnouncementDoc)
        .filter((a) => a.status !== "Inactive");
      onData(items);
    },
    onError,
  );
  trackFirestoreListener(unsub);
  return unsub;
}

export async function createAnnouncement({ type, title, message, createdByName }) {
  await addDoc(collection(db, ANNOUNCEMENTS_COLLECTION), {
    type: String(type || "").trim(),
    title: String(title || "").trim(),
    message: String(message || "").trim(),
    createdByName: String(createdByName || "Admin").trim(),
    createdAt: serverTimestamp(),
    status: "Active",
  });
}

export async function updateAnnouncement(id, { type, title, message }) {
  const docRef = doc(db, ANNOUNCEMENTS_COLLECTION, id);
  await updateDoc(docRef, {
    type: String(type || "").trim(),
    title: String(title || "").trim(),
    message: String(message || "").trim(),
  });
}

export async function deleteAnnouncement(id) {
  const docRef = doc(db, ANNOUNCEMENTS_COLLECTION, id);
  await updateDoc(docRef, {
    status: "Inactive",
  });
}
