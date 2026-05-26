import {
  collection,
  doc,
  getDocs,
  runTransaction,
  serverTimestamp,
  Timestamp,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { auth, db } from "./firebase.js";

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
  return {
    id: docSnap.id,
    name: data.name || "—",
    patientId: data.userId || "—",
    age: birthDate ? computeAge(birthDate) : "—",
    condition: data.condition || "—",
    lastVisit: formatLastVisit(data.lastVisit || data.createdAt),
    status: displayStatus(data),
    email: data.email || "",
    address: data.address || "",
    birthDate,
  };
}

export async function fetchPatients() {
  const snap = await getDocs(collection(db, USERS_COLLECTION));
  const patients = snap.docs.map(mapUserDoc);
  patients.sort((a, b) => a.name.localeCompare(b.name));
  return patients;
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
      accessibilityPreferences: "",
      status: "Active",
      createdAt: serverTimestamp(),
      registeredByStaff: staffUid,
    });
  });

  return newRef.id;
}
