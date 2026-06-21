const admin = require("firebase-admin");

const db = admin.firestore();

const CLINIC_OFFSET_MS = 8 * 60 * 60 * 1000;
const MEDICATIONS = "medications";
const REMINDERS = "medicationreminders";
const USERS = "users";

function pad2(value) {
  return String(value).padStart(2, "0");
}

function clinicNow() {
  const shifted = new Date(Date.now() + CLINIC_OFFSET_MS);
  return {
    date: `${shifted.getUTCFullYear()}-${pad2(shifted.getUTCMonth() + 1)}-${pad2(shifted.getUTCDate())}`,
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
    slot: `${pad2(shifted.getUTCHours())}:${pad2(shifted.getUTCMinutes())}`,
  };
}

function clinicPartsFromTimestamp(timestamp) {
  if (!timestamp || typeof timestamp.toDate !== "function") return null;
  const shifted = new Date(timestamp.toDate().getTime() + CLINIC_OFFSET_MS);
  return {
    date: `${shifted.getUTCFullYear()}-${pad2(shifted.getUTCMonth() + 1)}-${pad2(shifted.getUTCDate())}`,
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
    slot: `${pad2(shifted.getUTCHours())}:${pad2(shifted.getUTCMinutes())}`,
  };
}

function readPatientUserId(data) {
  return String(data.userId || data.userID || data.patientId || "").trim();
}

function notificationsEnabledForUser(data) {
  const settings = data.settings || data.accessibilityPreferences || {};
  if (typeof settings === "object" && settings.notificationsEnabled === false) {
    return false;
  }
  return true;
}

function isMedicationActive(medication, today) {
  if (!medication) return false;
  if (String(medication.status || "Active").trim() === "Cancelled") {
    return false;
  }
  const startDate = String(medication.startDate || "").trim();
  const endDate = String(medication.endDate || "").trim();
  if (!startDate || !endDate) return true;
  return startDate <= today && endDate >= today;
}

function reminderClockSlot(reminder) {
  const label = String(reminder.reminderTimeLabel || "").trim();
  const match = label.match(/(\d{2}):(\d{2}):(\d{2})$/);
  if (match) {
    return `${match[1]}:${match[2]}`;
  }

  const schedule = clinicPartsFromTimestamp(reminder.reminderTime);
  return schedule?.slot || "";
}

function isReminderDueToday(reminder, now) {
  const repeatPattern = String(reminder.repeatPattern || "Daily").trim().toLowerCase();
  const slot = reminderClockSlot(reminder);
  if (!slot || slot !== now.slot) return false;

  if (repeatPattern === "daily") {
    return true;
  }

  const schedule = clinicPartsFromTimestamp(reminder.reminderTime);
  return schedule?.date === now.date;
}

function alreadyTakenToday(reminder, today) {
  const status = String(reminder.status || "").trim();
  const completedDate = String(reminder.completedDate || "").trim();
  return status === "Completed" && completedDate === today;
}

function alreadyPushedThisSlot(reminder, today, slot) {
  const lastPushDate = String(reminder.lastPushDate || "").trim();
  const lastPushSlot = String(reminder.lastPushSlot || "").trim();
  return lastPushDate === today && lastPushSlot === slot;
}

async function buildPatientDeliveryMap() {
  const snap = await db.collection(USERS).get();
  const byPatientId = new Map();

  for (const docSnap of snap.docs) {
    const data = docSnap.data() || {};
    const token = String(data.fcmToken || "").trim();
    if (!token) continue;
    if (!notificationsEnabledForUser(data)) continue;

    const patientUserId = readPatientUserId(data);
    if (patientUserId) {
      byPatientId.set(patientUserId, {
        authUid: docSnap.id,
        token,
      });
    }
  }

  return byPatientId;
}

async function resolveDelivery(patientUserId, deliveryMap) {
  const direct = deliveryMap.get(patientUserId);
  if (direct?.token) return direct;

  for (const field of ["userId", "userID", "patientId"]) {
    const snap = await db
      .collection(USERS)
      .where(field, "==", patientUserId)
      .limit(5)
      .get();
    for (const docSnap of snap.docs) {
      const data = docSnap.data() || {};
      const token = String(data.fcmToken || "").trim();
      if (!token || !notificationsEnabledForUser(data)) continue;
      return { authUid: docSnap.id, token };
    }
  }

  return null;
}

async function buildMedicationMap() {
  const snap = await db.collection(MEDICATIONS).get();
  const map = new Map();
  for (const docSnap of snap.docs) {
    map.set(docSnap.id, docSnap.data() || {});
  }
  return map;
}

async function dispatchMedicationReminders() {
  const now = clinicNow();
  const [patientDelivery, medications, remindersSnap] = await Promise.all([
    buildPatientDeliveryMap(),
    buildMedicationMap(),
    db.collection(REMINDERS).get(),
  ]);

  let sent = 0;
  let skipped = 0;

  for (const reminderDoc of remindersSnap.docs) {
    const reminder = reminderDoc.data() || {};
    const reminderId = String(reminder.reminderId || reminderDoc.id).trim();
    const patientUserId = readPatientUserId(reminder);
    const medicationId = String(reminder.medicationId || "").trim();
    const status = String(reminder.status || "").trim();

    if (!patientUserId || !medicationId) {
      skipped += 1;
      continue;
    }
    if (status === "Missed") {
      skipped += 1;
      continue;
    }
    if (alreadyTakenToday(reminder, now.date)) {
      skipped += 1;
      continue;
    }
    if (alreadyPushedThisSlot(reminder, now.date, now.slot)) {
      skipped += 1;
      continue;
    }
    if (!isReminderDueToday(reminder, now)) {
      skipped += 1;
      continue;
    }

    const medication = medications.get(medicationId);
    if (!isMedicationActive(medication, now.date)) {
      skipped += 1;
      continue;
    }

    const delivery = await resolveDelivery(patientUserId, patientDelivery);
    if (!delivery?.token) {
      skipped += 1;
      continue;
    }

    const medicationName = String(medication?.name || "your medication").trim();
    const dosage = String(medication?.dosage || "").trim();
    const defaultBody = dosage
      ? `Take ${medicationName} — ${dosage}`
      : `Take ${medicationName}`;
    const body = String(reminder.reminderMessage || defaultBody).trim() || defaultBody;

    try {
      await admin.messaging().send({
        token: delivery.token,
        notification: {
          title: "Medication reminder",
          body,
        },
        data: {
          type: "medication_reminder",
          reminderId,
          medicationId,
          patientUserId,
        },
        android: {
          priority: "high",
          notification: {
            channelId: "medication_reminders",
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
            },
          },
        },
      });

      await reminderDoc.ref.set(
        {
          lastPushDate: now.date,
          lastPushSlot: now.slot,
          lastPushAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      sent += 1;
    } catch (error) {
      const code = error?.code || error?.errorInfo?.code || "";
      console.warn(`Medication push failed for ${reminderId}:`, code, error?.message || error);

      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
      ) {
        await db.collection(USERS).doc(delivery.authUid).set(
          {
            fcmToken: admin.firestore.FieldValue.delete(),
            fcmTokenUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      }
      skipped += 1;
    }
  }

  console.log(
    `Medication reminders ${now.date} ${now.slot}: sent=${sent} skipped=${skipped}`,
  );
  return { sent, skipped, slot: now.slot, date: now.date };
}

module.exports = {
  dispatchMedicationReminders,
  sendPushToToken: async (token, body, data = {}) => {
    await admin.messaging().send({
      token,
      notification: {
        title: "Medication reminder",
        body,
      },
      data: {
        type: "medication_reminder",
        ...data,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "medication_reminders",
          clickAction: "FLUTTER_NOTIFICATION_CLICK",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
          },
        },
      },
    });
  },
};
