const admin = require("firebase-admin");

const db = admin.firestore();

const CLINIC_OFFSET_MS = 8 * 60 * 60 * 1000;
const FOLLOW_UP_DELAY_MS = 5 * 60 * 1000;
const MEDICATIONS = "medications";
const REMINDERS = "medicationreminders";
const USERS = "users";
const PATIENT_NOTIFICATIONS = "patientnotifications";

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

function isWeeklyReminderDueOnDate(reminder, doseDate) {
  const repeatPattern = String(reminder.repeatPattern || "Daily").trim().toLowerCase();
  if (repeatPattern === "daily") {
    return true;
  }

  const schedule = clinicPartsFromTimestamp(reminder.reminderTime);
  return schedule?.date === doseDate;
}

function alreadyTakenToday(reminder, today) {
  const status = String(reminder.status || "").trim();
  const completedDate = String(reminder.completedDate || "").trim();
  return status === "Completed" && completedDate === today;
}

function pushedThisDoseSlot(reminder, today, doseSlot) {
  const lastPushDate = String(reminder.lastPushDate || "").trim();
  const lastPushSlot = String(reminder.lastPushSlot || "").trim();
  return lastPushDate === today && lastPushSlot === doseSlot;
}

function lastPushAtMs(reminder) {
  const lastPushAt = reminder.lastPushAt;
  if (!lastPushAt || typeof lastPushAt.toDate !== "function") return null;
  return lastPushAt.toDate().getTime();
}

function missedFollowUpAlreadySent(reminder, today, doseSlot) {
  return (
    String(reminder.missedFollowUpDate || "").trim() === today &&
    String(reminder.missedFollowUpSlot || "").trim() === doseSlot
  );
}

function buildPatientNotificationId(reminderId, doseDate, slot) {
  const safeSlot = String(slot || "").replace(":", "");
  const safeDate = String(doseDate || "").replace(/-/g, "");
  return `NR_${reminderId}_${safeDate}_${safeSlot}`;
}

function buildMissedNotificationId(reminderId, doseDate, slot) {
  return `${buildPatientNotificationId(reminderId, doseDate, slot)}_missed`;
}

async function ensurePatientNotification({
  reminderId,
  patientUserId,
  medicationId,
  doseDate,
  slot,
  title,
  body,
  status = "Delivered",
}) {
  const notificationId =
    status === "Missed"
      ? buildMissedNotificationId(reminderId, doseDate, slot)
      : buildPatientNotificationId(reminderId, doseDate, slot);
  const ref = db.collection(PATIENT_NOTIFICATIONS).doc(notificationId);
  const existing = await ref.get();
  if (existing.exists) {
    return { notificationId, created: false, ref };
  }

  await ref.set({
    notificationId,
    userId: patientUserId,
    reminderId,
    medicationId,
    type: "medication_reminder",
    title: String(title || "Medication reminder").trim() || "Medication reminder",
    body: String(body || "").trim(),
    doseDate,
    slot,
    status,
    readAt: null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return { notificationId, created: true, ref };
}

async function buildDeliveryMaps() {
  const snap = await db.collection(USERS).get();
  const byPatientId = new Map();
  const tokensByAuthUid = new Map();

  for (const docSnap of snap.docs) {
    const data = docSnap.data() || {};
    const token = String(data.fcmToken || "").trim();
    if (!token) continue;
    if (!notificationsEnabledForUser(data)) continue;

    tokensByAuthUid.set(docSnap.id, token);

    const patientUserId = readPatientUserId(data);
    if (patientUserId) {
      byPatientId.set(patientUserId, {
        authUid: docSnap.id,
        token,
        assignedCaregiverId: String(data.assignedCaregiverId || "").trim(),
        patientName: String(data.name || "").trim(),
      });
    }
  }

  return { byPatientId, tokensByAuthUid };
}

async function resolveDelivery(patientUserId, { byPatientId, tokensByAuthUid }) {
  const direct = byPatientId.get(patientUserId);
  if (direct?.token) {
    let caregiverToken = null;
    if (direct.assignedCaregiverId) {
      caregiverToken = tokensByAuthUid.get(direct.assignedCaregiverId);
    }
    return { ...direct, caregiverToken };
  }

  // Fallback lookup
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
      
      const assignedCaregiverId = String(data.assignedCaregiverId || "").trim();
      let caregiverToken = null;
      if (assignedCaregiverId) {
        // Query the caregiver document directly for fallback
        const cgSnap = await db.collection(USERS).doc(assignedCaregiverId).get();
        if (cgSnap.exists) {
          const cgData = cgSnap.data() || {};
          if (notificationsEnabledForUser(cgData)) {
            caregiverToken = String(cgData.fcmToken || "").trim();
          }
        }
      }
      return { 
        authUid: docSnap.id, 
        token, 
        assignedCaregiverId, 
        patientName: String(data.name || "").trim(),
        caregiverToken
      };
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

async function sendMedicationPush({
  delivery,
  title,
  body,
  data,
}) {
  if (!delivery?.token) return false;

  await admin.messaging().send({
    token: delivery.token,
    notification: {
      title,
      body,
    },
    data,
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
  return true;
}

async function dispatchMedicationReminders() {
  const now = clinicNow();
  const [deliveryMaps, medications, remindersSnap] = await Promise.all([
    buildDeliveryMaps(),
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
    const doseDate = String(reminder.doseDate || "").trim();

    if (!patientUserId || !medicationId) {
      skipped += 1;
      continue;
    }
    // Push targets today's dose rows; slot templates are not notified directly.
    if (!doseDate) {
      skipped += 1;
      continue;
    }
    if (doseDate !== now.date) {
      skipped += 1;
      continue;
    }
    if (alreadyTakenToday(reminder, now.date)) {
      skipped += 1;
      continue;
    }

    const doseSlot = reminderClockSlot(reminder);
    if (!doseSlot) {
      skipped += 1;
      continue;
    }

    const medication = medications.get(medicationId);
    if (!isMedicationActive(medication, now.date)) {
      skipped += 1;
      continue;
    }

    const delivery = await resolveDelivery(patientUserId, deliveryMaps);
    const medicationName = String(medication?.name || "your medication").trim();
    const dosage = String(medication?.dosage || "").trim();
    const defaultBody = dosage
      ? `Take ${medicationName} — ${dosage}`
      : `Take ${medicationName}`;
    const body = String(reminder.reminderMessage || defaultBody).trim() || defaultBody;

    const pushed = pushedThisDoseSlot(reminder, now.date, doseSlot);
    const lastPushMs = lastPushAtMs(reminder);
    const needsFollowUp =
      pushed &&
      !missedFollowUpAlreadySent(reminder, now.date, doseSlot) &&
      lastPushMs != null &&
      Date.now() - lastPushMs >= FOLLOW_UP_DELAY_MS;

    if (needsFollowUp) {
      const missedTitle = "Missed medication";
      const missedBody = `${medicationName} was not marked as taken. Please take it now.`;
      const notificationId = buildMissedNotificationId(reminderId, now.date, doseSlot);

      try {
        await ensurePatientNotification({
          reminderId,
          patientUserId,
          medicationId,
          doseDate: now.date,
          slot: doseSlot,
          title: missedTitle,
          body: missedBody,
          status: "Missed",
        });

        await sendMedicationPush({
          delivery,
          title: missedTitle,
          body: missedBody,
          data: {
            type: "medication_reminder",
            notificationKind: "missed",
            reminderId,
            medicationId,
            patientUserId,
            notificationId,
          },
        });
        
        // Also notify connected caregiver
        if (delivery?.caregiverToken) {
          const patientName = delivery.patientName || "Your patient";
          const caregiverBody = `${patientName} missed their medication: ${medicationName}.`;
          
          await admin.messaging().send({
            token: delivery.caregiverToken,
            notification: {
              title: "Missed Medication Alert",
              body: caregiverBody,
            },
            data: {
              type: "caregiver_medication_alert",
              reminderId,
              medicationId,
              patientUserId,
            },
            android: {
              priority: "high",
            },
          }).catch(e => console.warn(`Caregiver push failed for ${reminderId}:`, e));
        }

        await reminderDoc.ref.set(
          {
            status: "Missed",
            missedDate: now.date,
            missedFollowUpDate: now.date,
            missedFollowUpSlot: doseSlot,
            missedFollowUpAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        sent += 1;
      } catch (error) {
        const code = error?.code || error?.errorInfo?.code || "";
        console.warn(
          `Missed medication push failed for ${reminderId}:`,
          code,
          error?.message || error,
        );

        if (
          delivery?.authUid &&
          (code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token")
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
      continue;
    }

    if (status === "Missed") {
      skipped += 1;
      continue;
    }

    const dueNow = doseSlot === now.slot;
    if (!dueNow) {
      skipped += 1;
      continue;
    }
    if (!isWeeklyReminderDueOnDate(reminder, now.date)) {
      skipped += 1;
      continue;
    }
    if (pushed) {
      skipped += 1;
      continue;
    }

    const title = "Medication reminder";
    const notificationId = buildPatientNotificationId(reminderId, now.date, doseSlot);

    try {
      await ensurePatientNotification({
        reminderId,
        patientUserId,
        medicationId,
        doseDate: now.date,
        slot: doseSlot,
        title,
        body,
        status: "Delivered",
      });

      if (!delivery?.token) {
        skipped += 1;
        continue;
      }

      await sendMedicationPush({
        delivery,
        title,
        body,
        data: {
          type: "medication_reminder",
          notificationKind: "reminder",
          reminderId,
          medicationId,
          patientUserId,
          notificationId,
        },
      });

      await reminderDoc.ref.set(
        {
          lastPushDate: now.date,
          lastPushSlot: doseSlot,
          lastPushAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      sent += 1;
    } catch (error) {
      const code = error?.code || error?.errorInfo?.code || "";
      console.warn(`Medication push failed for ${reminderId}:`, code, error?.message || error);

      if (
        delivery?.authUid &&
        (code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-registration-token")
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

async function recordMedicationPatientNotification({
  patientUserId,
  reminderId,
  kind = "reminder",
}) {
  const trimmedPatientId = String(patientUserId || "").trim();
  const trimmedReminderId = String(reminderId || "").trim();
  const notificationKind = String(kind || "reminder").trim().toLowerCase();

  if (!trimmedPatientId || !trimmedReminderId) {
    throw new Error("patientUserId and reminderId are required.");
  }

  const reminderDoc = await db.collection(REMINDERS).doc(trimmedReminderId).get();
  if (!reminderDoc.exists) {
    throw new Error("Reminder not found.");
  }

  const reminder = reminderDoc.data() || {};
  const reminderPatientId = readPatientUserId(reminder);
  if (reminderPatientId !== trimmedPatientId) {
    throw new Error("Reminder does not belong to this patient.");
  }

  const medicationId = String(reminder.medicationId || "").trim();
  if (!medicationId) {
    throw new Error("Medication is missing on reminder.");
  }

  const medicationSnap = await db.collection(MEDICATIONS).doc(medicationId).get();
  const medication = medicationSnap.data() || {};
  const now = clinicNow();
  const doseDate = String(reminder.doseDate || "").trim() || now.date;
  const doseSlot = reminderClockSlot(reminder);
  if (!doseSlot) {
    throw new Error("Reminder time is missing.");
  }

  const medicationName = String(medication.name || "your medication").trim();
  const dosage = String(medication.dosage || "").trim();
  const defaultBody = dosage
    ? `Take ${medicationName} — ${dosage}`
    : `Take ${medicationName}`;
  const body = String(reminder.reminderMessage || defaultBody).trim() || defaultBody;

  const isMissed = notificationKind === "missed";
  const title = isMissed ? "Missed medication" : "Medication reminder";
  const notificationBody = isMissed
    ? `${medicationName} was not marked as taken. Please take it now.`
    : body;

  const notification = await ensurePatientNotification({
    reminderId: trimmedReminderId,
    patientUserId: trimmedPatientId,
    medicationId,
    doseDate,
    slot: doseSlot,
    title,
    body: notificationBody,
    status: isMissed ? "Missed" : "Delivered",
  });

  const mergeFields = isMissed
    ? {
        status: "Missed",
        missedDate: doseDate,
        missedFollowUpDate: doseDate,
        missedFollowUpSlot: doseSlot,
        missedFollowUpAt: admin.firestore.FieldValue.serverTimestamp(),
      }
    : {
        lastPushDate: doseDate,
        lastPushSlot: doseSlot,
        lastPushAt: admin.firestore.FieldValue.serverTimestamp(),
      };

  await reminderDoc.ref.set(mergeFields, { merge: true });

  return {
    notificationId: notification.notificationId,
    created: notification.created,
    doseDate,
    slot: doseSlot,
    status: isMissed ? "Missed" : "Delivered",
  };
}

module.exports = {
  dispatchMedicationReminders,
  recordMedicationPatientNotification,
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
