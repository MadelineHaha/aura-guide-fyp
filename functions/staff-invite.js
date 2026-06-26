const admin = require("firebase-admin");
const functions = require("firebase-functions");
const { assertEmailAvailableForInvite } = require("./email-uniqueness");

const db = admin.firestore();

const STAFF_ROLES = new Set(["doctor", "therapist"]);
const WEB_API_KEY = "AIzaSyCQlrH2N3KG64xQhMQEkSLy-QPkfVzuU6k";

function normalizeRole(role) {
  return String(role || "").trim().toLowerCase();
}

async function assertActiveAdmin(uid) {
  const snap = await db.collection("healthcarestaff").doc(uid).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("permission-denied", "Staff profile not found.");
  }
  const data = snap.data() || {};
  if (normalizeRole(data.role) !== "admin") {
    throw new functions.https.HttpsError("permission-denied", "Admin access required.");
  }
  if (String(data.status || "").trim() !== "Active") {
    throw new functions.https.HttpsError("permission-denied", "Admin account is not active.");
  }
}

async function sendStaffPasswordSetupEmail(email, continueUrl) {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=${WEB_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        requestType: "PASSWORD_RESET",
        email: String(email || "").trim().toLowerCase(),
        continueUrl: continueUrl || undefined,
      }),
    },
  );

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message =
      payload?.error?.message ||
      "Could not send the account setup email. Try again later.";
    throw new functions.https.HttpsError("internal", message);
  }
}

/**
 * Admin-only invite flow:
 * 1. Create Firebase Auth user without a password
 * 2. Create healthcarestaff/{uid} profile
 * 3. Email a password-setup link (Firebase password reset template)
 */
async function inviteHealthcareStaff(data, context) {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign-in required.");
  }

  await assertActiveAdmin(context.auth.uid);

  const name = String(data?.name || "").trim();
  const email = String(data?.email || "").trim().toLowerCase();
  const role = normalizeRole(data?.role);
  const specialty = String(data?.specialty || "").trim();
  const phone = String(data?.phone || "").trim();
  const continueUrl = String(data?.continueUrl || "").trim();

  if (!name || !email || !email.includes("@")) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid name and email are required.",
    );
  }
  if (!STAFF_ROLES.has(role)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Role must be doctor or therapist.",
    );
  }

  await assertEmailAvailableForInvite(email, { db, admin });

  let uid;
  try {
    const userRecord = await admin.auth().createUser({
      email,
      displayName: name,
      emailVerified: false,
    });
    uid = userRecord.uid;
  } catch (error) {
    if (error?.code === "auth/email-already-exists") {
      throw new functions.https.HttpsError(
        "already-exists",
        "An account with this email already exists.",
      );
    }
    throw new functions.https.HttpsError(
      "internal",
      error?.message || "Could not create the auth account.",
    );
  }

  const staffRef = db.collection("healthcarestaff").doc(uid);
  const counterRef = db.collection("system").doc("healthcareStaffCounter");

  try {
    await db.runTransaction(async (transaction) => {
      const counterSnap = await transaction.get(counterRef);
      const next = counterSnap.exists
        ? Number(counterSnap.data().next) || 1
        : 1;
      const staffID = `S${String(next).padStart(5, "0")}`;

      transaction.set(counterRef, { next: next + 1 }, { merge: true });
      transaction.set(staffRef, {
        staffID,
        name,
        email,
        role,
        specialty,
        phone,
        status: "Active",
        authUid: uid,
        invitePending: true,
        accountActivated: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        invitedBy: context.auth.uid,
      });
    });
  } catch (error) {
    await admin.auth().deleteUser(uid).catch(() => {});
    throw new functions.https.HttpsError(
      "internal",
      error?.message || "Could not save the staff profile.",
    );
  }

  let emailSent = false;
  try {
    await sendStaffPasswordSetupEmail(email, continueUrl);
    emailSent = true;
  } catch (error) {
    console.warn("Staff account created but setup email failed:", error?.message || error);
  }

  await staffRef.set(
    {
      invitePending: true,
      accountActivated: false,
      inviteEmailSentAt: emailSent
        ? admin.firestore.FieldValue.serverTimestamp()
        : null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return {
    ok: true,
    uid,
    email,
    role,
    message: emailSent
      ? "A password setup email has been sent. The account will be ready after they open the link and set their password."
      : "Account created but the setup email could not be sent. Resend the invite from administration.",
  };
}

module.exports = {
  inviteHealthcareStaff,
};
