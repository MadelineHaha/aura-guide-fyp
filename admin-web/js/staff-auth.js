import {
  signInWithEmailAndPassword,
  signOut,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-auth.js";
import { doc, getDoc } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { auth, db } from "./firebase.js";
import { LOG_ACTIONS } from "./activity-log-actions.js";
import { logStaffActivity, logSecurityAudit } from "./activity-logs-service.js";

export const HEALTHCARE_STAFF_COLLECTION = "healthcarestaff";
export const STAFF_SESSION_KEY = "staffSession";
export const LOGIN_ERROR_MESSAGE = "Invalid credential";

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
  void logStaffActivity({
    action: LOG_ACTIONS.LOGIN,
    details: "Successful login to staff portal.",
    type: "info",
  });
  return profile;
}

export async function signOutStaff() {
  try {
    await logStaffActivity({
      action: LOG_ACTIONS.LOGOUT,
      details: "Signed out of staff portal.",
      type: "info",
    });
  } catch (error) {
    console.warn("Could not write logout activity log:", error);
  }
  clearStaffSession();
  await signOut(auth);
}

export function getAuthErrorMessage(error) {
  const code = error?.code;
  if (
    code === "auth/invalid-credential" ||
    code === "auth/wrong-password" ||
    code === "auth/user-not-found" ||
    code === "auth/invalid-email"
  ) {
    return LOGIN_ERROR_MESSAGE;
  }
  if (code === "permission-denied") {
    return "Could not load your staff profile. Check Firestore rules for healthcarestaff.";
  }
  return error?.message || LOGIN_ERROR_MESSAGE;
}
