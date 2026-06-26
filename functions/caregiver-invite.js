const admin = require("firebase-admin");
const functions = require("firebase-functions");
const { assertEmailAvailableForInvite } = require("./email-uniqueness");

const db = admin.firestore();
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

async function sendPasswordSetupEmail(email, continueUrl) {
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

function normalizeConnectedPatients(value) {
  if (!Array.isArray(value)) return [];
  return value
    .map((entry) => ({
      patientDocId: String(entry?.patientDocId || entry?.id || "").trim(),
      userId: String(entry?.userId || entry?.userID || "").trim().toUpperCase(),
      name: String(entry?.name || "").trim(),
    }))
    .filter((entry) => entry.patientDocId && entry.userId);
}

async function syncPatientCaregiverLinks({
  caregiverUid,
  caregiverName,
  caregiverId,
  connectedPatients,
}) {
  const batch = db.batch();
  for (const patient of connectedPatients) {
    const patientRef = db.collection("users").doc(patient.patientDocId);
    batch.set(
      patientRef,
      {
        assignedCaregiverId: caregiverUid,
        assignedCaregiverName: caregiverName,
        assignedCaregiverPublicId: caregiverId,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  }
  if (!connectedPatients.length) return;
  await batch.commit();
}

/**
 * Admin-only caregiver invite:
 * Creates Firebase Auth + caregiver/{uid} profile with linked patients.
 */
async function inviteCaregiver(data, context) {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign-in required.");
  }

  await assertActiveAdmin(context.auth.uid);

  const name = String(data?.name || "").trim();
  const email = String(data?.email || "").trim().toLowerCase();
  const phone = String(data?.phone || "").trim();
  const continueUrl = String(data?.continueUrl || "").trim();
  const connectedPatients = normalizeConnectedPatients(data?.connectedPatients);

  if (!name || !email || !email.includes("@")) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid name and email are required.",
    );
  }
  if (connectedPatients.length === 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Select at least one patient to connect to this caregiver.",
    );
  }

  await assertEmailAvailableForInvite(email, { db, admin });

  let authUid;
  try {
    const userRecord = await admin.auth().createUser({
      email,
      displayName: name,
      emailVerified: false,
    });
    authUid = userRecord.uid;
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

  const caregiverRef = db.collection("caregiver").doc(authUid);
  const counterRef = db.collection("system").doc("caregiverCounter");
  let caregiverId;

  try {
    caregiverId = await db.runTransaction(async (transaction) => {
      const counterSnap = await transaction.get(counterRef);
      const next = counterSnap.exists ? Number(counterSnap.data().next) || 1 : 1;
      const assignedCaregiverId = `V${String(next).padStart(5, "0")}`;
      const connectedUserIds = connectedPatients.map((entry) => entry.userId);

      transaction.set(counterRef, { next: next + 1 }, { merge: true });
      transaction.set(caregiverRef, {
        caregiverId: assignedCaregiverId,
        caregiverID: assignedCaregiverId,
        name,
        email,
        phone,
        role: "caregiver",
        status: "Active",
        authUid,
        invitePending: true,
        accountActivated: false,
        connectedUserIds,
        connectedPatients,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        registeredByStaff: context.auth.uid,
      });

      return assignedCaregiverId;
    });
  } catch (error) {
    try {
      await admin.auth().deleteUser(authUid);
    } catch (_) {
      // Best-effort cleanup.
    }
    throw new functions.https.HttpsError(
      "internal",
      error?.message || "Could not save the caregiver profile.",
    );
  }

  try {
    await syncPatientCaregiverLinks({
      caregiverUid: authUid,
      caregiverName: name,
      caregiverId,
      connectedPatients,
    });
  } catch (error) {
    console.warn("Could not sync patient caregiver links:", error?.message || error);
  }

  let emailSent = false;
  try {
    await sendPasswordSetupEmail(email, continueUrl);
    emailSent = true;
  } catch (error) {
    console.warn("Caregiver created but setup email failed:", error?.message || error);
  }

  await caregiverRef.set(
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
    uid: authUid,
    caregiverId,
    connectedUserIds: connectedPatients.map((entry) => entry.userId),
    message: emailSent
      ? "A password setup email has been sent. The account will be ready after they open the link and set their password."
      : "Caregiver profile created but the setup email could not be sent. Resend the invite from administration.",
  };
}

module.exports = {
  inviteCaregiver,
};
