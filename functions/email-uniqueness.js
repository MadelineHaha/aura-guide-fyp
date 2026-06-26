const functions = require("firebase-functions");

const COLLECTION_CHECKS = [
  { name: "users", label: "patient" },
  { name: "healthcarestaff", label: "staff member" },
  { name: "caregiver", label: "caregiver" },
  { name: "caregivers", label: "caregiver" },
];

function normalizeEmail(email) {
  return String(email || "").trim().toLowerCase();
}

async function emailExistsInCollection(db, collectionName, email) {
  const snap = await db
    .collection(collectionName)
    .where("email", "==", email)
    .limit(1)
    .get();
  return !snap.empty;
}

/**
 * Ensures an email is not used in users, healthcarestaff, caregiver, or Firebase Auth.
 * @throws {functions.https.HttpsError} already-exists when taken
 */
async function assertEmailAvailableForInvite(email, { db, admin }) {
  const normalized = normalizeEmail(email);
  if (!normalized || !normalized.includes("@")) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid email address is required.",
    );
  }

  for (const { name, label } of COLLECTION_CHECKS) {
    const exists = await emailExistsInCollection(db, name, normalized);
    if (exists) {
      throw new functions.https.HttpsError(
        "already-exists",
        `This email is already registered as a ${label}. Please use a different email.`,
      );
    }
  }

  try {
    await admin.auth().getUserByEmail(normalized);
    throw new functions.https.HttpsError(
      "already-exists",
      "This email is already registered in the system. Please use a different email.",
    );
  } catch (error) {
    if (error?.code === "auth/user-not-found") {
      return;
    }
    if (error instanceof functions.https.HttpsError) {
      throw error;
    }
    throw error;
  }
}

module.exports = {
  assertEmailAvailableForInvite,
  normalizeInviteEmail: normalizeEmail,
};
