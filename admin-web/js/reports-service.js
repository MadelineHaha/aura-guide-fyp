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
import { MEDICATION_REMINDERS_COLLECTION } from "./medications-service.js";
import { mapUserDoc, USERS_COLLECTION } from "./user-patients-service.js";

export const PATIENT_ACTIVITY_COLLECTION = "activity";
/** @deprecated Legacy collection — reports fall back if `activity` is empty. */
export const PATIENT_DAILY_METRICS_COLLECTION = "patientdailymetrics";

export const REPORT_RANGES = {
  TODAY: "today",
  THREE_MONTHS: 3,
  SIX_MONTHS: 6,
  ALL: 0,
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

  const months = Number(rangeKey);
  if (!months || months <= 0) {
    return { rangeStart: null, rangeEnd: end };
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
  return {
    userId,
    status: String(data.status || "").trim(),
    completedDate: String(data.completedDate || "").trim(),
    repeatPattern: String(data.repeatPattern || "Daily").trim(),
    medicationId: String(data.medicationId || "").trim(),
  };
}

function mapAppointmentRow(docSnap) {
  const data = docSnap.data() || {};
  const userId = readUserId(data);
  const dateTime = timestampToDate(data.dateTime || data.scheduledAt);
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

function countDailyRemindersForUser(reminders, userId) {
  return reminders.filter(
    (reminder) =>
      reminder.userId === userId &&
      reminder.repeatPattern.toLowerCase() === "daily",
  ).length;
}

function medicationAdherenceForUser(reminders, logs, userId, rangeStart, rangeEnd, todayKey) {
  const dailyCount = countDailyRemindersForUser(reminders, userId);
  if (dailyCount <= 0) return null;

  const end = rangeEnd || new Date();
  const start = rangeStart || new Date(end.getFullYear(), end.getMonth() - 5, 1);
  const dayCount = daysBetweenInclusive(start, end);
  const expected = dailyCount * dayCount;

  let taken = logs.filter(
    (log) =>
      log.userId === userId &&
      log.action === LOG_ACTIONS.MARK_MEDICATION &&
      inRange(new Date(log.timestampMs), start, end),
  ).length;

  const todayInRange = inRange(new Date(), start, end);
  if (todayInRange) {
    const completedToday = reminders.filter(
      (reminder) =>
        reminder.userId === userId &&
        reminder.status === "Completed" &&
        reminder.completedDate === todayKey,
    ).length;
    taken = Math.max(taken, completedToday);
  }

  if (expected <= 0) return null;
  return Math.min(100, Math.round((taken / expected) * 100));
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

function computeMonthlyTrends({
  patients,
  appointments,
  reminders,
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
        medicationAdherenceForUser(
          reminders,
          logs,
          patient.patientId,
          start,
          end,
          todayKey,
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

function computeEmergencyAnalytics(alerts, logs, rangeStart, rangeEnd) {
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

  const buckets = monthBuckets(rangeStart, rangeEnd);
  const monthly = buckets.map((bucket) => {
    const monthStart = new Date(`${bucket}-01T00:00:00`);
    const monthEnd = new Date(monthStart.getFullYear(), monthStart.getMonth() + 1, 0, 23, 59, 59, 999);
    const monthAlerts = scoped.filter((alert) =>
      inRange(parseAlertDate(alert), monthStart, monthEnd),
    );
    let monthResponded = 0;
    let monthResolved = 0;
    for (const alert of monthAlerts) {
      const status = String(alert.status || "").toLowerCase();
      if (status === "responded" || status === "resolved") monthResponded += 1;
      if (status === "resolved") monthResolved += 1;
    }
    return {
      label: monthLabelFromKey(bucket),
      alerts: monthAlerts.length,
      responded: monthResponded,
      resolved: monthResolved,
    };
  });

  return {
    totals: {
      alerts: scoped.length,
      responded,
      resolved,
      avgResponseMin:
        responseCount > 0
          ? Math.round((responseMinutesTotal / responseCount) * 10) / 10
          : 0,
    },
    monthly,
  };
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
  appointments,
  reminders,
  logs,
  alerts,
  rangeStart,
  rangeEnd,
  todayKey,
}) {
  const buckets = monthBuckets(rangeStart, rangeEnd);
  const baselineKey = buckets[0];
  const latestKey = buckets[buckets.length - 1];

  const baselineStart = new Date(`${baselineKey}-01T00:00:00`);
  const baselineEnd = new Date(baselineStart.getFullYear(), baselineStart.getMonth() + 1, 0, 23, 59, 59, 999);
  const latestStart = new Date(`${latestKey}-01T00:00:00`);
  const latestEnd = new Date(latestStart.getFullYear(), latestStart.getMonth() + 1, 0, 23, 59, 59, 999);

  const readmissionBaseline = patients.filter((patient) => {
    const done = appointments.filter(
      (row) =>
        row.userId === patient.patientId &&
        ATTENDED_STATUSES.has(row.status) &&
        inRange(row.dateTime, baselineStart, baselineEnd),
    ).length;
    return done >= 2;
  }).length;
  const readmissionLatest = patients.filter((patient) => {
    const done = appointments.filter(
      (row) =>
        row.userId === patient.patientId &&
        ATTENDED_STATUSES.has(row.status) &&
        inRange(row.dateTime, latestStart, latestEnd),
    ).length;
    return done >= 2;
  }).length;
  const readmissionBaselinePct =
    patients.length > 0 ? Math.round((readmissionBaseline / patients.length) * 100) : 0;
  const readmissionLatestPct =
    patients.length > 0 ? Math.round((readmissionLatest / patients.length) * 100) : 0;

  const fallBaseline = alerts.filter(
    (alert) => isFallAlert(alert) && inRange(parseAlertDate(alert), baselineStart, baselineEnd),
  ).length;
  const fallLatest = alerts.filter(
    (alert) => isFallAlert(alert) && inRange(parseAlertDate(alert), latestStart, latestEnd),
  ).length;

  const medBaselineValues = patients
    .map((patient) =>
      medicationAdherenceForUser(
        reminders,
        logs,
        patient.patientId,
        baselineStart,
        baselineEnd,
        todayKey,
      ),
    )
    .filter((value) => value != null);
  const medLatestValues = patients
    .map((patient) =>
      medicationAdherenceForUser(
        reminders,
        logs,
        patient.patientId,
        latestStart,
        latestEnd,
        todayKey,
      ),
    )
    .filter((value) => value != null);
  const medBaseline = metricForMonth(medBaselineValues);
  const medLatest = metricForMonth(medLatestValues);

  const apptBaselineValues = patients
    .map((patient) => appointmentStatsForUser(appointments, patient.patientId, baselineStart, baselineEnd).rate)
    .filter((value) => value != null);
  const apptLatestValues = patients
    .map((patient) => appointmentStatsForUser(appointments, patient.patientId, latestStart, latestEnd).rate)
    .filter((value) => value != null);
  const apptBaseline = metricForMonth(apptBaselineValues);
  const apptLatest = metricForMonth(apptLatestValues);

  const emergencyBaseline = computeEmergencyAnalytics(alerts, logs, baselineStart, baselineEnd);
  const emergencyLatest = computeEmergencyAnalytics(alerts, logs, latestStart, latestEnd);

  const safetyBaseline = Math.round((medBaseline + apptBaseline) / 2);
  const safetyLatest = Math.round((medLatest + apptLatest) / 2);

  const baselineLabel = monthLabelFromKey(baselineKey).toUpperCase();
  const latestLabel = monthLabelFromKey(latestKey).toUpperCase();

  return {
    baselineLabel,
    latestLabel,
    rows: [
      {
        metric: "Hospital Readmission Rate",
        ...formatImprovement(readmissionBaselinePct, readmissionLatestPct, { suffix: "%", invert: true }),
      },
      {
        metric: "Patient Fall Incidents",
        ...formatImprovement(fallBaseline, fallLatest, { invert: true }),
      },
      {
        metric: "Medication Safety Score",
        ...formatImprovement(medBaseline, medLatest, { suffix: "%" }),
      },
      {
        metric: "Overall Safety Score",
        ...formatImprovement(safetyBaseline, safetyLatest),
      },
      {
        metric: "Emergency Avg. Response",
        baselineText: `${emergencyBaseline.totals.avgResponseMin || 0}m`,
        latestText: `${emergencyLatest.totals.avgResponseMin || 0}m`,
        changePct:
          emergencyBaseline.totals.avgResponseMin > 0
            ? Math.round(
                ((emergencyLatest.totals.avgResponseMin - emergencyBaseline.totals.avgResponseMin) /
                  emergencyBaseline.totals.avgResponseMin) *
                  100,
              )
            : 0,
        positive: emergencyLatest.totals.avgResponseMin <= emergencyBaseline.totals.avgResponseMin,
      },
      {
        metric: "Appointment Attendance",
        ...formatImprovement(apptBaseline, apptLatest, { suffix: "%" }),
      },
    ],
  };
}

export function buildReportsAnalytics({
  patients,
  appointments,
  reminders,
  metrics,
  logs,
  alerts,
  rangeKey,
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
    const medAdherence = medicationAdherenceForUser(
      reminders,
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
      medAdherence: medAdherence ?? 0,
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
    metrics,
    logs,
    rangeStart,
    rangeEnd,
    todayKey,
    rangeKey,
  });

  const emergency = computeEmergencyAnalytics(alerts, logs, rangeStart, rangeEnd);
  const outcomes = computeHealthOutcomes({
    patients: activePatients,
    appointments,
    reminders,
    metrics,
    logs,
    alerts,
    rangeStart,
    rangeEnd,
    todayKey,
    rangeKey,
  });

  return {
    userActivity,
    healthTrend,
    emergency,
    outcomes,
    patientCount: userActivity.length,
  };
}

export async function fetchReportsData(rangeKey = REPORT_RANGES.ALL) {
  const queries = [
    {
      name: "users",
      required: true,
      run: () => getDocs(collection(db, USERS_COLLECTION)),
    },
    {
      name: "appointments",
      required: true,
      run: () =>
        getDocs(
          query(collection(db, APPOINTMENTS_COLLECTION), orderBy("dateTime", "asc")),
        ),
    },
    {
      name: "medicationreminders",
      required: true,
      run: () => getDocs(collection(db, MEDICATION_REMINDERS_COLLECTION)),
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

  const warnings = results
    .filter((entry) => !entry.required && entry.error)
    .map((entry) => entry.name);

  const report = buildReportsAnalytics({
    patients,
    appointments,
    reminders,
    metrics,
    logs,
    alerts,
    rangeKey,
  });

  return { ...report, warnings };
}
