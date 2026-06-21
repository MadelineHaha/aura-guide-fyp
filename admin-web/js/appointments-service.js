import {
  collection,
  deleteField,
  doc,
  getDocs,
  onSnapshot,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  Timestamp,
  updateDoc,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { createMedicationWithReminder } from "./medications-service.js";
import { logStaffActivity } from "./activity-logs-service.js";
import { LOG_ACTIONS } from "./activity-log-actions.js";
import { formatTypedSentence } from "./text-format.js";
import { trackFirestoreListener } from "./firestore-realtime.js";
import {
  fetchPatients,
  mapUserDoc,
  USERS_COLLECTION,
} from "./user-patients-service.js";
import { fetchActiveStaff } from "./staff-list-service.js";
import { HEALTHCARE_STAFF_COLLECTION } from "./staff-auth.js";
import { formatStaffDisplayName } from "./staff-name-format.js";
import { isClinicTimeValue } from "./appointment-time-slots.js";

export const APPOINTMENTS_COLLECTION = "appointments";
export const APPOINTMENT_COUNTER_PATH = ["system", "appointmentCounter"];

/** Mobile book flow session types + staff-created types. */
export const APPOINTMENT_TYPES = [
  "General Check-up",
  "Therapist Session",
  "Urgent Consultation",
  "Consultation",
  "Follow-up",
  "Therapy Session",
  "Emergency",
];

export const APPOINTMENT_STATUSES = [
  "Pending",
  "Scheduled",
  "Rescheduled",
  "Done",
  "Cancelled",
];

function timestampToDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

export function todayDateString() {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

export function combineDateAndTime(dateStr, timeStr) {
  const [y, m, d] = dateStr.split("-").map(Number);
  const [hh, mm] = timeStr.split(":").map(Number);
  return new Date(y, m - 1, d, hh, mm, 0, 0);
}

/** ERD format: YYYY-MM-DD HH:mm:SS */
export function formatErdDatetime(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  const hh = String(date.getHours()).padStart(2, "0");
  const mm = String(date.getMinutes()).padStart(2, "0");
  const ss = String(date.getSeconds()).padStart(2, "0");
  return `${y}-${m}-${d} ${hh}:${mm}:${ss}`;
}

export function normalizeStatus(status) {
  const value = (status || "Scheduled").toLowerCase();
  if (value === "cancelled") return "cancelled";
  if (value === "done" || value === "completed") return "done";
  if (value === "rescheduled") return "rescheduled";
  if (value === "pending") return "pending";
  return "scheduled";
}

export function isDateTimeChanged(previousDate, date, time) {
  if (!previousDate) return false;
  return previousDate.getTime() !== combineDateAndTime(date, time).getTime();
}

export function dateToInputValue(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function timeToInputValue(date) {
  const hh = String(date.getHours()).padStart(2, "0");
  const mm = String(date.getMinutes()).padStart(2, "0");
  return `${hh}:${mm}`;
}

function staffDisplayName(staff) {
  return formatStaffDisplayName(staff);
}

function buildLookupsFrom(patients, staffList) {
  const usersByUserId = new Map();
  for (const patient of patients) {
    usersByUserId.set(patient.patientId, patient);
  }

  const staffByStaffId = new Map();
  for (const staff of staffList) {
    staffByStaffId.set(staff.staffID, staff);
  }

  return { usersByUserId, staffByStaffId };
}

async function buildLookups() {
  const [patients, staffList] = await Promise.all([
    fetchPatients(),
    fetchActiveStaff(),
  ]);
  return buildLookupsFrom(patients, staffList);
}

export function mapAppointmentDoc(docSnap, lookups) {
  const data = docSnap.data();
  const dateTime = timestampToDate(data.dateTime || data.scheduledAt);
  const userId = data.userId || data.patientUserId || "";
  const staffId = data.staffId || data.staffID || "";
  const patient = lookups.usersByUserId.get(userId);
  const staff = lookups.staffByStaffId.get(staffId);

  return {
    id: docSnap.id,
    appointmentId: data.appointmentId || docSnap.id,
    patientName: patient?.name || "—",
    patientId: userId || "—",
    datetime: dateTime ? formatErdDatetime(dateTime) : "—",
    dateTime,
    appointmentType: data.appointmentType || data.type || "—",
    location: (data.location || "").trim() || "—",
    staff: staff ? staffDisplayName(staff) : staffId || "—",
    staffId,
    notes: data.notes || "",
    clinicalSummary: (data.clinicalSummary || "").trim(),
    recommendation: (data.recommendation || "").trim(),
    followUpDate: (data.followUpDate || "").trim(),
    status: normalizeStatus(data.status),
  };
}

export async function fetchAppointments() {
  const lookups = await buildLookups();
  const q = query(
    collection(db, APPOINTMENTS_COLLECTION),
    orderBy("dateTime", "asc"),
  );
  const snap = await getDocs(q);
  return snap.docs.map((docSnap) => mapAppointmentDoc(docSnap, lookups));
}

/**
 * Real-time appointments (and related patient/staff labels).
 * Updates only when Firestore documents change.
 */
function mapActiveStaffFromSnap(snap) {
  return snap.docs
    .map((docSnap) => {
      const data = docSnap.data();
      return {
        uid: docSnap.id,
        staffID: data.staffID || "",
        name: data.name || "",
        role: data.role || "",
        status: data.status || "",
      };
    })
    .filter((staff) => staff.status === "Active" && staff.staffID);
}

export function subscribeAppointments(onData, onError) {
  let patients = [];
  let staffList = [];
  let appointmentDocs = [];

  function emit() {
    const lookups = buildLookupsFrom(patients, staffList);
    onData(appointmentDocs.map((docSnap) => mapAppointmentDoc(docSnap, lookups)));
  }

  const appointmentsQuery = query(
    collection(db, APPOINTMENTS_COLLECTION),
    orderBy("dateTime", "asc"),
  );

  const unsubs = [
    onSnapshot(
      collection(db, USERS_COLLECTION),
      (snap) => {
        patients = snap.docs.map(mapUserDoc);
        emit();
      },
      onError,
    ),
    onSnapshot(
      collection(db, HEALTHCARE_STAFF_COLLECTION),
      (snap) => {
        staffList = mapActiveStaffFromSnap(snap);
        emit();
      },
      onError,
    ),
    onSnapshot(
      appointmentsQuery,
      (snap) => {
        appointmentDocs = snap.docs;
        emit();
      },
      onError,
    ),
  ];

  const stopAll = () => {
    for (const unsub of unsubs) {
      if (typeof unsub === "function") unsub();
    }
  };
  trackFirestoreListener(stopAll);
  return stopAll;
}

export async function createAppointment({
  userId,
  staffId,
  date,
  time,
  appointmentType,
  location,
  notes,
}) {
  const dateTime = combineDateAndTime(date, time);
  const now = new Date();

  if (date < todayDateString()) {
    throw new Error("Appointment date cannot be in the past.");
  }

  if (dateTime <= now) {
    throw new Error("Appointment date and time must be in the future.");
  }

  if (!userId || !staffId) {
    throw new Error("Patient and staff are required.");
  }

  if (!isClinicTimeValue(time)) {
    throw new Error("Please select a valid clinic time slot.");
  }

  const counterRef = doc(db, ...APPOINTMENT_COUNTER_PATH);
  const appointmentsRef = collection(db, APPOINTMENTS_COLLECTION);

  await runTransaction(db, async (transaction) => {
    const counterSnap = await transaction.get(counterRef);
    const next = counterSnap.exists()
      ? Number(counterSnap.data().next) || 1
      : 1;
    const appointmentId = `A${String(next).padStart(5, "0")}`;
    const appointmentRef = doc(appointmentsRef, appointmentId);

    transaction.set(counterRef, { next: next + 1 }, { merge: true });
    transaction.set(appointmentRef, {
      appointmentId,
      dateTime: Timestamp.fromDate(dateTime),
      status: "Scheduled",
      notes: formatOptionalTypedSentence(notes),
      location: location.trim(),
      appointmentType,
      userId,
      staffId,
      createdAt: serverTimestamp(),
    });
  });

  await logStaffActivity({
    action: LOG_ACTIONS.BOOK_APPOINTMENT,
    details: `Scheduled ${appointmentType} for patient ${userId} with staff ${staffId}.`,
    type: "info",
  });
}

function formatOptionalTypedSentence(text) {
  const trimmed = String(text || "").trim();
  return trimmed ? formatTypedSentence(trimmed) : "";
}

function appointmentRef(appointmentId) {
  return doc(db, APPOINTMENTS_COLLECTION, appointmentId);
}

export async function updateAppointmentStatus(appointmentId, status) {
  await updateDoc(appointmentRef(appointmentId), {
    status,
    updatedAt: serverTimestamp(),
  });
  await logStaffActivity({
    action: LOG_ACTIONS.UPDATE_APPOINTMENT_STATUS,
    details: `Appointment ${appointmentId} set to ${status}.`,
    type: "info",
  });
}

/** Staff assigns location and confirms a patient-booked pending appointment. */
export async function acceptAppointment(appointmentId, location) {
  const loc = (location || "").trim();
  if (!loc) {
    throw new Error("Location is required before accepting.");
  }

  await updateDoc(appointmentRef(appointmentId), {
    status: "Scheduled",
    location: loc,
    updatedAt: serverTimestamp(),
  });
  await logStaffActivity({
    action: LOG_ACTIONS.ACCEPT_APPOINTMENT,
    details: `Accepted pending appointment ${appointmentId} at ${loc}.`,
    type: "info",
  });
}

export async function updateAppointment({
  appointmentId,
  userId,
  date,
  time,
  appointmentType,
  location,
  notes,
  requireFuture = true,
  currentStatus = "scheduled",
  previousDateTime = null,
}) {
  const dateTime = combineDateAndTime(date, time);
  const now = new Date();

  if (date < todayDateString()) {
    throw new Error("Appointment date cannot be in the past.");
  }

  if (requireFuture && dateTime <= now) {
    throw new Error("Appointment date and time must be in the future.");
  }

  if (!userId) {
    throw new Error("Patient is required.");
  }

  if (!isClinicTimeValue(time)) {
    throw new Error("Please select a valid clinic time slot.");
  }

  const payload = {
    userId,
    dateTime: Timestamp.fromDate(dateTime),
    appointmentType,
    location: location.trim(),
    notes: formatOptionalTypedSentence(notes),
    updatedAt: serverTimestamp(),
  };

  const normalized = normalizeStatus(currentStatus);
  const dateChanged = isDateTimeChanged(previousDateTime, date, time);
  if (
    dateChanged &&
    (normalized === "scheduled" || normalized === "rescheduled")
  ) {
    payload.status = "Rescheduled";
  }

  await updateDoc(appointmentRef(appointmentId), payload);
  await logStaffActivity({
    action: LOG_ACTIONS.UPDATE_APPOINTMENT,
    details: `Updated appointment ${appointmentId} for patient ${userId}.`,
    type: "info",
  });
}

const CLINICAL_SUMMARY_MAX = 500;
const RECOMMENDATION_MAX = 500;

/**
 * Marks appointment Done and saves visit notes. Optionally prescribes medications.
 */
export async function completeAppointment({
  appointmentId,
  clinicalSummary,
  recommendation,
  followUpDate,
  staffId,
  userId,
  medications = [],
}) {
  const summary = formatTypedSentence(clinicalSummary);
  const rec = formatOptionalTypedSentence(recommendation);
  const followUp = String(followUpDate || "").trim();

  if (!summary) {
    throw new Error("Clinical summary is required.");
  }
  if (summary.length > CLINICAL_SUMMARY_MAX) {
    throw new Error(
      `Clinical summary must be ${CLINICAL_SUMMARY_MAX} characters or less.`,
    );
  }
  if (rec.length > RECOMMENDATION_MAX) {
    throw new Error(
      `Recommendation must be ${RECOMMENDATION_MAX} characters or less.`,
    );
  }
  if (!appointmentId) {
    throw new Error("Appointment is required.");
  }

  const payload = {
    status: "Done",
    clinicalSummary: summary,
    recommendation: rec,
    completedAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  };

  // No date selected = no follow-up scheduled.
  payload.followUpDate = followUp ? followUp : deleteField();

  await updateDoc(appointmentRef(appointmentId), payload);

  await logStaffActivity({
    action: LOG_ACTIONS.COMPLETE_APPOINTMENT,
    details: `Marked appointment ${appointmentId} as done for patient ${userId}.`,
    type: "info",
  });

  for (const medication of medications) {
    await createMedicationWithReminder({
      userId,
      staffId,
      name: medication.name,
      dosage: medication.dosage,
      frequency: medication.frequency,
      instructions: medication.instructions,
      startDate: medication.startDate,
      endDate: medication.endDate,
      reminderDate: medication.reminderDate,
      reminderTimes: medication.reminderTimes,
    });
  }
}
