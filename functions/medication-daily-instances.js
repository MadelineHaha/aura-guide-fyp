const admin = require("firebase-admin");

const db = admin.firestore();

const CLINIC_OFFSET_MS = 8 * 60 * 60 * 1000;
const MEDICATIONS = "medications";
const REMINDERS = "medicationreminders";
const REMINDER_COUNTER_PATH = ["system", "medicationReminderCounter"];

function pad2(value) {
  return String(value).padStart(2, "0");
}

function clinicNow() {
  const shifted = new Date(Date.now() + CLINIC_OFFSET_MS);
  return {
    date: `${shifted.getUTCFullYear()}-${pad2(shifted.getUTCMonth() + 1)}-${pad2(shifted.getUTCDate())}`,
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
  };
}

function clinicPartsFromTimestamp(timestamp) {
  if (!timestamp || typeof timestamp.toDate !== "function") return null;
  const shifted = new Date(timestamp.toDate().getTime() + CLINIC_OFFSET_MS);
  return {
    date: `${shifted.getUTCFullYear()}-${pad2(shifted.getUTCMonth() + 1)}-${pad2(shifted.getUTCDate())}`,
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
    dayOfWeek: shifted.getUTCDay(),
    slot: `${pad2(shifted.getUTCHours())}:${pad2(shifted.getUTCMinutes())}`,
  };
}

function dayOfWeekForDate(dateStr) {
  const [year, month, day] = String(dateStr || "").split("-").map(Number);
  if (!year || !month || !day) return null;
  const shifted = new Date(Date.UTC(year, month - 1, day, 0, 0, 0));
  return shifted.getUTCDay();
}

function combineDateAndTimeClinic(dateStr, timeStr) {
  const [year, month, day] = String(dateStr || "").split("-").map(Number);
  const [hour, minute] = String(timeStr || "08:00").split(":").map(Number);
  return new Date(Date.UTC(year, month - 1, day, hour - 8, minute, 0, 0));
}

function formatReminderLabel(date) {
  const shifted = new Date(date.getTime() + CLINIC_OFFSET_MS);
  const y = shifted.getUTCFullYear();
  const m = pad2(shifted.getUTCMonth() + 1);
  const d = pad2(shifted.getUTCDate());
  const hh = pad2(shifted.getUTCHours());
  const mm = pad2(shifted.getUTCMinutes());
  const ss = pad2(shifted.getUTCSeconds());
  return `${y}-${m}-${d} ${hh}:${mm}:${ss}`;
}

function readPatientUserId(data) {
  return String(data.userId || data.userID || data.patientId || "").trim();
}

function isMedicationActiveOnDate(medication, dateStr) {
  if (!medication) return false;
  if (String(medication.status || "Active").trim() === "Cancelled") return false;
  const startDate = String(medication.startDate || "").trim();
  const endDate = String(medication.endDate || "").trim();
  if (!startDate || !endDate) return true;
  return startDate <= dateStr && endDate >= dateStr;
}

function isSlotTemplate(reminder) {
  return !String(reminder.doseDate || "").trim();
}

function reminderClockSlot(reminder) {
  const label = String(reminder.reminderTimeLabel || "").trim();
  const match = label.match(/(\d{2}):(\d{2}):(\d{2})$/);
  if (match) {
    return `${match[1]}:${match[2]}`;
  }
  const schedule = clinicPartsFromTimestamp(reminder.reminderTime);
  return schedule?.slot || "08:00";
}

function isWeeklySlotDueOnDate(slotReminder, doseDate) {
  const repeat = String(slotReminder.repeatPattern || "Daily").trim().toLowerCase();
  if (repeat !== "weekly") return true;
  const schedule = clinicPartsFromTimestamp(slotReminder.reminderTime);
  if (!schedule) return false;
  const doseDay = dayOfWeekForDate(doseDate);
  return doseDay != null && schedule.dayOfWeek === doseDay;
}

function previousClinicDate(dateStr) {
  const [year, month, day] = String(dateStr || "").split("-").map(Number);
  const utc = Date.UTC(year, month - 1, day, 0, 0, 0);
  const prev = new Date(utc - 24 * 60 * 60 * 1000);
  const shifted = new Date(prev.getTime() + CLINIC_OFFSET_MS);
  return `${shifted.getUTCFullYear()}-${pad2(shifted.getUTCMonth() + 1)}-${pad2(shifted.getUTCDate())}`;
}

async function finalizeMissedDosesForDate(doseDate) {
  const snap = await db
    .collection(REMINDERS)
    .where("doseDate", "==", doseDate)
    .get();

  let updated = 0;
  const batch = db.batch();
  for (const docSnap of snap.docs) {
    const data = docSnap.data() || {};
    const status = String(data.status || "").trim();
    if (status !== "Pending") continue;
    batch.update(docSnap.ref, {
      status: "Missed",
      missedDate: doseDate,
      completedDate: "",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    updated += 1;
  }
  if (updated > 0) {
    await batch.commit();
  }
  return updated;
}

async function reserveReminderIds(count) {
  const counterRef = db.doc(REMINDER_COUNTER_PATH.join("/"));
  return db.runTransaction(async (transaction) => {
    const snap = await transaction.get(counterRef);
    let next = snap.exists ? Number(snap.data().next) || 1 : 1;
    const ids = [];
    for (let i = 0; i < count; i += 1) {
      ids.push(`R${String(next).padStart(5, "0")}`);
      next += 1;
    }
    transaction.set(counterRef, { next }, { merge: true });
    return ids;
  });
}

/**
 * Creates one medicationreminders row per slot for `doseDate` while medication is active.
 * @param {object} options
 * @param {string} [options.doseDate] clinic YYYY-MM-DD (defaults to today)
 * @param {string} [options.patientUserId] limit to one patient
 */
async function createDailyReminderInstances({ doseDate, patientUserId } = {}) {
  const today = doseDate || clinicNow().date;
  const patientFilter = String(patientUserId || "").trim();

  const [medicationsSnap, remindersSnap] = await Promise.all([
    db.collection(MEDICATIONS).get(),
    db.collection(REMINDERS).get(),
  ]);

  const medications = new Map();
  for (const docSnap of medicationsSnap.docs) {
    medications.set(docSnap.id, { id: docSnap.id, ...(docSnap.data() || {}) });
  }

  const slotsByMedication = new Map();
  const existingDaily = new Set();

  for (const docSnap of remindersSnap.docs) {
    const data = docSnap.data() || {};
    const medicationId = String(data.medicationId || "").trim();
    if (!medicationId) continue;

    const dose = String(data.doseDate || "").trim();
    if (dose) {
      const slotId = String(data.slotReminderId || "").trim();
      const key = `${medicationId}|${dose}|${slotId}`;
      existingDaily.add(key);
      continue;
    }

    if (!slotsByMedication.has(medicationId)) {
      slotsByMedication.set(medicationId, []);
    }
    slotsByMedication.get(medicationId).push({
      id: docSnap.id,
      ...data,
    });
  }

  const toCreate = [];
  for (const [medicationId, medication] of medications.entries()) {
    if (!isMedicationActiveOnDate(medication, today)) continue;

    const userId = readPatientUserId(medication);
    if (!userId) continue;
    if (patientFilter && userId !== patientFilter) continue;

    const slots = slotsByMedication.get(medicationId) || [];
    for (const slot of slots) {
      if (!isWeeklySlotDueOnDate(slot, today)) continue;

      const slotReminderId = String(slot.reminderId || slot.id || "").trim();
      const dedupeKey = `${medicationId}|${today}|${slotReminderId}`;
      if (existingDaily.has(dedupeKey)) continue;

      const clock = reminderClockSlot(slot);
      const reminderDateTime = combineDateAndTimeClinic(today, clock);
      const message =
        String(slot.reminderMessage || "").trim() ||
        `Take ${String(medication.name || "medication").trim()}`;

      toCreate.push({
        dedupeKey,
        payload: {
          reminderTime: admin.firestore.Timestamp.fromDate(reminderDateTime),
          reminderTimeLabel: formatReminderLabel(reminderDateTime),
          reminderType: String(slot.reminderType || "Notification").trim() || "Notification",
          reminderMessage: message,
          repeatPattern: String(slot.repeatPattern || "Daily").trim() || "Daily",
          status: "Pending",
          medicationId,
          userId,
          staffId: String(slot.staffId || slot.staffID || medication.staffId || medication.staffID || "").trim(),
          doseDate: today,
          slotReminderId,
          completedDate: "",
          missedDate: "",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
      });
    }
  }

  if (toCreate.length === 0) {
    return { created: 0, doseDate: today };
  }

  const ids = await reserveReminderIds(toCreate.length);
  const batch = db.batch();
  for (let i = 0; i < toCreate.length; i += 1) {
    const reminderId = ids[i];
    const entry = toCreate[i];
    batch.set(db.collection(REMINDERS).doc(reminderId), {
      ...entry.payload,
      reminderId,
    });
  }
  await batch.commit();

  return { created: toCreate.length, doseDate: today };
}

async function runDailyMedicationReminderJob() {
  const today = clinicNow().date;
  const yesterday = previousClinicDate(today);
  const missed = await finalizeMissedDosesForDate(yesterday);
  const created = await createDailyReminderInstances({ doseDate: today });
  console.log(
    `Daily medication reminders ${today}: missed=${missed} created=${created.created}`,
  );
  return { today, yesterday, missed, created: created.created };
}

function reminderCountForFrequency(frequency) {
  switch (String(frequency || "").trim()) {
    case "Twice daily":
      return 2;
    case "Three times daily":
      return 3;
    case "Once daily":
    case "Weekly":
    default:
      return 1;
  }
}

function repeatPatternForFrequency(frequency) {
  return String(frequency || "").trim() === "Weekly" ? "Weekly" : "Daily";
}

function defaultReminderTimesForFrequency(frequency) {
  switch (String(frequency || "").trim()) {
    case "Twice daily":
      return ["08:00", "20:00"];
    case "Three times daily":
      return ["08:00", "14:00", "20:00"];
    case "Once daily":
    case "Weekly":
    default:
      return ["08:00"];
  }
}

function pickMissingReminderTimes(existingTimes, frequency, countNeeded) {
  const defaults = defaultReminderTimesForFrequency(frequency);
  const missing = [];
  for (const time of defaults) {
    if (missing.length >= countNeeded) break;
    if (!existingTimes.includes(time)) missing.push(time);
  }
  let index = 0;
  while (missing.length < countNeeded && defaults.length > 0) {
    const time = defaults[index % defaults.length];
    if (!existingTimes.includes(time) && !missing.includes(time)) {
      missing.push(time);
    }
    index += 1;
    if (index > defaults.length * 4) break;
  }
  return missing;
}

function reminderTimeInputFromTimestamp(timestamp) {
  const schedule = clinicPartsFromTimestamp(timestamp);
  return schedule?.slot || "08:00";
}

function staffIdFromReminders(docs) {
  for (const docSnap of docs) {
    const data = docSnap.data?.() || docSnap;
    const id = String(data.staffId || data.staffID || "").trim();
    if (id) return id;
  }
  return "";
}

/**
 * Creates missing slot-template medicationreminders rows for a patient.
 */
async function ensureMedicationSlotReminders(patientUserId) {
  const trimmedUserId = String(patientUserId || "").trim();
  if (!/^U\d{5}$/.test(trimmedUserId)) {
    return { created: 0 };
  }

  const [medicationsSnap, remindersSnap] = await Promise.all([
    db.collection(MEDICATIONS).where("userId", "==", trimmedUserId).get(),
    db.collection(REMINDERS).where("userId", "==", trimmedUserId).get(),
  ]);

  if (medicationsSnap.empty) {
    return { created: 0 };
  }

  const remindersByMed = new Map();
  for (const docSnap of remindersSnap.docs) {
    const medId = String(docSnap.data().medicationId || "").trim();
    if (!medId) continue;
    if (!remindersByMed.has(medId)) remindersByMed.set(medId, []);
    remindersByMed.get(medId).push(docSnap);
  }

  const toCreate = [];
  for (const medDoc of medicationsSnap.docs) {
    const med = medDoc.data() || {};
    const medicationId = String(med.medicationId || medDoc.id).trim();
    if (!medicationId) continue;
    if (String(med.status || "Active").trim() === "Cancelled") continue;

    const frequency = String(med.frequency || "").trim();
    const expectedCount = reminderCountForFrequency(frequency);
    const allDocs = remindersByMed.get(medicationId) || [];
    const slotDocs = allDocs.filter((docSnap) => isSlotTemplate(docSnap.data()));
    if (slotDocs.length >= expectedCount) continue;

    const existingTimes = slotDocs
      .map((docSnap) => reminderTimeInputFromTimestamp(docSnap.data().reminderTime))
      .sort();
    const timesToAdd = pickMissingReminderTimes(
      existingTimes,
      frequency,
      expectedCount - existingTimes.length,
    );
    if (timesToAdd.length === 0) continue;

    const startDate = String(med.startDate || "").trim() || clinicNow().date;
    const repeatPattern = repeatPatternForFrequency(frequency);
    const name = String(med.name || "").trim();
    const dosage = String(med.dosage || "").trim();
    const message =
      name && dosage
        ? `Take ${name} — ${dosage}`
        : `Medication reminder for ${name || medicationId}`;
    const staffId =
      String(med.staffId || med.staffID || "").trim() ||
      staffIdFromReminders(allDocs);
    if (!/^S\d{5}$/.test(staffId)) continue;

    for (const reminderTime of timesToAdd) {
      const reminderDateTime = combineDateAndTimeClinic(startDate, reminderTime);
      toCreate.push({
        reminderTime: admin.firestore.Timestamp.fromDate(reminderDateTime),
        reminderTimeLabel: formatReminderLabel(reminderDateTime),
        reminderType: "Notification",
        reminderMessage: message,
        repeatPattern,
        status: "Pending",
        medicationId,
        userId: trimmedUserId,
        staffId,
        doseDate: "",
        completedDate: "",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
  }

  if (toCreate.length === 0) {
    return { created: 0 };
  }

  const ids = await reserveReminderIds(toCreate.length);
  const batch = db.batch();
  for (let i = 0; i < toCreate.length; i += 1) {
    batch.set(db.collection(REMINDERS).doc(ids[i]), {
      ...toCreate[i],
      reminderId: ids[i],
    });
  }
  await batch.commit();

  return { created: toCreate.length };
}

module.exports = {
  clinicNow,
  createDailyReminderInstances,
  ensureMedicationSlotReminders,
  finalizeMissedDosesForDate,
  runDailyMedicationReminderJob,
  isSlotTemplate,
  isMedicationActiveOnDate,
};
