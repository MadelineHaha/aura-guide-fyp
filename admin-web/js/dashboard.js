import { initStaffAuth } from "./staff-shell.js";
import { homePageForRole, isAdmin, filterPatientsForClinicalPages } from "./staff-rbac.js";
import { formatStaffDisplayName } from "./staff-name-format.js";
import { releaseFirestoreListener } from "./firestore-realtime.js";
import { subscribePatients } from "./user-patients-service.js";
import { subscribeAppointments } from "./appointments-service.js";
import {
  ALERT_STATUS_ACTIVE,
  subscribeAllEmergencyAlerts,
} from "./emergency-alerts-service.js";
import { subscribeAllStaff } from "./staff-list-service.js";
import { subscribeCaregivers } from "./caregiver-service.js";
import { subscribeActivityLogs } from "./activity-logs-service.js";
import {
  loadMedicationAdherenceRows,
  medAdherenceBadgeHtml,
  parseAdherenceRangeKey,
} from "./medication-adherence-view.js";
import {
  formatFirestoreError,
  showStaffDataBanner,
  clearStaffDataBanner,
} from "./staff-data-status.js";

const greetingEl = document.getElementById("dashboard-greeting");
const adminSectionsEl = document.getElementById("admin-dashboard-sections");
const staffStatCardsEl = document.getElementById("staff-stat-cards");
const staffGridEl = document.getElementById("staff-dashboard-grid");

const isAdminDashboardPage = Boolean(adminSectionsEl);
const isStaffDashboardPage = Boolean(staffGridEl);

const WEEKDAY_LABELS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const STATUS_COLORS = {
  stable: "#4caf7d",
  monitoring: "#6bc4c4",
  critical: "#f08c9c",
};

const APPOINTMENT_STATUS_COLORS = {
  completed: "#4caf7d",
  upcoming: "#2d6a6a",
  missed: "#f08c9c",
  cancelled: "#adb5bd",
  pending: "#f0ad4e",
};

let activityLogsCache = [];

let patientsCache = [];
let allPatientsCache = [];
let appointmentsCache = [];
let emergenciesCache = [];
let staffCache = [];
let caregiversCache = [];

let loggedInRole = "";
let loggedInUid = "";
let loggedInStaffID = "";
let isAdminUser = false;

let unsubscribePatients = null;
let unsubscribeAppointments = null;
let unsubscribeEmergencies = null;
let unsubscribeStaff = null;
let unsubscribeCaregivers = null;
let unsubscribeActivityLogs = null;

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function formatGreeting(profile) {
  const now = new Date();
  const hour = now.getHours();
  const dayPart = hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening";
  const dateStr = now.toLocaleDateString("en-GB", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
  });
  const who = formatStaffDisplayName(profile) || profile.name || "Staff";
  return `${dateStr} — Good ${dayPart}, ${who}`;
}

function startOfWeekMonday(date = new Date()) {
  const d = new Date(date);
  const day = d.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  d.setHours(0, 0, 0, 0);
  d.setDate(d.getDate() + diff);
  return d;
}

function isSameCalendarDay(a, b) {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

function isActivePatient(patient) {
  return String(patient.accountStatus || "Active").toLowerCase() !== "inactive";
}

function formatTodayLabel(date = new Date()) {
  return date.toLocaleDateString("en-GB", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
  });
}

function patientsRegisteredToday(patients) {
  const today = new Date();
  return patients.filter(
    (patient) => patient.createdAt && isSameCalendarDay(patient.createdAt, today),
  ).length;
}

function appointmentsScheduledToday(appointments) {
  const today = new Date();
  return appointments.filter(
    (appointment) => appointment.dateTime && isSameCalendarDay(appointment.dateTime, today),
  );
}

function emergenciesTodayCount(alerts) {
  const today = new Date();
  return alerts.filter((alert) => {
    const alertDate = parseEmergencyDate(alert);
    return alertDate && isSameCalendarDay(alertDate, today);
  }).length;
}

function updateAdminTodayLabels() {
  const label = `Today — ${formatTodayLabel()}`;
  const activityMetaEl = document.getElementById("dashboard-activity-meta");
  const apptMetaEl = document.getElementById("dashboard-appt-stats-meta");
  if (activityMetaEl) activityMetaEl.textContent = label;
  if (apptMetaEl) apptMetaEl.textContent = label;
}

function formatAppointmentTime(date) {
  if (!date) return "—";
  return date.toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });
}

function shortStaffName(staffLabel) {
  const value = String(staffLabel || "—").trim();
  return value.replace(/^Dr\.\s*/i, "").split(/\s+/)[0] || value;
}

function statusLabel(status) {
  const value = String(status || "stable");
  return value.charAt(0).toUpperCase() + value.slice(1);
}

function attentionBadgeClass(status) {
  return status === "critical" ? "badge badge--critical" : "badge badge--monitoring";
}

function todayAppointments(appointments) {
  const today = new Date();
  return appointments
    .filter((appointment) => {
      if (!appointment.dateTime) return false;
      if (appointment.status === "cancelled") return false;
      return isSameCalendarDay(appointment.dateTime, today);
    })
    .sort((a, b) => a.dateTime - b.dateTime);
}

function remainingTodayAppointments(appointments) {
  const now = new Date();
  return todayAppointments(appointments).filter((appointment) => {
    if (appointment.status === "done") return false;
    return appointment.dateTime >= now;
  }).length;
}

function countStaffByRole(role) {
  return staffCache.filter(
    (member) =>
      member.status === "Active" &&
      String(member.role || "").trim().toLowerCase() === role,
  ).length;
}

function countActiveCaregivers() {
  return caregiversCache.filter(
    (member) => String(member.status || "").trim() === "Active",
  ).length;
}

function appointmentStatistics(appointments) {
  const now = new Date();
  let completed = 0;
  let cancelled = 0;
  let missed = 0;
  let upcoming = 0;

  for (const appointment of appointments) {
    const status = String(appointment.status || "").toLowerCase();
    if (status === "done") {
      completed += 1;
      continue;
    }
    if (status === "cancelled") {
      cancelled += 1;
      continue;
    }
    if (status === "missed") {
      missed += 1;
      continue;
    }
    if (!appointment.dateTime) continue;
    if (appointment.dateTime < now) {
      missed += 1;
    } else {
      upcoming += 1;
    }
  }

  return {
    total: appointments.length,
    completed,
    cancelled,
    missed,
    upcoming,
  };
}

function renderTodayAppointmentsList(listEl, emptyEl, appointments) {
  if (!listEl || !emptyEl) return;
  const todays = todayAppointments(appointments);
  if (todays.length === 0) {
    listEl.innerHTML = "";
    emptyEl.hidden = false;
    return;
  }
  emptyEl.hidden = true;
  listEl.innerHTML = todays
    .map(
      (appointment) => {
        const isTherapist = loggedInRole.toLowerCase() === "therapist";
        const detail1 = isTherapist ? (appointment.sessionName || appointment.appointmentType || "Therapy Session") : appointment.appointmentType;
        const detail2 = isTherapist ? (appointment.sessionDuration ? appointment.sessionDuration + " mins" : "Pending") : appointment.location;
        
        return `
        <li class="appointment-item" style="display:flex; align-items:center; gap:16px; padding:12px; border-bottom:1px solid var(--border-color);">
          <div class="appointment-time" style="font-size:1.1rem; font-weight:700; color:var(--primary-color); min-width:85px;">
            ${escapeHtml(formatAppointmentTime(appointment.dateTime))}
          </div>
          <div class="appointment-main" style="flex:1;">
            <p class="appointment-name" style="margin:0; font-weight:600;">${escapeHtml(appointment.patientName)} <span style="font-size:0.85em;color:var(--gray-500);font-weight:normal;">(${escapeHtml(appointment.patientId)})</span></p>
            <p class="appointment-detail" style="margin:4px 0 0; color:var(--gray-600); font-size:0.875rem;">${escapeHtml(detail1)}</p>
          </div>
          <span class="appointment-assignee" style="background:var(--background-color); padding:4px 8px; border-radius:4px; font-size:0.875rem;">${escapeHtml(detail2)}</span>
          <span class="${appointmentStatusBadgeClass(appointment.status)}">${escapeHtml(formatAppointmentStatusLabel(appointment.status))}</span>
        </li>
      `;
      }
    )
    .join("");
}

function formatAppointmentStatusLabel(status) {
  const value = String(status || "scheduled").toLowerCase();
  if (value === "done") return "Done";
  if (value === "missed") return "Missed";
  if (value === "cancelled") return "Cancelled";
  if (value === "pending") return "Pending";
  if (value === "rescheduled") return "Rescheduled";
  return "Scheduled";
}

function appointmentStatusBadgeClass(status) {
  const value = String(status || "scheduled").toLowerCase();
  if (value === "done") return "appt-badge appt-badge--done";
  if (value === "missed") return "appt-badge appt-badge--missed";
  if (value === "cancelled") return "appt-badge appt-badge--cancelled";
  if (value === "pending") return "appt-badge appt-badge--pending";
  if (value === "rescheduled") return "appt-badge appt-badge--rescheduled";
  return "appt-badge appt-badge--scheduled";
}

function renderAdminTodayAppointmentsList() {
  const listEl = document.getElementById("admin-today-appointments-list");
  const emptyEl = document.getElementById("admin-today-appointments-empty");
  if (!listEl || !emptyEl) return;

  const todays = todayAppointments(appointmentsCache);
  if (todays.length === 0) {
    listEl.innerHTML = "";
    emptyEl.hidden = false;
    return;
  }

  emptyEl.hidden = true;
  listEl.innerHTML = todays
    .map(
      (appointment) => `
        <li class="appointment-item admin-appointment-item">
          <div class="appointment-time-block">
            <span class="appointment-time">${escapeHtml(formatAppointmentTime(appointment.dateTime))}</span>
          </div>
          <div class="appointment-main">
            <p class="appointment-name">${escapeHtml(appointment.patientName)} <span class="appointment-id">(${escapeHtml(appointment.patientId)})</span></p>
            <p class="appointment-detail">${escapeHtml(appointment.appointmentType)} · ${escapeHtml(appointment.location || "—")}</p>
            <p class="appointment-detail">Staff: ${escapeHtml(appointment.staff)}</p>
          </div>
          <span class="${appointmentStatusBadgeClass(appointment.status)}">${escapeHtml(formatAppointmentStatusLabel(appointment.status))}</span>
        </li>`,
    )
    .join("");
}

function renderAdminAppointmentDonut() {
  const donutEl = document.getElementById("admin-appointment-donut");
  const legendEl = document.getElementById("admin-appointment-legend");
  const miniStatsEl = document.getElementById("admin-appt-mini-stats");
  if (!donutEl || !legendEl) return;

  const todays = appointmentsScheduledToday(appointmentsCache);
  const stats = appointmentStatistics(todays);
  const segments = [
    { key: "completed", count: stats.completed, label: "Completed" },
    { key: "upcoming", count: stats.upcoming, label: "Upcoming" },
    { key: "missed", count: stats.missed, label: "Missed" },
    { key: "cancelled", count: stats.cancelled, label: "Cancelled" },
  ].filter((entry) => entry.count > 0);

  const total = stats.total;
  if (total === 0) {
    donutEl.style.background = "#e9ecef";
    legendEl.innerHTML =
      '<li><span class="donut-swatch" style="background:#e9ecef"></span>No appointments today</li>';
    if (miniStatsEl) miniStatsEl.innerHTML = "";
    return;
  }

  let angle = 0;
  const gradientParts = [];
  for (const entry of segments) {
    const sweep = (entry.count / total) * 360;
    gradientParts.push(`${APPOINTMENT_STATUS_COLORS[entry.key]} ${angle}deg ${angle + sweep}deg`);
    angle += sweep;
  }
  donutEl.style.background = `conic-gradient(${gradientParts.join(", ")})`;

  legendEl.innerHTML = segments
    .map((entry) => {
      const pct = Math.round((entry.count / total) * 100);
      return `<li><span class="donut-swatch" style="background:${APPOINTMENT_STATUS_COLORS[entry.key]}"></span>${entry.label} · ${entry.count} (${pct}%)</li>`;
    })
    .join("");

  if (miniStatsEl) {
    miniStatsEl.innerHTML = segments
      .map(
        (entry) => `
        <div class="admin-appt-mini-stat admin-appt-mini-stat--${entry.key}">
          <span class="admin-appt-mini-stat-value">${entry.count}</span>
          <span class="admin-appt-mini-stat-label">${entry.label}</span>
        </div>`,
      )
      .join("");
  }
}

function renderAdminActivityFeed() {
  const feedEl = document.getElementById("admin-activity-feed");
  const emptyEl = document.getElementById("admin-activity-empty");
  if (!feedEl || !emptyEl) return;

  const recent = activityLogsCache.slice(0, 10);
  if (recent.length === 0) {
    feedEl.innerHTML = "";
    emptyEl.hidden = false;
    return;
  }

  emptyEl.hidden = true;
  feedEl.innerHTML = recent
    .map((log) => {
      const logType = String(log.type || "info").toLowerCase();
      const isWarning = logType === "warning";
      const isSecurity = logType === "security";
      const itemClass = isWarning
        ? "activity-feed-item activity-feed-item--warning"
        : isSecurity
          ? "activity-feed-item activity-feed-item--security"
          : "activity-feed-item";

      const typeBadgeHtml =
        isWarning || isSecurity
          ? `<span class="activity-feed-type-badge activity-feed-type-badge--${logType}" title="${isSecurity ? "Security" : "Warning"}">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
                ${
                  isSecurity
                    ? '<rect x="3" y="11" width="18" height="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>'
                    : '<path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/>'
                }
              </svg>
              ${isSecurity ? "Security" : "Warning"}
            </span>`
          : "";

      const detailsHtml = log.details
        ? `<p class="activity-feed-detail">${escapeHtml(log.details)}</p>`
        : "";

      return `
        <li class="${itemClass}">
          <div class="activity-feed-main">
            <p class="activity-feed-user">
              ${escapeHtml(log.userName || "—")}
              <span class="activity-feed-user-id">(${escapeHtml(log.userId || "—")})</span>
            </p>
            <p class="activity-feed-action">
              ${typeBadgeHtml}
              <span class="activity-feed-action-text">${escapeHtml(log.action)}</span>
            </p>
            ${detailsHtml}
          </div>
          <span class="activity-feed-meta">${escapeHtml(log.timestamp)}</span>
        </li>`;
    })
    .join("");
}

function renderAdminDashboard() {
  const activePatients = patientsCache.filter(isActivePatient);
  const activeEmergencies = emergenciesCache.filter(
    (alert) => alert.status === ALERT_STATUS_ACTIVE,
  ).length;
  const todaysAppointments = appointmentsScheduledToday(appointmentsCache);
  const apptStats = appointmentStatistics(todaysAppointments);
  const newToday = patientsRegisteredToday(activePatients);

  const set = (id, value) => {
    const el = document.getElementById(id);
    if (el) el.textContent = String(value);
  };

  updateAdminTodayLabels();

  set("stat-total-patients", activePatients.length);
  set("stat-total-doctors", countStaffByRole("doctor"));
  set("stat-total-therapists", countStaffByRole("therapist"));
  set("stat-total-caregivers", countActiveCaregivers());
  set("stat-active-emergencies", activeEmergencies);

  const patientsMetaEl = document.getElementById("stat-patients-admin-meta");
  if (patientsMetaEl) {
    patientsMetaEl.textContent =
      newToday === 0 ? "No new registrations today" : `+${newToday} registered today`;
    patientsMetaEl.classList.toggle("stat-card-meta--positive", newToday > 0);
  }

  const emergenciesMetaEl = document.getElementById("stat-emergencies-admin-meta");
  if (emergenciesMetaEl) {
    emergenciesMetaEl.textContent =
      activeEmergencies === 0
        ? "All clear"
        : `${activeEmergencies} need response`;
    emergenciesMetaEl.classList.toggle("stat-card-meta--positive", activeEmergencies === 0);
  }

  set("summary-new-patients", newToday);
  set("summary-missed-appointments", apptStats.missed);
  set("summary-emergency-alerts", emergenciesTodayCount(emergenciesCache));

  renderAdminAppointmentDonut();
  renderAdminTodayAppointmentsList();
  renderAdminActivityFeed();
}

function renderStaffSummaryStats() {
  const activePatients = patientsCache.filter(isActivePatient);
  const addedToday = patientsRegisteredToday(activePatients);
  const todays = todayAppointments(appointmentsCache);
  const remaining = remainingTodayAppointments(appointmentsCache);
  const activeEmergencies = emergenciesCache.filter(
    (alert) => alert.status === ALERT_STATUS_ACTIVE,
  ).length;

  const totalPatientsEl = document.getElementById("stat-staff-total-patients");
  const patientsMetaEl = document.getElementById("stat-patients-meta");
  const todayAppointmentsCountEl = document.getElementById("stat-today-appointments");
  const appointmentsMetaEl = document.getElementById("stat-appointments-meta");
  const emergenciesMetaEl = document.getElementById("stat-emergencies-meta");
  const activeEmergenciesEl = document.getElementById("stat-staff-active-emergencies");

  // Customize titles for Therapist
  if (loggedInRole.toLowerCase() === "therapist") {
    const todayLabelEl = document.querySelector("#staff-stat-cards article:nth-child(2) .stat-card-label");
    if (todayLabelEl) todayLabelEl.textContent = "Today's Therapy Sessions";
    const panelTitleEl = document.querySelector("#panel-today-appointments .panel-title");
    if (panelTitleEl) panelTitleEl.textContent = "Today's Therapy Sessions";
  }

  if (totalPatientsEl) totalPatientsEl.textContent = String(activePatients.length);
  if (patientsMetaEl) {
    patientsMetaEl.textContent =
      addedToday === 0 ? "No new patients today" : `+${addedToday} today`;
    patientsMetaEl.classList.toggle("stat-card-meta--positive", addedToday > 0);
  }
  if (todayAppointmentsCountEl) todayAppointmentsCountEl.textContent = String(todays.length);
  if (appointmentsMetaEl) {
    appointmentsMetaEl.textContent =
      remaining === 0
        ? todays.length === 0
          ? "No appointments today"
          : "All completed"
        : `${remaining} remaining`;
  }
  if (activeEmergenciesEl) activeEmergenciesEl.textContent = String(activeEmergencies);
  if (emergenciesMetaEl) {
    emergenciesMetaEl.textContent =
      activeEmergencies === 0
        ? "No active alerts"
        : `${activeEmergencies} require response`;
    emergenciesMetaEl.classList.toggle("stat-card-meta--positive", activeEmergencies === 0);
  }
}

function parseEmergencyDate(alert) {
  const label = String(alert.dateTimeLabel || alert.dateTime || "").trim();
  const match = label.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (!match) return null;
  const [, y, m, d] = match;
  return new Date(Number(y), Number(m) - 1, Number(d));
}

function weeklyBuckets() {
  const weekStart = startOfWeekMonday();
  return WEEKDAY_LABELS.map((label, index) => {
    const dayStart = new Date(weekStart);
    dayStart.setDate(weekStart.getDate() + index);
    const dayEnd = new Date(dayStart);
    dayEnd.setHours(23, 59, 59, 999);
    return { label, dayStart, dayEnd };
  });
}

function renderWeeklyActivity() {
  const weeklyChartEl = document.getElementById("weekly-activity-chart");
  if (!weeklyChartEl) return;
  const buckets = weeklyBuckets();
  const appointmentCounts = buckets.map(() => 0);
  const emergencyCounts = buckets.map(() => 0);

  for (const appointment of appointmentsCache) {
    if (!appointment.dateTime || appointment.status === "cancelled") continue;
    buckets.forEach((bucket, index) => {
      if (appointment.dateTime >= bucket.dayStart && appointment.dateTime <= bucket.dayEnd) {
        appointmentCounts[index] += 1;
      }
    });
  }
  for (const alert of emergenciesCache) {
    const alertDate = parseEmergencyDate(alert);
    if (!alertDate) continue;
    buckets.forEach((bucket, index) => {
      if (alertDate >= bucket.dayStart && alertDate <= bucket.dayEnd) {
        emergencyCounts[index] += 1;
      }
    });
  }

  const maxValue = Math.max(1, ...appointmentCounts, ...emergencyCounts);
  weeklyChartEl.innerHTML = buckets
    .map((bucket, index) => {
      const primary = Math.round((appointmentCounts[index] / maxValue) * 100);
      const secondary = Math.round((emergencyCounts[index] / maxValue) * 100);
      return `
        <div class="bar-chart-col">
          <span class="bar bar--primary" style="--h: ${Math.max(primary, 4)}%"></span>
          <span class="bar bar--secondary" style="--h: ${Math.max(secondary, emergencyCounts[index] ? 4 : 0)}%"></span>
          <span class="bar-chart-day">${bucket.label}</span>
        </div>`;
    })
    .join("");
}

function renderPatientStatus() {
  const patientStatusDonutEl = document.getElementById("patient-status-donut");
  const patientStatusLegendEl = document.getElementById("patient-status-legend");
  if (!patientStatusDonutEl || !patientStatusLegendEl) return;

  const activePatients = patientsCache.filter(isActivePatient);
  const counts = { stable: 0, monitoring: 0, critical: 0 };
  for (const patient of activePatients) {
    const status = String(patient.status || "stable").toLowerCase();
    if (counts[status] != null) counts[status] += 1;
    else counts.stable += 1;
  }

  const total = activePatients.length;
  if (total === 0) {
    patientStatusDonutEl.style.background = "#e9ecef";
    patientStatusLegendEl.innerHTML =
      '<li><span class="donut-swatch donut-swatch--stable"></span>No patients yet</li>';
    return;
  }

  let angle = 0;
  const segments = [];
  for (const key of ["stable", "monitoring", "critical"]) {
    const count = counts[key];
    if (count <= 0) continue;
    const sweep = (count / total) * 360;
    segments.push(`${STATUS_COLORS[key]} ${angle}deg ${angle + sweep}deg`);
    angle += sweep;
  }
  patientStatusDonutEl.style.background =
    segments.length > 0 ? `conic-gradient(${segments.join(", ")})` : "#e9ecef";
  patientStatusLegendEl.innerHTML = ["stable", "monitoring", "critical"]
    .map((key) => {
      const pct = Math.round((counts[key] / total) * 100);
      return `<li><span class="donut-swatch donut-swatch--${key}"></span>${statusLabel(key)} ${pct}%</li>`;
    })
    .join("");
}

let medAdherenceAlertsLoading = false;

function medicationAlertPatients() {
  return filterPatientsForClinicalPages(allPatientsCache, {
    role: loggedInRole,
    uid: loggedInUid,
  }).filter(isActivePatient);
}

async function renderMedicationAdherenceAlerts() {
  const listEl = document.getElementById("medication-alerts-list");
  const emptyEl = document.getElementById("medication-alerts-empty");
  const timeframeEl = document.getElementById("medication-adherence-timeframe");

  if (!listEl || !emptyEl || !timeframeEl) return;
  if (loggedInRole.toLowerCase() !== "doctor") return;
  if (medAdherenceAlertsLoading) return;

  const activePatients = medicationAlertPatients();
  if (activePatients.length === 0) {
    listEl.innerHTML = "";
    emptyEl.hidden = false;
    emptyEl.textContent = "No medication adherence alerts.";
    return;
  }

  medAdherenceAlertsLoading = true;
  listEl.innerHTML = "<p style='padding: 12px; color: var(--gray-600);'>Loading alerts...</p>";
  emptyEl.hidden = true;

  try {
    const rangeKey = parseAdherenceRangeKey(timeframeEl.value);
    const { lowRows } = await loadMedicationAdherenceRows(activePatients, rangeKey);
    const patientById = new Map(activePatients.map((patient) => [patient.patientId, patient]));

    if (lowRows.length === 0) {
      listEl.innerHTML = "";
      emptyEl.hidden = false;
      emptyEl.textContent = "No medication adherence alerts.";
      return;
    }

    emptyEl.hidden = true;
    listEl.innerHTML = lowRows
      .map((row) => {
        const patient = patientById.get(row.patientId) || {};
        const caregiverName = patient.assignedCaregiverName
          ? escapeHtml(patient.assignedCaregiverName)
          : "None";
        const caregiverId = patient.assignedCaregiverId || "none";
        const btnText = caregiverId !== "none" ? "Contact Caregiver" : "Contact Patient";

        return `
        <li class="attention-item med-adherence-row--low" style="display:flex; justify-content:space-between; align-items:center; padding:12px; border-bottom:1px solid var(--border-color);">
          <div>
            <p style="margin:0; font-weight:600;">${escapeHtml(row.name || "Unknown")} <span class="med-adherence-flag">Low adherence</span></p>
            <p style="margin:4px 0 0; font-size:0.875rem; color:var(--gray-600);">${escapeHtml(row.patientId || "—")}</p>
            <p style="margin:6px 0 0; display:flex; align-items:center; gap:8px; flex-wrap:wrap; font-size:0.875rem; color:var(--gray-600);">
              Adherence: ${medAdherenceBadgeHtml(row)} <span>&middot; Caregiver: ${caregiverName}</span>
            </p>
          </div>
          <button type="button" class="btn-secondary btn-sm" data-contact-patient="${escapeHtml(row.patientId)}" data-contact-caregiver="${escapeHtml(caregiverId)}">${btnText}</button>
        </li>`;
      })
      .join("");

    listEl.querySelectorAll("[data-contact-patient]").forEach((button) => {
      button.addEventListener("click", () => {
        window.contactCaregiverOrPatient(
          button.getAttribute("data-contact-patient"),
          button.getAttribute("data-contact-caregiver"),
        );
      });
    });
  } catch (error) {
    console.error("Error generating adherence alerts", error);
    listEl.innerHTML = "";
    emptyEl.hidden = false;
    emptyEl.textContent = "Failed to load alerts.";
  } finally {
    medAdherenceAlertsLoading = false;
  }
}

function renderStaffDashboard() {
  renderStaffSummaryStats();
  renderWeeklyActivity();
  renderTodayAppointmentsList(
    document.getElementById("staff-today-appointments-list"),
    document.getElementById("staff-today-appointments-empty"),
    appointmentsCache,
  );
  renderPatientStatus();
  if (loggedInRole.toLowerCase() === "doctor") {
    void renderMedicationAdherenceAlerts();
  }
}

function renderDashboard() {
  if (isAdminUser) {
    if (isAdminDashboardPage) renderAdminDashboard();
  } else if (isStaffDashboardPage) {
    renderStaffDashboard();
  }
}


const adherenceTimeframeEl = document.getElementById("medication-adherence-timeframe");
if (adherenceTimeframeEl) {
  adherenceTimeframeEl.addEventListener("change", () => {
    void renderMedicationAdherenceAlerts();
  });
}

window.contactCaregiverOrPatient = function(patientId, caregiverId) {
  // Store routing information in sessionStorage so communication page knows to select them
  if (caregiverId && caregiverId !== "none") {
    sessionStorage.setItem("auraOpenCommunicationPatientId", caregiverId);
  } else if (patientId) {
    sessionStorage.setItem("auraOpenCommunicationPatientId", patientId);
  }
  window.location.href = "communication.html";
};

function applyRoleLayout() {
  const titleEl = document.querySelector(".staff-dashboard-title");
  if (titleEl) {
    titleEl.textContent = isAdminUser ? "Admin Dashboard" : "Staff Dashboard";
  }
  
  if (loggedInRole.toLowerCase() === "doctor") {
    if (titleEl) titleEl.textContent = "Doctor Dashboard";
    
    const weeklyChart = document.getElementById("panel-weekly-activity");
    const patientStatus = document.getElementById("panel-patient-status");
    const statCards = document.getElementById("staff-stat-cards");
    
    if (weeklyChart) weeklyChart.hidden = true;
    if (patientStatus) patientStatus.hidden = true;
    if (statCards) statCards.hidden = true;
  } else if (loggedInRole.toLowerCase() === "therapist") {
    if (titleEl) titleEl.textContent = "Therapist Dashboard";

    const weeklyChart = document.getElementById("panel-weekly-activity");
    const patientStatus = document.getElementById("panel-patient-status");
    const medicationAlerts = document.getElementById("panel-medication-alerts");
    
    if (weeklyChart) weeklyChart.hidden = true;
    if (patientStatus) patientStatus.hidden = true;
    if (medicationAlerts) medicationAlerts.hidden = true;

    const statCards = document.querySelectorAll("#staff-stat-cards .stat-card");
    if (statCards.length >= 3) {
      statCards[0].hidden = true; // Total Patients
      statCards[2].hidden = true; // Active Emergencies
    }
  }
  
  const mainContent = document.getElementById("main-dashboard-content");
  if (mainContent) mainContent.hidden = false;
}

function ensureDashboardPageForRole() {
  if (isAdminUser && isStaffDashboardPage) {
    window.location.replace("dashboard.html");
    return false;
  }
  if (!isAdminUser && isAdminDashboardPage) {
    window.location.replace("staff-dashboard.html");
    return false;
  }
  return true;
}

function scopePatients(patients) {
  const lowerRole = loggedInRole.toLowerCase();
  if (lowerRole === "doctor") {
    return patients.filter((p) => p.assignedDoctorId === loggedInUid);
  }
  if (lowerRole === "therapist") {
    return patients.filter((p) => p.assignedTherapistId === loggedInUid);
  }
  return patients;
}

function scopeAppointments(appointments) {
  const lowerRole = loggedInRole.toLowerCase();
  if (lowerRole === "doctor" || lowerRole === "therapist") {
    const assignedIds = new Set(patientsCache.map((p) => p.patientId));
    return appointments.filter((a) => assignedIds.has(a.patientId) || String(a.staffId) === String(loggedInUid) || String(a.staffId) === String(loggedInStaffID));
  }
  return appointments;
}

function handleDashboardDataError(error, context) {
  console.error(`Dashboard ${context} listener failed:`, error);
  showStaffDataBanner(formatFirestoreError(error, context));
}

function startDashboardRealtime() {
  clearStaffDataBanner();
  releaseFirestoreListener(unsubscribePatients);
  releaseFirestoreListener(unsubscribeAppointments);
  releaseFirestoreListener(unsubscribeEmergencies);
  releaseFirestoreListener(unsubscribeStaff);
  releaseFirestoreListener(unsubscribeCaregivers);
  releaseFirestoreListener(unsubscribeActivityLogs);

  unsubscribePatients = subscribePatients(
    (patients) => {
      allPatientsCache = patients;
      patientsCache = scopePatients(patients);
      renderDashboard();
    },
    (error) => handleDashboardDataError(error, "patients"),
  );

  unsubscribeAppointments = subscribeAppointments(
    (appointments) => {
      appointmentsCache = scopeAppointments(appointments);
      renderDashboard();
    },
    (error) => handleDashboardDataError(error, "appointments"),
  );

  unsubscribeEmergencies = subscribeAllEmergencyAlerts(
    (alerts) => {
      const lowerRole = loggedInRole.toLowerCase();
      if (lowerRole === "doctor" || lowerRole === "therapist") {
        const assignedIds = new Set(patientsCache.map((p) => p.patientId));
        emergenciesCache = alerts.filter((a) => assignedIds.has(a.userId));
      } else {
        emergenciesCache = alerts;
      }
      renderDashboard();
    },
    (error) => handleDashboardDataError(error, "emergency alerts"),
  );

  if (isAdminUser) {
    unsubscribeStaff = subscribeAllStaff(
      (staff) => {
        staffCache = staff;
        renderDashboard();
      },
      (error) => handleDashboardDataError(error, "staff"),
    );
    unsubscribeCaregivers = subscribeCaregivers(
      (caregivers) => {
        caregiversCache = caregivers;
        renderDashboard();
      },
      (error) => handleDashboardDataError(error, "caregivers"),
    );
    unsubscribeActivityLogs = subscribeActivityLogs(
      (logs) => {
        activityLogsCache = logs;
        renderDashboard();
      },
      (error) => handleDashboardDataError(error, "activity logs"),
    );
  }
}

initStaffAuth((profile) => {
  if (greetingEl) greetingEl.textContent = formatGreeting(profile);
  loggedInRole = profile.role || "";
  loggedInUid = profile.uid || "";
  loggedInStaffID = profile.staffID || "";
  isAdminUser = isAdmin(profile.role);
  applyRoleLayout();
  if (!ensureDashboardPageForRole()) return;
  startDashboardRealtime();
});
