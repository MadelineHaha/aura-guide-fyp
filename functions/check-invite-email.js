const admin = require("firebase-admin");
const functions = require("firebase-functions");
const { assertEmailAvailableForInvite } = require("./email-uniqueness");

const db = admin.firestore();

async function assertActiveAdmin(uid) {
  const snap = await db.collection("healthcarestaff").doc(uid).get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("permission-denied", "Staff profile not found.");
  }
  const data = snap.data() || {};
  const role = String(data.role || "").trim().toLowerCase();
  if (role !== "admin") {
    throw new functions.https.HttpsError("permission-denied", "Admin access required.");
  }
  if (String(data.status || "").trim() !== "Active") {
    throw new functions.https.HttpsError("permission-denied", "Admin account is not active.");
  }
}

/** Admin-only email availability check using the Admin SDK (no client Firestore rules). */
async function checkInviteEmail(data, context) {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign-in required.");
  }

  await assertActiveAdmin(context.auth.uid);

  const email = String(data?.email || "").trim().toLowerCase();
  if (!email || !email.includes("@")) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid email address is required.",
    );
  }

  try {
    await assertEmailAvailableForInvite(email, { db, admin });
    return { available: true };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) {
      if (error.code === "already-exists") {
        return { available: false, message: error.message };
      }
      throw error;
    }
    throw new functions.https.HttpsError(
      "internal",
      error?.message || "Could not verify the email address.",
    );
  }
}

module.exports = {
  checkInviteEmail,
};
