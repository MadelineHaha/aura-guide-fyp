const admin = require("firebase-admin");
const functions = require("firebase-functions");
const { dispatchMedicationReminders, sendPushToToken, recordMedicationPatientNotification } = require("./medication-reminders");
const {
  createDailyReminderInstances,
  ensureMedicationSlotReminders,
  runDailyMedicationReminderJob,
} = require("./medication-daily-instances");
const { inviteHealthcareStaff } = require("./staff-invite");
const { checkInviteEmail } = require("./check-invite-email");
const {
  invitePatient,
  verifyPatientOnboardingPin,
  completePatientOnboarding,
} = require("./patient-invite");
const { inviteCaregiver } = require("./caregiver-invite");
const { broadcastAnnouncement } = require("./broadcast-announcement");
const { markOverdueAppointmentsAsMissed } = require("./appointment-missed");

admin.initializeApp();

const db = admin.firestore();

/**
 * Writes auth metadata into users/{uid} when auth user is created.
 * Keeps Firestore profile aligned even if app creation flow fails midway.
 */
exports.onAuthUserCreate = functions.auth.user().onCreate(async (user) => {
  const staffRef = db.collection("healthcarestaff").doc(user.uid);
  for (let attempt = 0; attempt < 6; attempt += 1) {
    const staffSnap = await staffRef.get();
    if (staffSnap.exists) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }

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
 * Creates today's dose rows and finalizes yesterday's pending doses as Missed.
 * Runs daily at 00:05 clinic time (Asia/Kuala_Lumpur).
 */
exports.createDailyMedicationReminders = functions.pubsub
  .schedule("5 0 * * *")
  .timeZone("Asia/Kuala_Lumpur")
  .onRun(async () => runDailyMedicationReminderJob());

/**
 * Marks overdue appointments (not Done/Cancelled) as Missed in Firestore.
 * Runs every 15 minutes in Asia/Kuala_Lumpur.
 */
exports.markMissedAppointments = functions.pubsub
  .schedule("every 15 minutes")
  .timeZone("Asia/Kuala_Lumpur")
  .onRun(async () => {
    const updated = await markOverdueAppointmentsAsMissed();
    console.log(`Marked ${updated} overdue appointment(s) as Missed.`);
    return null;
  });

/**
 * Ensures today's medicationreminders dose rows exist for the signed-in patient.
 */
exports.syncDailyMedicationReminders = functions.https.onCall(async (_data, context) => {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign-in required.");
  }

  const userDoc = await db.collection("users").doc(context.auth.uid).get();
  const userData = userDoc.data() || {};
  const patientUserId = String(
    userData.userId || userData.userID || userData.patientId || "",
  ).trim();

  if (!patientUserId) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Patient User ID is missing on your profile.",
    );
  }

  const result = await createDailyReminderInstances({ patientUserId });
  return { ok: true, ...result };
});

/**
 * Creates missing slot-template medicationreminders rows for the signed-in patient.
 */
exports.ensureMedicationSlotReminders = functions.https.onCall(async (_data, context) => {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign-in required.");
  }

  const userDoc = await db.collection("users").doc(context.auth.uid).get();
  const userData = userDoc.data() || {};
  const patientUserId = String(
    userData.userId || userData.userID || userData.patientId || "",
  ).trim();

  if (!patientUserId) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Patient User ID is missing on your profile.",
    );
  }

  const slotResult = await ensureMedicationSlotReminders(patientUserId);
  const dailyResult = await createDailyReminderInstances({ patientUserId });
  return { ok: true, ...slotResult, dailyCreated: dailyResult.created };
});

/**
 * Persists a medication reminder notification to patientnotifications.
 * Called by the mobile app when a local reminder fires (no Blaze scheduler required).
 */
exports.recordMedicationPatientNotification = functions.https.onCall(async (data, context) => {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign-in required.");
  }

  const userDoc = await db.collection("users").doc(context.auth.uid).get();
  const userData = userDoc.data() || {};
  const patientUserId = String(
    userData.userId || userData.userID || userData.patientId || "",
  ).trim();

  if (!patientUserId) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Patient User ID is missing on your profile.",
    );
  }

  const reminderId = String(data?.reminderId || "").trim();
  const kind = String(data?.kind || "reminder").trim();

  if (!reminderId) {
    throw new functions.https.HttpsError("invalid-argument", "reminderId is required.");
  }

  try {
    const result = await recordMedicationPatientNotification({
      patientUserId,
      reminderId,
      kind,
    });
    return { ok: true, ...result };
  } catch (error) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      error?.message || "Could not record notification.",
    );
  }
});

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

/**
 * Admin-only: create doctor/therapist/caregiver without a password and email a setup link.
 */
exports.inviteHealthcareStaff = functions.https.onCall(inviteHealthcareStaff);

/**
 * Admin-only: verify an invite email is not already used in users / staff / caregiver.
 */
exports.checkInviteEmail = functions.https.onCall(checkInviteEmail);

/**
 * Admin-only: create family/guardian caregiver in caregiver collection.
 */
exports.inviteCaregiver = functions.https.onCall(inviteCaregiver);

/**
 * Admin-only: create patient without a password and assign a 4-digit onboarding PIN.
 */
exports.invitePatient = functions.https.onCall(invitePatient);

/**
 * Mobile onboarding: verify User ID + PIN and return a custom auth token.
 */
exports.verifyPatientOnboardingPin = functions.https.onCall(verifyPatientOnboardingPin);

/**
 * Mobile onboarding: clear PIN after voice profile setup.
 */
exports.completePatientOnboarding = functions.https.onCall(completePatientOnboarding);

exports.broadcastAnnouncement = broadcastAnnouncement;
