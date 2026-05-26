import {
  collection,
  doc,
  getDocs,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  Timestamp,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { fetchPatients } from "./user-patients-service.js";
import { fetchActiveStaff } from "./staff-list-service.js";

export const APPOINTMENTS_COLLECTION = "appointments";
export const APPOINTMENT_COUNTER_PATH = ["system", "appointmentCounter"];

export const APPOINTMENT_TYPES = [
  "Consultation",
  "Follow-up",
  "Therapy Session",
  "Emergency",
];

export const APPOINTMENT_STATUSES = ["Scheduled", "Cancelled", "Rescheduled"];

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
  if (value === "rescheduled") return "rescheduled";
  return "scheduled";
}

function staffDisplayName(staff) {
  if (!staff?.name) return staff?.staffID || "—";
  const role = (staff.role || "").toLowerCase();
  if (role.includes("doctor") || role.includes("dr")) {
    return staff.name.startsWith("Dr.") ? staff.name : `Dr. ${staff.name}`;
  }
  return staff.name;
}

async function buildLookups() {
  const [patients, staffList] = await Promise.all([
    fetchPatients(),
    fetchActiveStaff(),
  ]);

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
    location: data.location || "—",
    staff: staff ? staffDisplayName(staff) : staffId || "—",
    staffId,
    notes: data.notes || "",
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
      notes: (notes || "").trim(),
      location: location.trim(),
      appointmentType,
      userId,
      staffId,
      createdAt: serverTimestamp(),
    });
  });
}
