import { initializeApp } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-app.js";
import {
  createUserWithEmailAndPassword,
  getAuth,
  signOut,
  inMemoryPersistence,
  setPersistence,
  deleteUser,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-auth.js";
import {
  doc,
  collection,
  setDoc,
  deleteDoc,
  runTransaction,
  serverTimestamp,
  updateDoc,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { firebaseConfig } from "./firebase-config.js";
import { auth, db } from "./firebase.js";
import { HEALTHCARE_STAFF_COLLECTION } from "./staff-auth.js";
import { STAFF_COUNTER_PATH, formatStaffId } from "./staff-id-service.js";
import {
  CAREGIVER_COUNTER_PATH,
  formatCaregiverId,
} from "./caregiver-id-service.js";
import { sendInviteLinkEmail } from "./identity-email.js";
import { humanizeIdentityError } from "./callable-error.js";
import { assertEmailAvailableForInvite } from "./email-uniqueness-service.js";

const CAREGIVER_COLLECTION = "caregiver";

async function syncPatientCaregiverLinks({
  caregiverUid,
  caregiverName,
  caregiverId,
  connectedPatients,
}) {
  for (const patient of connectedPatients) {
    await updateDoc(doc(db, "users", patient.patientDocId), {
      assignedCaregiverId: caregiverUid,
      assignedCaregiverName: caregiverName,
      assignedCaregiverPublicId: caregiverId,
      updatedAt: serverTimestamp(),
    });
  }
}

/** Client-side fallback when inviteHealthcareStaff Cloud Function is unavailable. */
export async function createStaffDirect({
  name,
  email,
  role,
  phone = "",
  continueUrl = "",
}) {
  const trimmedName = String(name || "").trim();
  const normalizedRole = String(role || "").trim().toLowerCase();
  if (!trimmedName) throw new Error("Name is required.");
  if (!["doctor", "therapist"].includes(normalizedRole)) throw new Error("Role must be doctor or therapist.");

  const normalizedEmail = String(email || "").trim().toLowerCase();
  await assertEmailAvailableForInvite(normalizedEmail);

  // Generate a random temporary password
  const randomPassword = Math.random().toString(36).slice(-8) + Math.random().toString(36).slice(-8);

  // 1. Create the user using the Identity Toolkit REST API (avoids signing out the admin)
  const signupRes = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${firebaseConfig.apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: normalizedEmail, password: randomPassword, returnSecureToken: false }),
  });
  const signupData = await signupRes.json().catch(() => ({}));
  if (!signupRes.ok) {
    if (signupData?.error?.message === "EMAIL_EXISTS") {
      throw new Error("An account with this email already exists.");
    }
    throw new Error(signupData?.error?.message || "Could not create the auth account.");
  }
  const authUid = signupData.localId;

  // 2. Create the Firestore profile
  const inviteRef = doc(db, "healthcarestaff", authUid);
  const counterRef = doc(db, ...STAFF_COUNTER_PATH);
  
  await runTransaction(db, async (transaction) => {
    const counterSnap = await transaction.get(counterRef);
    const next = counterSnap.exists() ? Number(counterSnap.data().next) || 1 : 1;
    const staffId = formatStaffId(next);
    
    transaction.set(counterRef, { next: next + 1 }, { merge: true });
    transaction.set(inviteRef, {
      staffId: staffId,
      name: trimmedName,
      email: normalizedEmail,
      role: normalizedRole,
      phone: String(phone || "").trim(),
      status: "Active",
      invitePending: true,
      accountActivated: false,
      createdAt: serverTimestamp(),
    });
  });

  // 3. Send Password Reset Email
  let emailSent = false;
  try {
    const { sendPasswordSetupEmail } = await import("./identity-email.js");
    await sendPasswordSetupEmail(normalizedEmail, continueUrl);
    emailSent = true;
  } catch (error) {
    throw new Error(error?.message || "Could not send the password setup email. Please try again.");
  }

  return { inviteId: authUid, emailSent };
}

/** Client-side fallback when inviteCaregiver Cloud Function is unavailable. */
export async function createCaregiverDirect({
  name,
  email,
  phone = "",
  connectedPatients = [],
  continueUrl = "",
}) {
  const trimmedName = String(name || "").trim();
  const trimmedPatients = (Array.isArray(connectedPatients) ? connectedPatients : [])
    .map((entry) => ({
      patientDocId: String(entry.patientDocId || entry.id || "").trim(),
      userId: String(entry.userId || entry.userID || "").trim().toUpperCase(),
      name: String(entry.name || "").trim(),
    }))
    .filter((entry) => entry.patientDocId && entry.userId);

  if (!trimmedName) throw new Error("Name is required.");
  if (trimmedPatients.length === 0) throw new Error("Select at least one patient to connect.");

  const normalizedEmail = String(email || "").trim().toLowerCase();
  await assertEmailAvailableForInvite(normalizedEmail);

  // Generate a random temporary password
  const randomPassword = Math.random().toString(36).slice(-8) + Math.random().toString(36).slice(-8);

  // 1. Create the user using the Identity Toolkit REST API
  const signupRes = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${firebaseConfig.apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: normalizedEmail, password: randomPassword, returnSecureToken: false }),
  });
  const signupData = await signupRes.json().catch(() => ({}));
  if (!signupRes.ok) {
    if (signupData?.error?.message === "EMAIL_EXISTS") {
      throw new Error("An account with this email already exists.");
    }
    throw new Error(signupData?.error?.message || "Could not create the auth account.");
  }
  const authUid = signupData.localId;

  // 2. Create the Firestore profile
  const inviteRef = doc(db, "caregiver", authUid);
  const counterRef = doc(db, ...CAREGIVER_COUNTER_PATH);
  
  await runTransaction(db, async (transaction) => {
    const counterSnap = await transaction.get(counterRef);
    const next = counterSnap.exists() ? Number(counterSnap.data().next) || 1 : 1;
    const caregiverId = formatCaregiverId(next);
    
    transaction.set(counterRef, { next: next + 1 }, { merge: true });
    transaction.set(inviteRef, {
      caregiverId: caregiverId,
      caregiverID: caregiverId,
      name: trimmedName,
      email: normalizedEmail,
      role: "caregiver",
      phone: String(phone || "").trim(),
      connectedPatients: trimmedPatients,
      connectedUserIds: trimmedPatients.map(p => p.userId),
      status: "Active",
      invitePending: true,
      accountActivated: false,
      createdAt: serverTimestamp(),
    });
  });

  // 3. Send Password Reset Email
  let emailSent = false;
  try {
    const { sendPasswordSetupEmail } = await import("./identity-email.js");
    await sendPasswordSetupEmail(normalizedEmail, continueUrl);
    emailSent = true;
  } catch (error) {
    throw new Error(error?.message || "Could not send the password setup email. Please try again.");
  }

  return { inviteId: authUid, emailSent };
}
