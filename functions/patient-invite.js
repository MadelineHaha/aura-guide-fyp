const admin = require("firebase-admin");
const functions = require("firebase-functions");
const crypto = require("crypto");

const db = admin.firestore();

function normalizeRole(role) {
  return String(role || "").trim().toLowerCase();
}

function normalizePassphrase(value) {
  return String(value || "").trim().toLowerCase().replace(/\s+/g, " ");
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

function generateOnboardingPin() {
  return String(crypto.randomInt(1000, 10000));
}

const VOICE_AUTH_EMAIL_DOMAIN = "auraguide.local";

function voiceEmailFor(authUid) {
  return `voice_${String(authUid || "").trim()}@${VOICE_AUTH_EMAIL_DOMAIN}`;
}

function generateVoiceAuthPassword() {
  const upper = "ABCDEFGHJKLMNPQRSTUVWXYZ";
  const lower = "abcdefghjkmnpqrstuvwxyz";
  const digits = "23456789";
  const special = "!@#$%^&*";
  const all = upper + lower + digits + special;
  const chars = [
    upper[crypto.randomInt(upper.length)],
    lower[crypto.randomInt(lower.length)],
    digits[crypto.randomInt(digits.length)],
    special[crypto.randomInt(special.length)],
  ];
  for (let i = 0; i < 12; i += 1) {
    chars.push(all[crypto.randomInt(all.length)]);
  }
  for (let i = chars.length - 1; i > 0; i -= 1) {
    const j = crypto.randomInt(i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join("");
}

async function createVoicePatientAuthAccount({ displayName }) {
  const password = generateVoiceAuthPassword();
  let authUid;
  try {
    const userRecord = await admin.auth().createUser({
      password,
      displayName: String(displayName || "").trim() || undefined,
      emailVerified: false,
    });
    authUid = userRecord.uid;
    const email = voiceEmailFor(authUid);
    await admin.auth().updateUser(authUid, { email });
    return { authUid, email, password };
  } catch (error) {
    if (authUid) {
      try {
        await admin.auth().deleteUser(authUid);
      } catch (_) {
        // Best-effort cleanup when email assignment fails.
      }
    }
    if (error?.code === "auth/email-already-exists") {
      throw new functions.https.HttpsError(
        "already-exists",
        "An account with this email already exists.",
      );
    }
    throw new functions.https.HttpsError(
      "internal",
      error?.message || "Could not create the patient auth account.",
    );
  }
}

function dateOnlyUtc(dateStr) {
  const [y, m, d] = String(dateStr || "").split("-").map(Number);
  if (!y || !m || !d) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid birthdate is required.",
    );
  }
  return new Date(Date.UTC(y, m - 1, d));
}

function todayDateString() {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

async function findUserDocByPublicId(publicUserId) {
  const trimmed = String(publicUserId || "").trim().toUpperCase();
  if (!trimmed) return null;

  for (const field of ["userId", "userID"]) {
    const snap = await db
      .collection("users")
      .where(field, "==", trimmed)
      .limit(1)
      .get();
    if (!snap.empty) {
      return snap.docs[0];
    }
  }
  return null;
}

async function findPendingUserDocByPin(pin) {
  const trimmed = String(pin || "").trim();
  if (!/^\d{4}$/.test(trimmed)) return null;

  for (const field of ["onboardingPin", "pin"]) {
    let snap = await db.collection("users").where(field, "==", trimmed).limit(5).get();
    let pendingDocs = snap.docs.filter(
      (doc) => doc.data()?.onboardingPending === true,
    );

    if (pendingDocs.length === 0) {
      const numPin = Number(trimmed);
      if (!isNaN(numPin)) {
        snap = await db.collection("users").where(field, "==", numPin).limit(5).get();
        pendingDocs = snap.docs.filter(
          (doc) => doc.data()?.onboardingPending === true,
        );
      }
    }

    if (pendingDocs.length === 0) continue;
    if (pendingDocs.length > 1) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Multiple accounts share this PIN. Contact your clinic administrator.",
      );
    }
    return pendingDocs[0];
  }
  return null;
}

function resolveStoredPin(profile) {
  return String(profile?.onboardingPin || profile?.pin || "").trim();
}

function buildVoiceProfile({ voicePassphrase, voiceprintVector, voiceFeatures }) {
  const passphrase = normalizePassphrase(voicePassphrase);
  if (!passphrase) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A voice passphrase is required.",
    );
  }

  const vector = Array.isArray(voiceprintVector)
    ? voiceprintVector.filter((value) => typeof value === "number")
    : [];
  if (vector.length === 0) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "A valid voice profile is required.",
    );
  }

  const features =
    voiceFeatures && typeof voiceFeatures === "object" ? voiceFeatures : {};

  return {
    passphrase,
    voiceprintVector: vector,
    voiceFeatures: features,
    embeddingVersion: 1,
  };
}

/**
 * Admin-only patient invite:
 * Creates Firebase Auth (voice_{uid}@auraguide.local) and a pending users/{authUid} profile with PIN.
 */
async function invitePatient(data, context) {
  if (!context.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Sign-in required.");
  }

  await assertActiveAdmin(context.auth.uid);

  const name = String(data?.name || "").trim();
  const birthDate = String(data?.birthDate || "").trim();
  const address = String(data?.address || "").trim();
  const gender = String(data?.gender || "").trim();
  const phone = String(data?.phone || "").trim();

  if (!name) {
    throw new functions.https.HttpsError("invalid-argument", "Name is required.");
  }
  if (!birthDate || !address) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Birthdate and address are required.",
    );
  }
  if (birthDate > todayDateString()) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Birthdate cannot be in the future.",
    );
  }

  const birthDateValue = dateOnlyUtc(birthDate);
  const onboardingPin = generateOnboardingPin();
  const { authUid, email, password } = await createVoicePatientAuthAccount({
    displayName: name,
  });
  const patientRef = db.collection("users").doc(authUid);
  const counterRef = db.collection("system").doc("userCounter");

  let userId;
  try {
    userId = await db.runTransaction(async (transaction) => {
      const counterSnap = await transaction.get(counterRef);
      const next = counterSnap.exists ? Number(counterSnap.data().next) || 1 : 1;
      const assignedUserId = `U${String(next).padStart(5, "0")}`;

      transaction.set(counterRef, { next: next + 1 }, { merge: true });
      const defaultSettings = {
        fontScale: 1.0,
        notificationsEnabled: true,
        fallDetectionEnabled: true,
        voiceAssistantEnabled: true,
        languageCode: "en",
      };
      transaction.set(patientRef, {
        userId: assignedUserId,
        name,
        email,
        authUid,
        voiceAuthPassword: password,
        birthDate: admin.firestore.Timestamp.fromDate(birthDateValue),
        address,
        gender,
        phone,
        voiceProfile: "",
        emergencyContact: "",
        settings: defaultSettings,
        status: "Active",
        pin: onboardingPin,
        onboardingPin,
        onboardingPending: true,
        emailPending: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        registeredByStaff: context.auth.uid,
      });
      transaction.set(db.collection("onboardingPins").doc(onboardingPin), {
        pin: onboardingPin,
        pendingDocId: authUid,
        userId: assignedUserId,
        authUid,
        onboardingPending: true,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return assignedUserId;
    });
  } catch (error) {
    try {
      await admin.auth().deleteUser(authUid);
    } catch (_) {
      // Best-effort cleanup when Firestore write fails.
    }
    throw new functions.https.HttpsError(
      "internal",
      error?.message || "Could not save the patient profile.",
    );
  }

  return {
    ok: true,
    pendingDocId: authUid,
    authUid,
    email,
    userId,
    pin: onboardingPin,
    onboardingPin,
    message:
      "Patient account created. Share the User ID and 4-digit PIN with the patient for first-time app setup.",
  };
}

/**
 * Pre-auth onboarding: verify User ID + PIN.
 * Returns a custom token only for legacy accounts that already have Auth.
 */
async function verifyPatientOnboardingPin(data, context) {
  const publicUserId = String(data?.userId || data?.userID || "").trim().toUpperCase();
  const pin = String(data?.pin || "").trim();

  if (!publicUserId || !/^\d{4}$/.test(pin)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Enter your User ID and a 4-digit PIN.",
    );
  }

  const userDoc = await findUserDocByPublicId(publicUserId);
  if (!userDoc) {
    throw new functions.https.HttpsError("not-found", "Invalid User ID or PIN.");
  }

  const profile = userDoc.data() || {};
  if (String(profile.status || "Active").trim() !== "Active") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "This account is inactive. Contact your clinic administrator.",
    );
  }
  if (profile.onboardingPending !== true) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "This account has already been set up. Please sign in instead.",
    );
  }
  if (resolveStoredPin(profile) !== pin) {
    throw new functions.https.HttpsError("not-found", "Invalid User ID or PIN.");
  }

  const authUid = String(profile.authUid || "").trim();
  if (authUid) {
    const token = await admin.auth().createCustomToken(authUid);
    return {
      ok: true,
      requiresVoiceActivation: true,
      token,
      uid: authUid,
      name: String(profile.name || "").trim(),
      userId: publicUserId,
    };
  }

  return {
    ok: true,
    requiresVoiceActivation: true,
    pendingDocId: userDoc.id,
    userId: publicUserId,
    name: String(profile.name || "").trim(),
  };
}

async function activatePatientWithVoice({
  publicUserId,
  pin,
  voicePassphrase,
  voiceprintVector,
  voiceFeatures,
}) {
  const trimmedPin = String(pin || "").trim();
  if (!/^\d{4}$/.test(trimmedPin)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Enter a 4-digit PIN.",
    );
  }

  let resolvedUserId = String(publicUserId || "").trim().toUpperCase();
  let userDoc = null;

  if (resolvedUserId) {
    userDoc = await findUserDocByPublicId(resolvedUserId);
  } else {
    userDoc = await findPendingUserDocByPin(trimmedPin);
    if (userDoc) {
      const pendingProfile = userDoc.data() || {};
      resolvedUserId = String(
        pendingProfile.userId || pendingProfile.userID || "",
      ).trim().toUpperCase();
    }
  }

  if (!userDoc || !resolvedUserId) {
    throw new functions.https.HttpsError("not-found", "Invalid PIN. Please try again.");
  }

  publicUserId = resolvedUserId;

  const profile = userDoc.data() || {};
  if (profile.onboardingPending !== true) {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "This account has already been set up.",
    );
  }
  if (resolveStoredPin(profile) !== trimmedPin) {
    throw new functions.https.HttpsError("not-found", "Invalid PIN. Please try again.");
  }

  const voiceProfile = buildVoiceProfile({
    voicePassphrase,
    voiceprintVector,
    voiceFeatures,
  });
  const passphrase = voiceProfile.passphrase;
  const pendingDocId = userDoc.id;

  let authUid = String(profile.authUid || pendingDocId || "").trim();
  let email = String(profile.email || "").trim().toLowerCase();
  if (!email && authUid) {
    email = voiceEmailFor(authUid);
  }

  if (authUid) {
    await admin.auth().updateUser(authUid, {
      email: email || voiceEmailFor(authUid),
      displayName: String(profile.name || "").trim() || undefined,
    });
    email = email || voiceEmailFor(authUid);
  } else {
    const created = await createVoicePatientAuthAccount({
      displayName: String(profile.name || "").trim(),
    });
    authUid = created.authUid;
    email = created.email;
  }

  const finalProfile = {
    userId: profile.userId || publicUserId,
    name: profile.name || "",
    email,
    birthDate: profile.birthDate || null,
    address: profile.address || "",
    gender: profile.gender || "",
    phone: profile.phone || "",
    emergencyContact: profile.emergencyContact || "",
    settings: profile.settings || profile.accessibilityPreferences || {
      fontScale: 1.0,
      notificationsEnabled: true,
      fallDetectionEnabled: true,
      voiceAssistantEnabled: true,
      languageCode: "en",
    },
    accessibilityPreferences: admin.firestore.FieldValue.delete(),
    status: "Active",
    authUid,
    voiceProfile,
    voicePassphrase: passphrase,
    onboardingPending: false,
    emailPending: false,
    onboardingCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    registeredByStaff: profile.registeredByStaff || "",
    createdAt: profile.createdAt || admin.firestore.FieldValue.serverTimestamp(),
    onboardingPin: admin.firestore.FieldValue.delete(),
    pin: admin.firestore.FieldValue.delete(),
    voiceAuthPassword: admin.firestore.FieldValue.delete(),
  };

  const batch = db.batch();
  batch.set(db.collection("users").doc(authUid), finalProfile, { merge: true });
  if (pendingDocId !== authUid) {
    batch.delete(db.collection("users").doc(pendingDocId));
  }
  await batch.commit();

  const token = await admin.auth().createCustomToken(authUid);
  return { ok: true, token, uid: authUid, email, userId: publicUserId };
}

/**
 * Completes onboarding after voice setup.
 * Supports pre-auth activation (userId + pin + voice) or signed-in legacy cleanup.
 */
async function completePatientOnboarding(data, context) {
  const publicUserId = String(data?.userId || data?.userID || "").trim().toUpperCase();
  const pin = String(data?.pin || "").trim();
  const hasVoicePayload =
    data?.voicePassphrase != null ||
    Array.isArray(data?.voiceprintVector) ||
    (data?.voiceFeatures && typeof data.voiceFeatures === "object");

  if (pin && hasVoicePayload) {
    return activatePatientWithVoice({
      publicUserId,
      pin,
      voicePassphrase: data?.voicePassphrase,
      voiceprintVector: data?.voiceprintVector,
      voiceFeatures: data?.voiceFeatures,
    });
  }

  if (!context.auth?.uid) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "Sign-in required to complete onboarding.",
    );
  }

  const uid = context.auth.uid;
  const userRef = db.collection("users").doc(uid);
  const snap = await userRef.get();
  if (!snap.exists) {
    throw new functions.https.HttpsError("not-found", "Patient profile not found.");
  }

  const profile = snap.data() || {};
  if (profile.onboardingPending !== true) {
    return { ok: true, alreadyComplete: true };
  }

  const email =
    String(profile.email || "").trim() || voiceEmailFor(uid);
  const updates = {
    onboardingPending: false,
    emailPending: false,
    onboardingPin: admin.firestore.FieldValue.delete(),
    pin: admin.firestore.FieldValue.delete(),
    voiceAuthPassword: admin.firestore.FieldValue.delete(),
    onboardingCompletedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (!String(profile.email || "").trim()) {
    updates.email = email;
    try {
      await admin.auth().updateUser(uid, { email });
    } catch (error) {
      console.warn("Could not update auth email during onboarding:", error?.message || error);
    }
  }

  await userRef.set(updates, { merge: true });
  return { ok: true, email };
}

module.exports = {
  invitePatient,
  verifyPatientOnboardingPin,
  completePatientOnboarding,
};
