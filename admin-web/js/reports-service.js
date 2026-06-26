import {
  collection,
  getDocs,
  limit,
  orderBy,
  query,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { LOG_ACTIONS } from "./activity-log-actions.js";
import { mapActivityLogDoc, ACTIVITY_LOGS_COLLECTION } from "./activity-logs-service.js";
import { APPOINTMENTS_COLLECTION } from "./appointments-service.js";
import { EMERGENCY_ALERTS_COLLECTION, mapEmergencyAlertDoc } from "./emergency-alerts-service.js";
import { MEDICATION_REMINDERS_COLLECTION, MEDICATIONS_COLLECTION } from "./medications-service.js";
import { mapUserDoc, USERS_COLLECTION } from "./user-patients-service.js";
import { normalizeStaffRole } from "./staff-rbac.js";

export const PATIENT_ACTIVITY_COLLECTION = "activity";
/** @deprecated Legacy collection — reports fall back if `activity` is empty. */
export const PATIENT_DAILY_METRICS_COLLECTION = "patientdailymetrics";

export const REPORT_RANGES = {
  TODAY: "today",
  MONTH: "month",
  THREE_MONTHS: 3,
  SIX_MONTHS: 6,
  ALL: 0,
};

/** Medication adherence result statuses for reports UI. */
export const MED_ADHERENCE_STATUS = {
  NA: "N/A",
  PENDING: "Pending",
  CALCULATED: "Calculated",
};

const MONTH_LABELS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const ATTENDED_STATUSES = new Set(["done", "completed"]);
const CANCELLED = "cancelled";
const FALL_ALERT_PATTERN = /fall detection/i;

function timestampToDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

function parseErdDateTime(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(trimmed)) return null;
  const [datePart, timePart] = trimmed.split(" ");
  const parsed = new Date(`${datePart}T${timePart}`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function parseAlertDate(alert) {
  const erd = parseErdDateTime(alert?.dateTime);
  if (erd) return erd;
  return timestampToDate(alert?.dateTime);
}

const CLINIC_OFFSET_MS = 8 * 60 * 60 * 1000;

function dateKeyClinic(fromDate = new Date()) {
  const shifted = new Date(fromDate.getTime() + CLINIC_OFFSET_MS);
  const y = shifted.getUTCFullYear();
  const m = String(shifted.getUTCMonth() + 1).padStart(2, "0");
  const d = String(shifted.getUTCDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function mergeStepMetrics(activityRows, legacyRows) {
  const map = new Map();
  for (const row of legacyRows) {
    map.set(`${row.userId}|${row.date}`, row);
  }
  for (const row of activityRows) {
    map.set(`${row.userId}|${row.date}`, row);
  }
  return [...map.values()];
}

function stepsForUser(metrics, userId, rangeKey, rangeStart, rangeEnd) {
  if (rangeKey === REPORT_RANGES.TODAY) {
    const todayStr = dateKeyClinic();
    const match = metrics.find(
      (row) => row.userId === userId && row.date === todayStr,
    );
    return match?.steps ?? 0;
  }
  return averageStepsForUser(metrics, userId, rangeStart, rangeEnd);
}

function dateKey(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

function monthKey(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, "0")}`;
}

function monthLabelFromKey(key) {
  const [, monthPart] = key.split("-");
  const index = Number(monthPart) - 1;
  return MONTH_LABELS[index] || key;
}

function daysBetweenInclusive(start, end) {
  const msPerDay = 24 * 60 * 60 * 1000;
  const startUtc = Date.UTC(start.getFullYear(), start.getMonth(), start.getDate());
  const endUtc = Date.UTC(end.getFullYear(), end.getMonth(), end.getDate());
  return Math.max(1, Math.floor((endUtc - startUtc) / msPerDay) + 1);
}

export function resolveReportRangeStart(rangeKey, endDate = new Date()) {
  return resolveReportRange(rangeKey, endDate).rangeStart;
}

export function resolveReportRange(rangeKey, endDate = new Date()) {
  const end = new Date(endDate);
  end.setHours(23, 59, 59, 999);

  if (rangeKey === REPORT_RANGES.TODAY || rangeKey === "today") {
    const start = new Date(end);
    start.setHours(0, 0, 0, 0);
    return { rangeStart: start, rangeEnd: end };
  }

  if (rangeKey === REPORT_RANGES.MONTH || rangeKey === "month") {
    const start = new Date(end);
    start.setDate(1);
    start.setHours(0, 0, 0, 0);
    return { rangeStart: start, rangeEnd: end };
  }

  const months = Number(rangeKey);
  if (!months || months <= 0) {
    return { rangeStart: null, rangeEnd: null };
  }

  const start = new Date(end);
  start.setHours(0, 0, 0, 0);
  start.setMonth(start.getMonth() - months);
  return { rangeStart: start, rangeEnd: end };
}

function inRange(date, rangeStart, rangeEnd) {
  if (!date) return false;
  if (rangeStart && date < rangeStart) return false;
  if (rangeEnd && date > rangeEnd) return false;
  return true;
}

function readUserId(data) {
  return String(data.userId || data.userID || "").trim();
}

function mapMetricDoc(docSnap) {
  const data = docSnap.data() || {};
  const userId = readUserId(data);
  const date = String(data.date || "").trim();
  const steps = Number(data.steps);
  if (!userId || !date || !Number.isFinite(steps)) return null;
  return { userId, date, steps: Math.max(0, Math.round(steps)) };
}

function mapReminderDoc(docSnap) {
  const data = docSnap.data() || {};
  const userId = readUserId(data);
  if (!userId) return null;
  const reminderTime = timestampToDate(data.reminderTime);
  return {
    userId,
    status: String(data.status || "").trim(),
    completedDate: String(data.completedDate || "").trim(),
    missedDate: String(data.missedDate || "").trim(),
    doseDate: String(data.doseDate || "").trim(),
    slotReminderId: String(data.slotReminderId || "").trim(),
    repeatPattern: String(data.repeatPattern || "Daily").trim(),
    medicationId: String(data.medicationId || "").trim(),
    reminderTime,
  };
}

function mapMedicationDoc(docSnap) {
  const data = docSnap.data() || {};
  const userId = readUserId(data);
  const medicationId = String(data.medicationId || docSnap.id).trim();
  if (!userId || !medicationId) return null;
  return {
    medicationId,
    userId,
    startDate: String(data.startDate || "").trim(),
    endDate: String(data.endDate || "").trim(),
    status: String(data.status || "Active").trim(),
  };
}

function isMedicationActiveOnDate(medication, dateKey) {
  if (!medication) return false;
  if (medication.status === "Cancelled") return false;
  if (!medication.startDate || !medication.endDate) return true;
  return medication.startDate <= dateKey && medication.endDate >= dateKey;
}

function isDailyDoseReminder(reminder) {
  return !!reminder.doseDate;
}

function dateFromDateKey(dateKey) {
  const parsed = new Date(`${dateKey}T12:00:00`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function mapAppointmentRow(docSnap) {
  const data = docSnap.data() || {};
  const userId = readUserId(data);
  let dateTime = timestampToDate(data.dateTime || data.scheduledAt);
  if (!dateTime && (data.dateTime || data.scheduledAt)) {
    dateTime = parseErdDateTime(data.dateTime || data.scheduledAt);
    if (!dateTime && typeof (data.dateTime || data.scheduledAt) === "string") {
      const parsed = new Date(data.dateTime || data.scheduledAt);
      if (!Number.isNaN(parsed.getTime())) dateTime = parsed;
    }
  }
  if (!dateTime && data.date) {
    const timeStr = data.time || "12:00:00";
    const parsed = new Date(`${data.date}T${timeStr}`);
    if (!Number.isNaN(parsed.getTime())) dateTime = parsed;
  }
  
  const status = String(data.status || "Scheduled").toLowerCase();
  if (!userId || !dateTime) return null;
  return { userId, dateTime, status };
}

function isFallAlert(alert) {
  const type = String(alert?.alertType || "").trim();
  return FALL_ALERT_PATTERN.test(type);
}

function extractAlertIdFromLog(details) {
  const match = String(details || "").match(/E\d{5}/);
  return match ? match[0] : "";
}

function buildResponseTimeMap(logs) {
  const map = new Map();
  for (const log of logs) {
    if (log.action !== LOG_ACTIONS.RESPOND_EMERGENCY) continue;
    const alertId = extractAlertIdFromLog(log.details);
    if (!alertId || !log.timestampMs) continue;
    if (!map.has(alertId) || log.timestampMs < map.get(alertId)) {
      map.set(alertId, log.timestampMs);
    }
  }
  return map;
}

function enumerateDateKeysBetween(rangeStart, rangeEnd) {
  if (!rangeEnd) return [];
  const keys = [];
  const cursor = new Date(rangeStart || rangeEnd);
  cursor.setHours(0, 0, 0, 0);
  const end = new Date(rangeEnd);
  end.setHours(23, 59, 59, 999);
  while (cursor <= end) {
    keys.push(dateKey(cursor));
    cursor.setDate(cursor.getDate() + 1);
  }
  return keys;
}

/** Clinic calendar days between two instants (for medication dose scheduling). */
function enumerateClinicDateKeysBetween(rangeStart, rangeEnd) {
  if (!rangeEnd) return [];
  const keys = [];
  const cursor = new Date(rangeStart || rangeEnd);
  cursor.setHours(0, 0, 0, 0);
  const end = new Date(rangeEnd);
  end.setHours(23, 59, 59, 999);
  while (cursor <= end) {
    keys.push(dateKeyClinic(cursor));
    cursor.setDate(cursor.getDate() + 1);
  }
  return keys;
}

function adherenceRangeStartForUser(rangeStart, rangeEnd, reminders, userId) {
  if (rangeStart) return new Date(rangeStart);

  const userReminders = reminders.filter((reminder) => reminder.userId === userId);
  let earliest = null;
  for (const reminder of userReminders) {
    if (!reminder.reminderTime) continue;
    const dayKey = dateKeyClinic(reminder.reminderTime);
    const [year, month, day] = dayKey.split("-").map(Number);
    const dayStart = new Date(year, month - 1, day);
    dayStart.setHours(0, 0, 0, 0);
    if (!earliest || dayStart < earliest) earliest = dayStart;
  }

  if (earliest) return earliest;

  const today = new Date(rangeEnd);
  today.setHours(0, 0, 0, 0);
  return today;
}

function reminderClockInClinic(reminderTime) {
  if (!reminderTime) return { hours: 0, minutes: 0 };
  const shifted = new Date(reminderTime.getTime() + CLINIC_OFFSET_MS);
  return {
    hours: shifted.getUTCHours(),
    minutes: shifted.getUTCMinutes(),
  };
}

function doseInstantClinic(dayKey, reminder) {
  const [year, month, day] = dayKey.split("-").map(Number);
  const clock = reminderClockInClinic(reminder.reminderTime);
  return new Date(
    Date.UTC(year, month - 1, day, clock.hours - 8, clock.minutes, 0, 0),
  );
}

function countScheduledDueDoses(reminders, medications, userId, rangeStart, rangeEnd) {
  const medById = new Map(medications.map((med) => [med.medicationId, med]));
  const dailyDoses = reminders.filter(
    (reminder) =>
      reminder.userId === userId &&
      isDailyDoseReminder(reminder) &&
      reminder.reminderTime,
  );

  const now = new Date();
  const evaluationEnd =
    rangeEnd && rangeEnd.getTime() < now.getTime() ? rangeEnd : now;

  if (dailyDoses.length > 0) {
    let scheduledDue = 0;
    for (const reminder of dailyDoses) {
      const doseKey = reminder.doseDate;
      const doseDate = dateFromDateKey(doseKey);
      if (!doseDate) continue;
      if (rangeStart && doseDate < rangeStart) continue;
      if (rangeEnd && doseDate > rangeEnd) continue;
      const medication = medById.get(reminder.medicationId);
      if (!isMedicationActiveOnDate(medication, doseKey)) continue;
      const doseAt = doseInstantClinic(doseKey, reminder);
      if (doseAt.getTime() <= evaluationEnd.getTime()) {
        scheduledDue += 1;
      }
    }
    return scheduledDue;
  }

  const dailyReminders = reminders.filter(
    (reminder) =>
      reminder.userId === userId &&
      reminder.repeatPattern.toLowerCase() === "daily" &&
      reminder.reminderTime &&
      !isDailyDoseReminder(reminder),
  );
  if (!dailyReminders.length) return 0;

  const effectiveStart = adherenceRangeStartForUser(
    rangeStart,
    rangeEnd,
    reminders,
    userId,
  );

  let scheduledDue = 0;
  for (const dayKey of enumerateClinicDateKeysBetween(effectiveStart, rangeEnd)) {
    for (const reminder of dailyReminders) {
      const medication = medById.get(reminder.medicationId);
      if (!isMedicationActiveOnDate(medication, dayKey)) continue;
      const doseAt = doseInstantClinic(dayKey, reminder);
      if (doseAt.getTime() <= evaluationEnd.getTime()) {
        scheduledDue += 1;
      }
    }
  }
  return scheduledDue;
}

function countTakenDoses(
  reminders,
  medications,
  logs,
  userId,
  rangeStart,
  rangeEnd,
  todayKey,
) {
  const dailyDoses = reminders.filter(
    (reminder) => reminder.userId === userId && isDailyDoseReminder(reminder),
  );

  if (dailyDoses.length > 0) {
    let taken = 0;
    for (const reminder of dailyDoses) {
      const doseKey = reminder.doseDate;
      const doseDate = dateFromDateKey(doseKey);
      if (!doseDate) continue;
      if (rangeStart && doseDate < rangeStart) continue;
      if (rangeEnd && doseDate > rangeEnd) continue;
      if (reminder.status === "Completed") {
        taken += 1;
      }
    }
    return taken;
  }

  let taken = logs.filter(
    (log) =>
      log.userId === userId &&
      log.action === LOG_ACTIONS.MARK_MEDICATION &&
      log.timestampMs &&
      inRange(new Date(log.timestampMs), rangeStart, rangeEnd),
  ).length;

  const todayInRange = inRange(new Date(), rangeStart, rangeEnd);
  if (!todayInRange) return taken;

  const completedToday = reminders.filter(
    (reminder) =>
      reminder.userId === userId &&
      reminder.status === "Completed" &&
      reminder.completedDate === todayKey,
  ).length;
  // Missed doses (status "Missed" / missedDate) are not counted as taken.

  const logsToday = logs.filter((log) => {
    if (log.userId !== userId || log.action !== LOG_ACTIONS.MARK_MEDICATION) {
      return false;
    }
    if (!log.timestampMs) return false;
    const logDate = dateKeyClinic(new Date(log.timestampMs));
    return logDate === todayKey;
  }).length;

  if (completedToday > logsToday) {
    taken += completedToday - logsToday;
  }

  return taken;
}

/**
 * @returns {{ status: string, adherence: number|null, scheduledDoses?: number, takenDoses?: number }}
 */
export function medicationAdherenceForUser(
  reminders,
  medications,
  logs,
  userId,
  rangeStart,
  rangeEnd,
  todayKey,
) {
  const assigned = reminders.filter((reminder) => reminder.userId === userId);
  if (!assigned.length) {
    return { status: MED_ADHERENCE_STATUS.NA, adherence: null };
  }

  const scheduledDoses = countScheduledDueDoses(
    reminders,
    medications,
    userId,
    rangeStart,
    rangeEnd,
  );
  if (scheduledDoses <= 0) {
    return { status: MED_ADHERENCE_STATUS.PENDING, adherence: null };
  }

  const takenDoses = countTakenDoses(
    reminders,
    medications,
    logs,
    userId,
    rangeStart,
    rangeEnd,
    todayKey,
  );
  const adherence = Math.min(
    100,
    Math.round((takenDoses / scheduledDoses) * 100),
  );

  return {
    status: MED_ADHERENCE_STATUS.CALCULATED,
    adherence,
    scheduledDoses,
    takenDoses,
  };
}

export function adherencePercentValue(result) {
  if (!result || result.status !== MED_ADHERENCE_STATUS.CALCULATED) return null;
  return result.adherence;
}

function appointmentStatsForUser(appointments, userId, rangeStart, rangeEnd) {
  const scoped = appointments.filter(
    (row) =>
      row.userId === userId &&
      row.status !== CANCELLED &&
      inRange(row.dateTime, rangeStart, rangeEnd),
  );
  const attended = scoped.filter((row) => ATTENDED_STATUSES.has(row.status)).length;
  const total = scoped.length;
  const rate = total > 0 ? Math.round((attended / total) * 100) : null;
  return { attended, total, rate };
}

function averageStepsForUser(metrics, userId, rangeStart, rangeEnd) {
  // Each row is one day's total synced from the patient device (`activity`).
  const scoped = metrics.filter((row) => {
    if (row.userId !== userId) return false;
    const date = new Date(`${row.date}T12:00:00`);
    return inRange(date, rangeStart, rangeEnd);
  });
  if (scoped.length === 0) return 0;
  const total = scoped.reduce((sum, row) => sum + row.steps, 0);
  return Math.round(total / scoped.length);
}

function lastActiveForUser(logs, userId) {
  let latest = 0;
  for (const log of logs) {
    if (log.userId !== userId) continue;
    if (log.source !== "mobile") continue;
    if (log.timestampMs > latest) latest = log.timestampMs;
  }
  if (!latest) return "—";
  return dateKey(new Date(latest));
}

function monthBuckets(rangeStart, rangeEnd) {
  const end = rangeEnd || new Date();
  const start =
    rangeStart ||
    new Date(end.getFullYear(), end.getMonth() - 5, 1);
  const buckets = [];
  const cursor = new Date(start.getFullYear(), start.getMonth(), 1);
  const last = new Date(end.getFullYear(), end.getMonth(), 1);
  while (cursor <= last) {
    buckets.push(monthKey(cursor));
    cursor.setMonth(cursor.getMonth() + 1);
  }
  return buckets.slice(-6);
}

function bucketWindow(bucket, daily) {
  if (daily) {
    const dayStart = new Date(`${bucket}T00:00:00`);
    const dayEnd = new Date(`${bucket}T23:59:59`);
    return { start: dayStart, end: dayEnd };
  }
  const monthStart = new Date(`${bucket}-01T00:00:00`);
  const monthEnd = new Date(
    monthStart.getFullYear(),
    monthStart.getMonth() + 1,
    0,
    23,
    59,
    59,
    999,
  );
  return { start: monthStart, end: monthEnd };
}

function trendBuckets(rangeStart, rangeEnd, rangeKey) {
  if (rangeKey === REPORT_RANGES.TODAY) {
    const todayStr = dateKeyClinic();
    return {
      buckets: [todayStr],
      labels: ["Today"],
      daily: true,
    };
  }

  if (rangeStart && rangeEnd) {
    const startKey = dateKey(rangeStart);
    const endKey = dateKey(rangeEnd);
    if (startKey === endKey) {
      return {
        buckets: [startKey],
        labels: ["Today"],
        daily: true,
      };
    }
  }

  const monthKeys = monthBuckets(rangeStart, rangeEnd);
  return {
    buckets: monthKeys,
    labels: monthKeys.map(monthLabelFromKey),
    daily: false,
  };
}

function metricForMonth(values) {
  if (!values.length) return 0;
  return Math.round(values.reduce((sum, value) => sum + value, 0) / values.length);
}

/** Average daily steps across patients (from Firestore `activity` / device sync). */
function cohortAverageSteps(patients, metrics, rangeStart, rangeEnd) {
  if (!patients.length) return 0;
  const values = patients.map((patient) =>
    averageStepsForUser(metrics, patient.patientId, rangeStart, rangeEnd),
  );
  return metricForMonth(values);
}

/** Share of emergency alerts marked Resolved in a period. */
function emergencyResolutionRate(alerts, rangeStart, rangeEnd) {
  const scoped = alerts.filter((alert) =>
    inRange(parseAlertDate(alert), rangeStart, rangeEnd),
  );
  if (scoped.length === 0) return 0;
  const resolved = scoped.filter(
    (alert) => String(alert.status || "").toLowerCase() === "resolved",
  ).length;
  return Math.round((resolved / scoped.length) * 100);
}

/** Patients with at least one mobile activity log in the period. */
function mobileEngagementRate(patients, logs, rangeStart, rangeEnd) {
  if (!patients.length) return 0;
  const engaged = patients.filter((patient) =>
    logs.some(
      (log) =>
        log.userId === patient.patientId &&
        log.source === "mobile" &&
        log.timestampMs &&
        inRange(new Date(log.timestampMs), rangeStart, rangeEnd),
    ),
  ).length;
  return Math.round((engaged / patients.length) * 100);
}

function computeMonthlyTrends({
  patients,
  appointments,
  reminders,
  medications,
  metrics,
  logs,
  rangeStart,
  rangeEnd,
  todayKey,
  rangeKey,
}) {
  const { buckets, labels, daily } = trendBuckets(rangeStart, rangeEnd, rangeKey);

  const stepsSeries = buckets.map((bucket) => {
    const values = metrics
      .filter((row) => (daily ? row.date === bucket : row.date.startsWith(`${bucket}-`)))
      .map((row) => row.steps / 100);
    return metricForMonth(values, bucket);
  });

  const medSeries = buckets.map((bucket) => {
    const { start, end } = bucketWindow(bucket, daily);
    const values = patients
      .map((patient) =>
        adherencePercentValue(
          medicationAdherenceForUser(
            reminders,
            medications,
            logs,
            patient.patientId,
            start,
            end,
            todayKey,
          ),
        ),
      )
      .filter((value) => value != null);
    return metricForMonth(values, bucket);
  });

  const apptSeries = buckets.map((bucket) => {
    const { start, end } = bucketWindow(bucket, daily);
    const values = patients
      .map((patient) => {
        const stats = appointmentStatsForUser(
          appointments,
          patient.patientId,
          start,
          end,
        );
        return stats.rate;
      })
      .filter((value) => value != null);
    return metricForMonth(values, bucket);
  });

  return { labels, stepsSeries, medSeries, apptSeries };
}

function getResolutionBuckets(rangeStart, rangeEnd, grouping) {
  const end = rangeEnd || new Date();
  
  let start = rangeStart;
  if (!start) {
    start = new Date(end.getFullYear(), end.getMonth() - 5, 1);
  }

  const buckets = [];
  
  if (grouping === "daily") {
    const limitStart = new Date(end.getTime() - 29 * 24 * 60 * 60 * 1000);
    const effectiveStart = start > limitStart ? start : limitStart;
    
    const cursor = new Date(effectiveStart);
    cursor.setHours(0, 0, 0, 0);
    while (cursor <= end) {
      const dayStart = new Date(cursor);
      const dayEnd = new Date(cursor);
      dayEnd.setHours(23, 59, 59, 999);
      
      const label = dayStart.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      buckets.push({
        key: dateKey(dayStart),
        label,
        start: dayStart,
        end: dayEnd
      });
      cursor.setDate(cursor.getDate() + 1);
    }
  } else if (grouping === "weekly") {
    const limitStart = new Date(end.getTime() - 11 * 7 * 24 * 60 * 60 * 1000);
    const effectiveStart = start > limitStart ? start : limitStart;
    
    const cursor = new Date(effectiveStart);
    const day = cursor.getDay();
    cursor.setDate(cursor.getDate() - day);
    cursor.setHours(0, 0, 0, 0);
    
    while (cursor <= end) {
      const weekStart = new Date(cursor);
      const weekEnd = new Date(cursor);
      weekEnd.setDate(weekEnd.getDate() + 6);
      weekEnd.setHours(23, 59, 59, 999);
      
      const label = "Week of " + weekStart.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      buckets.push({
        key: dateKey(weekStart),
        label,
        start: weekStart,
        end: weekEnd
      });
      cursor.setDate(cursor.getDate() + 7);
    }
  } else {
    // Monthly buckets
    const cursor = new Date(start.getFullYear(), start.getMonth(), 1);
    const last = new Date(end.getFullYear(), end.getMonth(), 1);
    while (cursor <= last) {
      const monthStart = new Date(cursor.getFullYear(), cursor.getMonth(), 1, 0, 0, 0, 0);
      const monthEnd = new Date(cursor.getFullYear(), cursor.getMonth() + 1, 0, 23, 59, 59, 999);
      
      const label = cursor.toLocaleDateString("en-US", { month: "short", year: "2-digit" });
      buckets.push({
        key: monthKey(cursor),
        label,
        start: monthStart,
        end: monthEnd
      });
      cursor.setMonth(cursor.getMonth() + 1);
    }
    if (buckets.length > 12) {
      return buckets.slice(-12);
    }
  }
  
  return buckets;
}

function computeGrowthData(patients, staffDocs, rangeStart, rangeEnd) {
  const buckets = monthBuckets(rangeStart, rangeEnd);
  const parsedPatients = patients.map((p) => {
    const d = timestampToDate(p.createdAt) || p.createdAt;
    return {
      role: "patient",
      date: d instanceof Date && !Number.isNaN(d.getTime()) ? d : null,
    };
  }).filter((p) => p.date !== null);

  const parsedStaff = staffDocs.map((s) => {
    return {
      role: s.role,
      date: s.createdAt instanceof Date && !Number.isNaN(s.createdAt.getTime()) ? s.createdAt : null,
    };
  }).filter((s) => s.date !== null);

  let cumPatients = 0;
  let cumDoctors = 0;
  let cumTherapists = 0;
  let cumCaregivers = 0;

  if (buckets.length > 0) {
    const monthStart = new Date(`${buckets[0]}-01T00:00:00`);
    cumPatients = parsedPatients.filter((p) => p.date < monthStart).length;
    cumDoctors = parsedStaff.filter((s) => s.role === "doctor" && s.date < monthStart).length;
    cumTherapists = parsedStaff.filter((s) => s.role === "therapist" && s.date < monthStart).length;
    cumCaregivers = parsedStaff.filter((s) => s.role === "caregiver" && s.date < monthStart).length;
  }

  const patientGrowth = [];
  const doctorGrowth = [];
  const therapistGrowth = [];
  const caregiverGrowth = [];
  const labels = buckets.map(monthLabelFromKey);

  for (const bucket of buckets) {
    const monthStart = new Date(`${bucket}-01T00:00:00`);
    const monthEnd = new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 0, 23, 59, 59, 999);

    const newPatients = parsedPatients.filter((p) => p.date >= monthStart && p.date <= monthEnd).length;
    const newDoctors = parsedStaff.filter((s) => s.role === "doctor" && s.date >= monthStart && s.date <= monthEnd).length;
    const newTherapists = parsedStaff.filter((s) => s.role === "therapist" && s.date >= monthStart && s.date <= monthEnd).length;
    const newCaregivers = parsedStaff.filter((s) => s.role === "caregiver" && s.date >= monthStart && s.date <= monthEnd).length;

    cumPatients += newPatients;
    cumDoctors += newDoctors;
    cumTherapists += newTherapists;
    cumCaregivers += newCaregivers;

    patientGrowth.push(cumPatients);
    doctorGrowth.push(cumDoctors);
    therapistGrowth.push(cumTherapists);
    caregiverGrowth.push(cumCaregivers);
  }

  const totalRegisteredPatients = patients.length;
  const totalDoctors = staffDocs.filter((s) => s.role === "doctor").length;
  const totalTherapists = staffDocs.filter((s) => s.role === "therapist").length;
  const totalCaregivers = staffDocs.filter((s) => s.role === "caregiver").length;
  const totalStaff = totalDoctors + totalTherapists + totalCaregivers;

  return {
    labels,
    patientGrowth,
    doctorGrowth,
    therapistGrowth,
    caregiverGrowth,
    totalRegisteredPatients,
    totalStaff,
    totalDoctors,
    totalTherapists,
    totalCaregivers,
  };
}

function computeAppointmentReports(appointments, rangeStart, rangeEnd, grouping = "monthly") {
  const now = new Date();
  const scoped = appointments.filter((row) => inRange(row.dateTime, rangeStart, rangeEnd));
  const nonCancelled = scoped.filter((row) => row.status !== CANCELLED);
  const totalNonCancelled = nonCancelled.length;

  const pastNonCancelled = nonCancelled.filter(row => row.dateTime < now);
  const totalPastNonCancelled = pastNonCancelled.length;

  const doneCount = pastNonCancelled.filter((row) => ATTENDED_STATUSES.has(row.status)).length;
  const missedCount = pastNonCancelled.filter((row) => !ATTENDED_STATUSES.has(row.status)).length;

  const attendanceRate = totalPastNonCancelled > 0 ? Math.round((doneCount / totalPastNonCancelled) * 100) : 0;
  const missedRate = totalPastNonCancelled > 0 ? Math.round((missedCount / totalPastNonCancelled) * 100) : 0;

  const buckets = getResolutionBuckets(rangeStart, rangeEnd, grouping);
  const monthly = buckets.map((bucket) => {
    const monthScoped = nonCancelled.filter((row) => inRange(row.dateTime, bucket.start, bucket.end));
    const monthTotal = monthScoped.length;
    const monthDone = monthScoped.filter((row) => ATTENDED_STATUSES.has(row.status)).length;
    const monthMissed = monthScoped.filter((row) => {
      const isPast = row.dateTime < now;
      const isNotDone = !ATTENDED_STATUSES.has(row.status);
      return isPast && isNotDone;
    }).length;

    const monthAttendanceRate = monthTotal > 0 ? Math.round((monthDone / monthTotal) * 100) : 0;
    const monthMissedRate = monthTotal > 0 ? Math.round((monthMissed / monthTotal) * 100) : 0;

    return {
      label: bucket.label,
      total: monthTotal,
      attendanceRate: monthAttendanceRate,
      missedRate: monthMissedRate,
    };
  });

  return {
    totalNonCancelled,
    doneCount,
    missedCount,
    attendanceRate,
    missedRate,
    monthly,
  };
}

function computeEmergencyAnalytics(alerts, logs, rangeStart, rangeEnd, grouping = "monthly") {
  const scoped = alerts.filter((alert) => inRange(parseAlertDate(alert), rangeStart, rangeEnd));
  const responseMap = buildResponseTimeMap(logs);

  let responded = 0;
  let resolved = 0;
  let responseMinutesTotal = 0;
  let responseCount = 0;

  for (const alert of scoped) {
    const status = String(alert.status || "").toLowerCase();
    if (status === "responded" || status === "resolved") responded += 1;
    if (status === "resolved") resolved += 1;

    const created = parseAlertDate(alert);
    const respondedAt = responseMap.get(alert.alertId);
    if (created && respondedAt) {
      const minutes = (respondedAt - created.getTime()) / 60000;
      if (minutes >= 0 && minutes < 24 * 60) {
        responseMinutesTotal += minutes;
        responseCount += 1;
      }
    }
  }

  const buckets = getResolutionBuckets(rangeStart, rangeEnd, grouping);
  const monthly = buckets.map((bucket) => {
    const monthAlerts = scoped.filter((alert) =>
      inRange(parseAlertDate(alert), bucket.start, bucket.end),
    );
    let monthResponded = 0;
    let monthResolved = 0;
    let monthResponseMinutesTotal = 0;
    let monthResponseCount = 0;

    for (const alert of monthAlerts) {
      const status = String(alert.status || "").toLowerCase();
      if (status === "responded" || status === "resolved") monthResponded += 1;
      if (status === "resolved") monthResolved += 1;

      const created = parseAlertDate(alert);
      const respondedAt = responseMap.get(alert.alertId);
      if (created && respondedAt) {
        const minutes = (respondedAt - created.getTime()) / 60000;
        if (minutes >= 0 && minutes < 24 * 60) {
          monthResponseMinutesTotal += minutes;
          monthResponseCount += 1;
        }
      }
    }

    const resolutionRate = monthAlerts.length > 0 ? Math.round((monthResolved / monthAlerts.length) * 100) : 0;
    const avgResponseMin = monthResponseCount > 0 ? Math.round((monthResponseMinutesTotal / monthResponseCount) * 10) / 10 : 0;

    return {
      label: bucket.label,
      alerts: monthAlerts.length,
      responded: monthResponded,
      resolved: monthResolved,
      resolutionRate,
      avgResponseMin,
    };
  });

  const resolutionRate = scoped.length > 0 ? Math.round((resolved / scoped.length) * 100) : 0;

  return {
    totals: {
      alerts: scoped.length,
      responded,
      resolved,
      resolutionRate,
      avgResponseMin:
        responseCount > 0
          ? Math.round((responseMinutesTotal / responseCount) * 10) / 10
          : 0,
    },
    monthly,
  };
}

/** Estimated monthly walking distance (km) from average daily steps. */
function cohortWalkingDistanceKm(patients, metrics, rangeStart, rangeEnd) {
  const avgStepsPerDay = cohortAverageSteps(patients, metrics, rangeStart, rangeEnd);
  const days = enumerateDateKeysBetween(rangeStart, rangeEnd).length || 1;
  const metersPerStep = 0.76;
  const kilometers = (avgStepsPerDay * days * metersPerStep) / 1000;
  return Math.round(kilometers * 10) / 10;
}

function emergencyAlertCount(alerts, rangeStart, rangeEnd) {
  return alerts.filter((alert) => inRange(parseAlertDate(alert), rangeStart, rangeEnd)).length;
}

function formatImprovement(baseline, latest, { suffix = "", invert = false } = {}) {
  if (baseline == null || latest == null) {
    return { baselineText: "—", latestText: "—", changePct: null, positive: null };
  }
  const baselineText = `${baseline}${suffix}`;
  const latestText = `${latest}${suffix}`;
  if (baseline === 0 && latest === 0) {
    return { baselineText, latestText, changePct: 0, positive: true };
  }
  if (baseline === 0) {
    return { baselineText, latestText, changePct: 100, positive: !invert };
  }
  const raw = Math.round(((latest - baseline) / baseline) * 100);
  const positive = invert ? raw <= 0 : raw >= 0;
  return { baselineText, latestText, changePct: raw, positive };
}

function computeHealthOutcomes({
  patients,
  metrics,
  alerts,
  rangeStart,
  rangeEnd,
}) {
  const buckets = monthBuckets(rangeStart, rangeEnd);
  const baselineKey = buckets[0];
  const latestKey = buckets[buckets.length - 1];

  const baselineStart = new Date(`${baselineKey}-01T00:00:00`);
  const baselineEnd = new Date(baselineStart.getFullYear(), baselineStart.getMonth() + 1, 0, 23, 59, 59, 999);
  const latestStart = new Date(`${latestKey}-01T00:00:00`);
  const latestEnd = new Date(latestStart.getFullYear(), latestStart.getMonth() + 1, 0, 23, 59, 59, 999);

  const fallBaseline = alerts.filter(
    (alert) => isFallAlert(alert) && inRange(parseAlertDate(alert), baselineStart, baselineEnd),
  ).length;
  const fallLatest = alerts.filter(
    (alert) => isFallAlert(alert) && inRange(parseAlertDate(alert), latestStart, latestEnd),
  ).length;

  const walkingBaseline = cohortWalkingDistanceKm(
    patients,
    metrics,
    baselineStart,
    baselineEnd,
  );
  const walkingLatest = cohortWalkingDistanceKm(patients, metrics, latestStart, latestEnd);
  const walkingChange = formatImprovement(walkingBaseline, walkingLatest);

  const alertBaseline = emergencyAlertCount(alerts, baselineStart, baselineEnd);
  const alertLatest = emergencyAlertCount(alerts, latestStart, latestEnd);

  const baselineLabel = monthLabelFromKey(baselineKey).toUpperCase();
  const latestLabel = monthLabelFromKey(latestKey).toUpperCase();

  return {
    baselineLabel,
    latestLabel,
    rows: [
      {
        metric: "Fall Incident Count",
        ...formatImprovement(fallBaseline, fallLatest, { invert: true }),
      },
      {
        metric: "Walking Distance",
        baselineText: `${walkingBaseline.toLocaleString("en-US")} km`,
        latestText: `${walkingLatest.toLocaleString("en-US")} km`,
        changePct: walkingChange.changePct,
        positive: walkingChange.positive,
      },
      {
        metric: "Emergency Alert Frequency",
        ...formatImprovement(alertBaseline, alertLatest, { invert: true }),
      },
    ],
  };
}

export function buildReportsAnalytics({
  patients,
  appointments,
  reminders,
  medications,
  metrics,
  logs,
  alerts,
  rangeKey,
  grouping = "monthly",
  staffDocs = [],
}) {
  const { rangeStart, rangeEnd } = resolveReportRange(rangeKey);
  const todayKey = dateKeyClinic();

  const activePatients = patients.filter(
    (patient) => String(patient.accountStatus || "Active").toLowerCase() !== "inactive",
  );

  const userActivity = activePatients.map((patient) => {
    const avgSteps = stepsForUser(
      metrics,
      patient.patientId,
      rangeKey,
      rangeStart,
      rangeEnd,
    );
    const medResult = medicationAdherenceForUser(
      reminders,
      medications,
      logs,
      patient.patientId,
      rangeStart,
      rangeEnd,
      todayKey,
    );
    const apptStats = appointmentStatsForUser(
      appointments,
      patient.patientId,
      rangeStart,
      rangeEnd,
    );

    return {
      patientId: patient.patientId,
      name: patient.name,
      avgSteps,
      medAdherence: medResult.adherence,
      medAdherenceStatus: medResult.status,
      appointmentsAttended: apptStats.attended,
      appointmentsTotal: apptStats.total,
      appointmentRate: apptStats.rate ?? 0,
      lastActive: lastActiveForUser(logs, patient.patientId),
    };
  });

  userActivity.sort((a, b) => a.name.localeCompare(b.name));

  const healthTrend = computeMonthlyTrends({
    patients: activePatients,
    appointments,
    reminders,
    medications,
    metrics,
    logs,
    rangeStart,
    rangeEnd,
    todayKey,
    rangeKey,
  });

  const emergency = computeEmergencyAnalytics(alerts, logs, rangeStart, rangeEnd, grouping);
  const outcomes = computeHealthOutcomes({
    patients: activePatients,
    metrics,
    alerts,
    rangeStart,
    rangeEnd,
  });

  const patientGrowth = computeGrowthData(patients, staffDocs, rangeStart, rangeEnd);
  const appointmentReports = computeAppointmentReports(appointments, rangeStart, rangeEnd, grouping);

  return {
    userActivity,
    healthTrend,
    emergency,
    outcomes,
    patientCount: userActivity.length,
    patientGrowth,
    appointmentReports,
  };
}

export async function fetchReportsData(rangeKey = REPORT_RANGES.ALL, grouping = "monthly") {
  const queries = [
    {
      name: "users",
      required: true,
      run: () => getDocs(collection(db, USERS_COLLECTION)),
    },
    {
      name: "appointments",
      required: true,
      run: () => getDocs(collection(db, APPOINTMENTS_COLLECTION)),
    },
    {
      name: "medicationreminders",
      required: true,
      run: () => getDocs(collection(db, MEDICATION_REMINDERS_COLLECTION)),
    },
    {
      name: "medications",
      required: true,
      run: () => getDocs(collection(db, MEDICATIONS_COLLECTION)),
    },
    {
      name: "activity",
      required: false,
      run: () => getDocs(collection(db, PATIENT_ACTIVITY_COLLECTION)),
    },
    {
      name: "patientdailymetrics",
      required: false,
      run: () => getDocs(collection(db, PATIENT_DAILY_METRICS_COLLECTION)),
    },
    {
      name: "activityLogs",
      required: false,
      run: () =>
        getDocs(
          query(
            collection(db, ACTIVITY_LOGS_COLLECTION),
            orderBy("timestamp", "desc"),
            limit(2000),
          ),
        ),
    },
    {
      name: "emergencyalerts",
      required: true,
      run: () => getDocs(collection(db, EMERGENCY_ALERTS_COLLECTION)),
    },
    {
      name: "healthcarestaff",
      required: true,
      run: () => getDocs(collection(db, "healthcarestaff")),
    },
    {
      name: "caregiver",
      required: false,
      run: () => getDocs(collection(db, "caregiver")),
    },
  ];

  const results = await Promise.all(
    queries.map(async (entry) => {
      try {
        const snap = await entry.run();
        return { ...entry, snap, error: null };
      } catch (error) {
        console.error(`Reports: failed to load ${entry.name}:`, error);
        return { ...entry, snap: null, error };
      }
    }),
  );

  const failedRequired = results.filter((entry) => entry.required && entry.error);
  if (failedRequired.length > 0) {
    const first = failedRequired[0].error;
    const code = first?.code || "";
    if (code === "permission-denied") {
      throw Object.assign(new Error(
        "Could not load report data. Deploy Firestore rules: firebase deploy --only firestore:rules",
      ), { code });
    }
    throw first;
  }

  const byName = Object.fromEntries(results.map((entry) => [entry.name, entry.snap]));

  const patients = byName.users.docs.map(mapUserDoc);
  const appointments = byName.appointments.docs.map(mapAppointmentRow).filter(Boolean);
  const reminders = byName.medicationreminders.docs.map(mapReminderDoc).filter(Boolean);
  const medications = byName.medications.docs.map(mapMedicationDoc).filter(Boolean);
  const activityMetrics = byName.activity
    ? byName.activity.docs.map(mapMetricDoc).filter(Boolean)
    : [];
  const legacyMetrics = byName.patientdailymetrics
    ? byName.patientdailymetrics.docs.map(mapMetricDoc).filter(Boolean)
    : [];
  const metrics = mergeStepMetrics(activityMetrics, legacyMetrics);
  const logs = byName.activityLogs
    ? byName.activityLogs.docs.map(mapActivityLogDoc)
    : [];
  const alerts = byName.emergencyalerts.docs.map(mapEmergencyAlertDoc).filter(Boolean);
  const staffDocs = [
    ...byName.healthcarestaff.docs.map((docSnap) => {
      const data = docSnap.data() || {};
      return {
        uid: docSnap.id,
        role: normalizeStaffRole(data.role),
        createdAt: timestampToDate(data.createdAt) || data.createdAt,
      };
    }),
    ...(byName.caregiver
      ? byName.caregiver.docs.map((docSnap) => {
          const data = docSnap.data() || {};
          return {
            uid: docSnap.id,
            role: "caregiver",
            createdAt: timestampToDate(data.createdAt) || data.createdAt,
          };
        })
      : []),
  ];

  const warnings = results
    .filter((entry) => !entry.required && entry.error)
    .map((entry) => entry.name);

  const report = buildReportsAnalytics({
    patients,
    appointments,
    reminders,
    medications,
    metrics,
    logs,
    alerts,
    rangeKey,
    grouping,
    staffDocs,
  });

  return { ...report, warnings };
}
