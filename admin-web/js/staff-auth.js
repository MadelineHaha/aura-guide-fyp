import {
  signInWithEmailAndPassword,
  signOut,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-auth.js";
import { doc, getDoc } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { auth, db } from "./firebase.js";

export const HEALTHCARE_STAFF_COLLECTION = "healthcarestaff";
export const STAFF_SESSION_KEY = "staffSession";
export const LOGIN_ERROR_MESSAGE = "The email or password is invalid.";

export function saveStaffSession(profile) {
  sessionStorage.setItem(STAFF_SESSION_KEY, JSON.stringify(profile));
}

export function getStaffSession() {
  const raw = sessionStorage.getItem(STAFF_SESSION_KEY);
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function clearStaffSession() {
  sessionStorage.removeItem(STAFF_SESSION_KEY);
}

export async function loadStaffProfile(uid) {
  const snap = await getDoc(doc(db, HEALTHCARE_STAFF_COLLECTION, uid));
  if (!snap.exists()) {
    return null;
  }
  return { uid, ...snap.data() };
}

export async function verifyActiveStaff(uid) {
  const profile = await loadStaffProfile(uid);
  if (!profile) {
    await signOut(auth);
    throw new Error(LOGIN_ERROR_MESSAGE);
  }
  if (profile.status !== "Active") {
    await signOut(auth);
    throw new Error(LOGIN_ERROR_MESSAGE);
  }
  return profile;
}

export async function signInStaff(email, password) {
  const credential = await signInWithEmailAndPassword(auth, email.trim(), password);
  const profile = await verifyActiveStaff(credential.user.uid);
  saveStaffSession(profile);
  return profile;
}

export async function signOutStaff() {
  clearStaffSession();
  await signOut(auth);
}

export function getAuthErrorMessage() {
  return LOGIN_ERROR_MESSAGE;
}
