const admin = require("firebase-admin");
const functions = require("firebase-functions");
const { dispatchMedicationReminders, sendPushToToken } = require("./medication-reminders");

admin.initializeApp();

const db = admin.firestore();

/**
 * Writes auth metadata into users/{uid} when auth user is created.
 * Keeps Firestore profile aligned even if app creation flow fails midway.
 */
exports.onAuthUserCreate = functions.auth.user().onCreate(async (user) => {
  const userRef = db.collection("users").doc(user.uid);
  await userRef.set(
    {
      authUid: user.uid,
      email: user.email || "",
      emailVerified: !!user.emailVerified,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
});

/**
 * Marks profile as inactive when auth user is deleted.
 */
exports.onAuthUserDelete = functions.auth.user().onDelete(async (user) => {
  const userRef = db.collection("users").doc(user.uid);
  await userRef.set(
    {
      status: "Inactive",
      deletedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
});

/**
 * Callable sync endpoint for on-demand consistency.
 * Client can call this after returning from email verification flow.
 */
exports.syncMyAuthProfile = functions.https.onCall(async (_, context) => {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign-in required.");
  }

  const uid = context.auth.uid;
  const user = await admin.auth().getUser(uid);
  await db.collection("users").doc(uid).set(
    {
      authUid: uid,
      email: user.email || "",
      emailVerified: !!user.emailVerified,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  return {
    ok: true,
    uid,
    email: user.email || "",
    emailVerified: !!user.emailVerified,
  };
});

/**
 * Sends FCM medication reminders when clinic clock matches reminderTime.
 * Runs every minute in Asia/Kuala_Lumpur (UTC+8).
 */
exports.dispatchMedicationReminders = functions.pubsub
  .schedule("every 1 minutes")
  .timeZone("Asia/Kuala_Lumpur")
  .onRun(async () => dispatchMedicationReminders());

/**
 * Sends an immediate test push to the signed-in patient's device.
 */
exports.sendTestMedicationPush = functions.https.onCall(async (_data, context) => {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign-in required.");
  }

  const uid = context.auth.uid;
  const userDoc = await db.collection("users").doc(uid).get();
  const data = userDoc.data() || {};
  const token = String(data.fcmToken || "").trim();

  if (!token) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "No fcmToken on your user profile. Tap Notification on the home screen first.",
    );
  }

  await sendPushToToken(
    token,
    "This is a test medication reminder from Aura Guide.",
    { reminderId: "TEST", medicationId: "TEST" },
  );

  return { ok: true };
});

