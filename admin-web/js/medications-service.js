import {
  collection,
  doc,
  getDoc,
  getDocs,
  onSnapshot,
  query,
  runTransaction,
  serverTimestamp,
  Timestamp,
  where,
  writeBatch,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import {
  combineDateAndTime,
  timeToInputValue,
  todayDateString,
} from "./appointments-service.js";
import { formatTypedSentence } from "./text-format.js";
import { formatStaffDisplayName } from "./staff-name-format.js";
import { HEALTHCARE_STAFF_COLLECTION } from "./staff-auth.js";

export const MEDICATIONS_COLLECTION = "medications";
export const MEDICATION_REMINDERS_COLLECTION = "medicationreminders";
export const MEDICATION_COUNTER_PATH = ["system", "medicationCounter"];
export const REMINDER_COUNTER_PATH = ["system", "medicationReminderCounter"];
export const MEDICATION_STATUS_ACTIVE = "Active";
export const MEDICATION_STATUS_CANCELLED = "Cancelled";

const USER_ID_PATTERN = /^U\d{5}$/;
const STAFF_ID_PATTERN = /^S\d{5}$/;

export function reminderCountForFrequency(frequency) {
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

export function repeatPatternForFrequency(frequency) {
  return String(frequency || "").trim() === "Weekly" ? "Weekly" : "Daily";
}

function formatReminderLabel(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  const hh = String(date.getHours()).padStart(2, "0");
  const mm = String(date.getMinutes()).padStart(2, "0");
  const ss = String(date.getSeconds()).padStart(2, "0");
  return `${y}-${m}-${d} ${hh}:${mm}:${ss}`;
}

export function validateMedicationInput({
  name,
  dosage,
  frequency,
  instructions,
  startDate,
  endDate,
  reminderDate,
  reminderTimes,
  userId,
  staffId,
}) {
  const trimmedName = String(name || "").trim();
  const trimmedDosage = String(dosage || "").trim();
  const trimmedFrequency = String(frequency || "").trim();
  const trimmedInstructions = formatTypedSentence(instructions);
  const times = Array.isArray(reminderTimes)
    ? reminderTimes.map((time) => String(time || "").trim()).filter(Boolean)
    : [];

  if (!trimmedName) return "Medication name is required.";
  if (!trimmedDosage) return "Dosage is required.";
  if (!trimmedFrequency) return "Frequency is required.";
  if (!trimmedInstructions) return "Instructions are required.";
  if (!startDate) return "Start date is required.";
  if (!endDate) return "End date is required.";
  const today = todayDateString();
  if (startDate < today) return "Start date cannot be in the past.";
  const minEndDate = startDate > today ? startDate : today;
  if (endDate < minEndDate) {
    return endDate < today
      ? "End date cannot be in the past."
      : "End date must be on or after the start date.";
  }
  if (!reminderDate) return "Reminder date is required.";
  const expectedCount = reminderCountForFrequency(trimmedFrequency);
  if (times.length !== expectedCount) {
    return `Please provide ${expectedCount} reminder time(s) for ${trimmedFrequency}.`;
  }
  if (new Set(times).size !== times.length) {
    return "Reminder times must be different from each other.";
  }
  if (!userId || !USER_ID_PATTERN.test(userId)) {
    return "Patient User ID is missing or invalid.";
  }
  if (!staffId || !STAFF_ID_PATTERN.test(staffId)) {
    return "Staff ID is missing or invalid.";
  }
  return null;
}

export function validateMedicationUpdateInput({
  name,
  dosage,
  frequency,
  instructions,
  startDate,
  endDate,
  reminderDate,
  reminderTimes,
  userId,
  staffId,
}) {
  const trimmedName = String(name || "").trim();
  const trimmedDosage = String(dosage || "").trim();
  const trimmedFrequency = String(frequency || "").trim();
  const trimmedInstructions = formatTypedSentence(instructions);
  const times = Array.isArray(reminderTimes)
    ? reminderTimes.map((time) => String(time || "").trim()).filter(Boolean)
    : [];

  if (!trimmedName) return "Medication name is required.";
  if (!trimmedDosage) return "Dosage is required.";
  if (!trimmedFrequency) return "Frequency is required.";
  if (!trimmedInstructions) return "Instructions are required.";
  if (!startDate) return "Start date is required.";
  if (!endDate) return "End date is required.";
  if (endDate < startDate) {
    return "End date must be on or after the start date.";
  }
  if (!reminderDate) return "Reminder date is required.";
  const expectedCount = reminderCountForFrequency(trimmedFrequency);
  if (times.length !== expectedCount) {
    return `Please provide ${expectedCount} reminder time(s) for ${trimmedFrequency}.`;
  }
  if (new Set(times).size !== times.length) {
    return "Reminder times must be different from each other.";
  }
  if (!userId || !USER_ID_PATTERN.test(userId)) {
    return "Patient User ID is missing or invalid.";
  }
  if (!staffId || !STAFF_ID_PATTERN.test(staffId)) {
    return "Staff ID is missing or invalid.";
  }
  return null;
}

function reminderTimeInputFromTimestamp(value) {
  if (!value || typeof value.toDate !== "function") return "08:00";
  return timeToInputValue(value.toDate());
}

function sortReminderDocsByTime(docs) {
  return [...docs].sort((a, b) => {
    const ta = reminderTimeInputFromTimestamp(a.data().reminderTime);
    const tb = reminderTimeInputFromTimestamp(b.data().reminderTime);
    return ta.localeCompare(tb);
  });
}

/**
 * Loads one medication and its reminder times for editing.
 */
export async function fetchMedicationWithReminders(medicationId) {
  const trimmedId = String(medicationId || "").trim();
  if (!trimmedId) return null;

  const medicationRef = doc(db, MEDICATIONS_COLLECTION, trimmedId);
  const medicationSnap = await getDoc(medicationRef);
  if (!medicationSnap.exists()) return null;

  const data = medicationSnap.data();
  const remindersQuery = query(
    collection(db, MEDICATION_REMINDERS_COLLECTION),
    where("medicationId", "==", trimmedId),
  );
  const remindersSnap = await getDocs(remindersQuery);
  const reminderTimes = sortReminderDocsByTime(remindersSnap.docs).map((docSnap) =>
    reminderTimeInputFromTimestamp(docSnap.data().reminderTime),
  );

  return {
    medicationId: (data.medicationId || trimmedId).trim(),
    name: (data.name || "").trim(),
    dosage: (data.dosage || "").trim(),
    frequency: (data.frequency || "").trim(),
    instructions: (data.instructions || "").trim(),
    startDate: (data.startDate || "").trim(),
    endDate: (data.endDate || "").trim(),
    userId: (data.userId || data.userID || "").trim(),
    staffId: (data.staffId || data.staffID || "").trim(),
    status: String(data.status || MEDICATION_STATUS_ACTIVE).trim(),
    reminderTimes,
  };
}

export function defaultReminderTimesForFrequency(frequency) {
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

/**
 * Creates missing MedicationReminder rows for medications that have none
 * (or fewer than frequency requires).
 */
export async function ensureRemindersForMedications(userId) {
  const trimmedUserId = String(userId || "").trim();
  if (!USER_ID_PATTERN.test(trimmedUserId)) return { created: 0 };

  const [medsSnap, remindersSnap] = await Promise.all([
    getDocs(
      query(
        collection(db, MEDICATIONS_COLLECTION),
        where("userId", "==", trimmedUserId),
      ),
    ),
    getDocs(
      query(
        collection(db, MEDICATION_REMINDERS_COLLECTION),
        where("userId", "==", trimmedUserId),
      ),
    ),
  ]);

  if (medsSnap.empty) return { created: 0 };

  const remindersByMed = new Map();
  for (const docSnap of remindersSnap.docs) {
    const medId = String(docSnap.data().medicationId || "").trim();
    if (!medId) continue;
    if (!remindersByMed.has(medId)) remindersByMed.set(medId, []);
    remindersByMed.get(medId).push(docSnap);
  }

  const reminderCounterRef = doc(db, ...REMINDER_COUNTER_PATH);
  const remindersRef = collection(db, MEDICATION_REMINDERS_COLLECTION);
  let totalCreated = 0;

  await runTransaction(db, async (transaction) => {
    const remCounterSnap = await transaction.get(reminderCounterRef);
    let remNext = remCounterSnap.exists()
      ? Number(remCounterSnap.data().next) || 1
      : 1;

    for (const medDoc of medsSnap.docs) {
      const med = medDoc.data();
      const medicationId = String(med.medicationId || medDoc.id).trim();
      if (!medicationId) continue;
      if (
        String(med.status || MEDICATION_STATUS_ACTIVE).trim() ===
        MEDICATION_STATUS_CANCELLED
      ) {
        continue;
      }

      const frequency = String(med.frequency || "").trim();
      const expectedCount = reminderCountForFrequency(frequency);
      const existingDocs = remindersByMed.get(medicationId) || [];
      if (existingDocs.length >= expectedCount) continue;

      const existingTimes = sortReminderDocsByTime(existingDocs).map((docSnap) =>
        reminderTimeInputFromTimestamp(docSnap.data().reminderTime),
      );
      const timesToAdd = pickMissingReminderTimes(
        existingTimes,
        frequency,
        expectedCount - existingTimes.length,
      );
      if (timesToAdd.length === 0) continue;

      const startDate = String(med.startDate || "").trim() || todayDateString();
      const repeatPattern = repeatPatternForFrequency(frequency);
      const name = String(med.name || "").trim();
      const dosage = String(med.dosage || "").trim();
      const message =
        name && dosage
          ? `Take ${name} — ${dosage}`
          : `Medication reminder for ${name || medicationId}`;
      const staffId = String(med.staffId || med.staffID || "").trim();
      if (!staffId || !STAFF_ID_PATTERN.test(staffId)) continue;

      for (const reminderTime of timesToAdd) {
        const reminderId = `R${String(remNext).padStart(5, "0")}`;
        remNext += 1;
        totalCreated += 1;

        const reminderDateTime = combineDateAndTime(startDate, reminderTime);
        const reminderTs = Timestamp.fromDate(reminderDateTime);
        const reminderLabel = formatReminderLabel(reminderDateTime);

        transaction.set(doc(remindersRef, reminderId), {
          reminderId,
          reminderTime: reminderTs,
          reminderTimeLabel: reminderLabel,
          reminderType: "Notification",
          reminderMessage: message,
          repeatPattern,
          status: "Pending",
          medicationId,
          userId: trimmedUserId,
          staffId,
          completedDate: "",
          createdAt: serverTimestamp(),
        });
      }
    }

    if (totalCreated > 0) {
      transaction.set(reminderCounterRef, { next: remNext }, { merge: true });
    }
  });

  return { created: totalCreated };
}

/**
 * @returns {Promise<{ medicationId: string, reminderId: string }>}
 */
export async function createMedicationWithReminder({
  userId,
  staffId,
  name,
  dosage,
  frequency,
  instructions,
  startDate,
  endDate,
  reminderDate,
  reminderTimes,
}) {
  const validationError = validateMedicationInput({
    name,
    dosage,
    frequency,
    instructions,
    startDate,
    endDate,
    reminderDate,
    reminderTimes,
    userId,
    staffId,
  });
  if (validationError) {
    throw new Error(validationError);
  }

  const trimmedName = name.trim();
  const trimmedDosage = dosage.trim();
  const trimmedFrequency = frequency.trim();
  const trimmedInstructions = formatTypedSentence(instructions);
  const times = reminderTimes.map((time) => String(time).trim());
  const repeatPattern = repeatPatternForFrequency(trimmedFrequency);
  const message = `Take ${trimmedName} — ${trimmedDosage}`;

  const medicationCounterRef = doc(db, ...MEDICATION_COUNTER_PATH);
  const reminderCounterRef = doc(db, ...REMINDER_COUNTER_PATH);
  const medicationsRef = collection(db, MEDICATIONS_COLLECTION);
  const remindersRef = collection(db, MEDICATION_REMINDERS_COLLECTION);

  return runTransaction(db, async (transaction) => {
    const medCounterSnap = await transaction.get(medicationCounterRef);
    const medNext = medCounterSnap.exists()
      ? Number(medCounterSnap.data().next) || 1
      : 1;
    const medicationId = `M${String(medNext).padStart(5, "0")}`;

    const remCounterSnap = await transaction.get(reminderCounterRef);
    let remNext = remCounterSnap.exists()
      ? Number(remCounterSnap.data().next) || 1
      : 1;

    transaction.set(medicationCounterRef, { next: medNext + 1 }, { merge: true });

    transaction.set(doc(medicationsRef, medicationId), {
      medicationId,
      name: trimmedName,
      dosage: trimmedDosage,
      frequency: trimmedFrequency,
      instructions: trimmedInstructions,
      startDate,
      endDate,
      userId,
      staffId,
      status: MEDICATION_STATUS_ACTIVE,
      createdAt: serverTimestamp(),
    });

    const reminderIds = [];
    for (const reminderTime of times) {
      const reminderId = `R${String(remNext).padStart(5, "0")}`;
      remNext += 1;
      reminderIds.push(reminderId);

      const reminderDateTime = combineDateAndTime(reminderDate, reminderTime);
      const reminderTs = Timestamp.fromDate(reminderDateTime);
      const reminderLabel = formatReminderLabel(reminderDateTime);

      transaction.set(doc(remindersRef, reminderId), {
        reminderId,
        reminderTime: reminderTs,
        reminderTimeLabel: reminderLabel,
        reminderType: "Notification",
        reminderMessage: message,
        repeatPattern,
        status: "Pending",
        medicationId,
        userId,
        staffId,
        completedDate: "",
        createdAt: serverTimestamp(),
      });
    }

    transaction.set(reminderCounterRef, { next: remNext }, { merge: true });

    return { medicationId, reminderIds };
  });
}

/**
 * Updates medication fields and syncs reminder documents (preserves status/completedDate).
 */
export async function updateMedicationWithReminder({
  medicationId,
  staffId,
  name,
  dosage,
  frequency,
  instructions,
  startDate,
  endDate,
  reminderDate,
  reminderTimes,
}) {
  const trimmedId = String(medicationId || "").trim();
  const medicationRef = doc(db, MEDICATIONS_COLLECTION, trimmedId);
  const medicationSnap = await getDoc(medicationRef);
  if (!medicationSnap.exists()) {
    throw new Error("Medication not found.");
  }

  if (
    String(medicationSnap.data().status || MEDICATION_STATUS_ACTIVE).trim() ===
    MEDICATION_STATUS_CANCELLED
  ) {
    throw new Error("Cancelled medications cannot be edited.");
  }

  const userId = (medicationSnap.data().userId || medicationSnap.data().userID || "").trim();
  const validationError = validateMedicationUpdateInput({
    name,
    dosage,
    frequency,
    instructions,
    startDate,
    endDate,
    reminderDate,
    reminderTimes,
    userId,
    staffId,
  });
  if (validationError) {
    throw new Error(validationError);
  }

  const trimmedName = name.trim();
  const trimmedDosage = dosage.trim();
  const trimmedFrequency = frequency.trim();
  const trimmedInstructions = formatTypedSentence(instructions);
  const times = reminderTimes.map((time) => String(time).trim());
  const repeatPattern = repeatPatternForFrequency(trimmedFrequency);
  const message = `Take ${trimmedName} — ${trimmedDosage}`;

  const remindersQuery = query(
    collection(db, MEDICATION_REMINDERS_COLLECTION),
    where("medicationId", "==", trimmedId),
  );
  const remindersSnap = await getDocs(remindersQuery);
  const existingReminders = sortReminderDocsByTime(remindersSnap.docs);

  const reminderCounterRef = doc(db, ...REMINDER_COUNTER_PATH);
  const remindersRef = collection(db, MEDICATION_REMINDERS_COLLECTION);

  await runTransaction(db, async (transaction) => {
    const medDoc = await transaction.get(medicationRef);
    if (!medDoc.exists()) {
      throw new Error("Medication not found.");
    }

    const needNewReminders = times.length > existingReminders.length;
    let remNext = 1;
    if (needNewReminders) {
      const remCounterSnap = await transaction.get(reminderCounterRef);
      remNext = remCounterSnap.exists()
        ? Number(remCounterSnap.data().next) || 1
        : 1;
    }

    transaction.update(medicationRef, {
      name: trimmedName,
      dosage: trimmedDosage,
      frequency: trimmedFrequency,
      instructions: trimmedInstructions,
      startDate,
      endDate,
      staffId,
      updatedAt: serverTimestamp(),
    });

    for (let i = 0; i < times.length; i += 1) {
      const reminderTime = times[i];
      const reminderDateTime = combineDateAndTime(reminderDate, reminderTime);
      const reminderTs = Timestamp.fromDate(reminderDateTime);
      const reminderLabel = formatReminderLabel(reminderDateTime);
      const existing = existingReminders[i];

      if (existing) {
        transaction.update(existing.ref, {
          reminderTime: reminderTs,
          reminderTimeLabel: reminderLabel,
          reminderMessage: message,
          repeatPattern,
          staffId,
          updatedAt: serverTimestamp(),
        });
      } else {
        const reminderId = `R${String(remNext).padStart(5, "0")}`;
        remNext += 1;

        transaction.set(doc(remindersRef, reminderId), {
          reminderId,
          reminderTime: reminderTs,
          reminderTimeLabel: reminderLabel,
          reminderType: "Notification",
          reminderMessage: message,
          repeatPattern,
          status: "Pending",
          medicationId: trimmedId,
          userId,
          staffId,
          completedDate: "",
          createdAt: serverTimestamp(),
        });
      }
    }

    if (needNewReminders) {
      transaction.set(reminderCounterRef, { next: remNext }, { merge: true });
    }

    for (let i = times.length; i < existingReminders.length; i += 1) {
      transaction.delete(existingReminders[i].ref);
    }
  });

  return { medicationId: trimmedId };
}

/**
 * Cancels a medication and stops its reminders (staff action from edit modal).
 */
export async function cancelMedication({ medicationId, staffId }) {
  const trimmedId = String(medicationId || "").trim();
  if (!trimmedId) {
    throw new Error("Medication is required.");
  }
  if (!staffId || !STAFF_ID_PATTERN.test(staffId)) {
    throw new Error("Staff ID is missing or invalid.");
  }

  const medicationRef = doc(db, MEDICATIONS_COLLECTION, trimmedId);
  const medicationSnap = await getDoc(medicationRef);
  if (!medicationSnap.exists()) {
    throw new Error("Medication not found.");
  }

  const data = medicationSnap.data();
  if (
    String(data.status || MEDICATION_STATUS_ACTIVE).trim() ===
    MEDICATION_STATUS_CANCELLED
  ) {
    throw new Error("This medication is already cancelled.");
  }

  const today = todayDateString();
  const remindersSnap = await getDocs(
    query(
      collection(db, MEDICATION_REMINDERS_COLLECTION),
      where("medicationId", "==", trimmedId),
    ),
  );

  const batch = writeBatch(db);
  batch.update(medicationRef, {
    status: MEDICATION_STATUS_CANCELLED,
    endDate: today,
    cancelledAt: serverTimestamp(),
    staffId,
    updatedAt: serverTimestamp(),
  });

  for (const docSnap of remindersSnap.docs) {
    batch.update(docSnap.ref, {
      status: "Missed",
      updatedAt: serverTimestamp(),
    });
  }

  await batch.commit();
  return { medicationId: trimmedId };
}

function staffDisplayName(staff) {
  return formatStaffDisplayName(staff);
}

export function isMedicationActiveOnDate(startDate, endDate, yyyyMmDd, status = MEDICATION_STATUS_ACTIVE) {
  if (String(status || MEDICATION_STATUS_ACTIVE).trim() === MEDICATION_STATUS_CANCELLED) {
    return false;
  }
  const start = String(startDate || "").trim();
  const end = String(endDate || "").trim();
  if (!start || !end) return false;
  return yyyyMmDd >= start && yyyyMmDd <= end;
}

export function mapMedicationDoc(docSnap, staffByStaffId) {
  const data = docSnap.data();
  const staffId = data.staffId || data.staffID || "";
  const staff = staffByStaffId?.get(staffId);
  const today = todayDateString();
  const startDate = (data.startDate || "").trim();
  const endDate = (data.endDate || "").trim();
  const status = String(data.status || MEDICATION_STATUS_ACTIVE).trim();
  const cancelled = status === MEDICATION_STATUS_CANCELLED;

  return {
    medicationId: (data.medicationId || docSnap.id || "").trim(),
    name: (data.name || "—").trim(),
    dosage: (data.dosage || "—").trim(),
    frequency: (data.frequency || "—").trim(),
    instructions: (data.instructions || "").trim(),
    startDate,
    endDate,
    status,
    cancelled,
    active: isMedicationActiveOnDate(startDate, endDate, today, status),
    doctor: staff ? staffDisplayName(staff) : staffId || "—",
  };
}

function mapMedicationsSnap(snap, staffByStaffId) {
  if (snap.empty) return [];
  return snap.docs
    .filter((docSnap) => {
      const status = String(docSnap.data().status || MEDICATION_STATUS_ACTIVE).trim();
      return status !== MEDICATION_STATUS_CANCELLED;
    })
    .map((docSnap) => mapMedicationDoc(docSnap, staffByStaffId))
    .sort((a, b) => String(b.startDate).localeCompare(String(a.startDate)));
}

export function isMedicationsAccessError(error) {
  const code = error?.code || "";
  const msg = (error?.message || "").toLowerCase();
  return (
    code === "permission-denied" ||
    msg.includes("insufficient permissions") ||
    msg.includes("missing or insufficient permissions")
  );
}

/** Real-time medications for one patient (patients page modal). */
export function subscribeMedicationsByUserId(userId, onData, onError) {
  const trimmedUserId = String(userId || "").trim();
  let staffByStaffId = new Map();
  let medicationsSnap = null;
  let ensureTimer = null;

  function emit() {
    if (!medicationsSnap) return;
    onData(mapMedicationsSnap(medicationsSnap, staffByStaffId));
  }

  async function scheduleEnsure() {
    clearTimeout(ensureTimer);
    ensureTimer = setTimeout(async () => {
      try {
        await ensureRemindersForMedications(trimmedUserId);
      } catch (error) {
        console.warn("ensureRemindersForMedications failed:", error);
      }
    }, 400);
  }

  const medicationsQuery = query(
    collection(db, MEDICATIONS_COLLECTION),
    where("userId", "==", trimmedUserId),
  );

  const unsubs = [
    onSnapshot(
      collection(db, HEALTHCARE_STAFF_COLLECTION),
      (snap) => {
        const staffList = snap.docs
          .map((docSnap) => {
            const data = docSnap.data();
            return {
              staffID: data.staffID || "",
              name: data.name || "",
              role: data.role || "",
              status: data.status || "",
            };
          })
          .filter((staff) => staff.status === "Active" && staff.staffID);
        staffByStaffId = new Map(staffList.map((staff) => [staff.staffID, staff]));
        emit();
      },
      onError,
    ),
    onSnapshot(
      medicationsQuery,
      (snap) => {
        medicationsSnap = snap;
        scheduleEnsure();
        emit();
      },
      onError,
    ),
  ];

  const stopAll = () => {
    clearTimeout(ensureTimer);
    for (const unsub of unsubs) {
      if (typeof unsub === "function") unsub();
    }
  };
  trackFirestoreListener(stopAll);
  return stopAll;
}

/** Default end date one year from start (YYYY-MM-DD strings). */
export function defaultMedicationEndDate(startDate = todayDateString()) {
  const [y, m, d] = startDate.split("-").map(Number);
  const end = new Date(y + 1, m - 1, d);
  const ey = end.getFullYear();
  const em = String(end.getMonth() + 1).padStart(2, "0");
  const ed = String(end.getDate()).padStart(2, "0");
  return `${ey}-${em}-${ed}`;
}
