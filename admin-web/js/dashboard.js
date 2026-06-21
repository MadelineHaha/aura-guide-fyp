import { initStaffAuth } from "./staff-shell.js";
import { formatStaffDisplayName } from "./staff-name-format.js";
import { releaseFirestoreListener } from "./firestore-realtime.js";
import {
  subscribePatients,
} from "./user-patients-service.js";
import {
  subscribeAppointments,
} from "./appointments-service.js";
import {
  ALERT_STATUS_ACTIVE,
  subscribeAllEmergencyAlerts,
} from "./emergency-alerts-service.js";

const greetingEl = document.getElementById("dashboard-greeting");
const totalPatientsEl = document.getElementById("stat-total-patients");
const patientsMetaEl = document.getElementById("stat-patients-meta");
const todayAppointmentsCountEl = document.getElementById("stat-today-appointments");
const appointmentsMetaEl = document.getElementById("stat-appointments-meta");
const emergenciesMetaEl = document.getElementById("stat-emergencies-meta");
const weeklyChartEl = document.getElementById("weekly-activity-chart");
const todayAppointmentsListEl = document.getElementById("today-appointments-list");
const todayAppointmentsEmptyEl = document.getElementById("today-appointments-empty");
const patientStatusDonutEl = document.getElementById("patient-status-donut");
const patientStatusLegendEl = document.getElementById("patient-status-legend");
const attentionListEl = document.getElementById("attention-patients-list");
const attentionEmptyEl = document.getElementById("attention-patients-empty");

const WEEKDAY_LABELS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

const STATUS_COLORS = {
  stable: "#4caf7d",
  monitoring: "#6bc4c4",
  critical: "#f08c9c",
};

let patientsCache = [];
let appointmentsCache = [];
let emergenciesCache = [];

let unsubscribePatients = null;
let unsubscribeAppointments = null;
let unsubscribeEmergencies = null;

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
  const dayPart =
    hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening";
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

function patientsAddedThisWeek(patients) {
  const weekStart = startOfWeekMonday();
  return patients.filter((patient) => {
    if (!patient.createdAt) return false;
    return patient.createdAt >= weekStart;
  }).length;
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

function countWeeklyActivity() {
  const buckets = weeklyBuckets();
  const appointmentCounts = buckets.map(() => 0);
  const emergencyCounts = buckets.map(() => 0);

  for (const appointment of appointmentsCache) {
    if (!appointment.dateTime || appointment.status === "cancelled") continue;
    buckets.forEach((bucket, index) => {
      if (
        appointment.dateTime >= bucket.dayStart &&
        appointment.dateTime <= bucket.dayEnd
      ) {
        appointmentCounts[index] += 1;
      }
    });
  }

  for (const alert of emergenciesCache) {
    const alertDate = parseEmergencyDate(alert);
    if (!alertDate) continue;
    buckets.forEach((bucket, index) => {
      if (
        alertDate >= bucket.dayStart &&
        alertDate <= bucket.dayEnd
      ) {
        emergencyCounts[index] += 1;
      }
    });
  }

  return { buckets, appointmentCounts, emergencyCounts };
}

function renderWeeklyActivity() {
  if (!weeklyChartEl) return;

  const { buckets, appointmentCounts, emergencyCounts } = countWeeklyActivity();
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
        </div>
      `;
    })
    .join("");
}

function renderPatientStatus() {
  if (!patientStatusDonutEl || !patientStatusLegendEl) return;

  const activePatients = patientsCache.filter(isActivePatient);
  const counts = { stable: 0, monitoring: 0, critical: 0 };

  for (const patient of activePatients) {
    const status = String(patient.status || "stable").toLowerCase();
    if (counts[status] != null) {
      counts[status] += 1;
    } else {
      counts.stable += 1;
    }
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
    segments.length > 0
      ? `conic-gradient(${segments.join(", ")})`
      : "#e9ecef";

  patientStatusLegendEl.innerHTML = ["stable", "monitoring", "critical"]
    .map((key) => {
      const pct = Math.round((counts[key] / total) * 100);
      const swatchClass = `donut-swatch donut-swatch--${key}`;
      return `<li><span class="${swatchClass}"></span>${statusLabel(key)} ${pct}%</li>`;
    })
    .join("");
}

function renderAttentionList() {
  if (!attentionListEl || !attentionEmptyEl) return;

  const attentionPatients = patientsCache
    .filter(
      (patient) =>
        isActivePatient(patient) &&
        (patient.status === "monitoring" || patient.status === "critical"),
    )
    .sort((a, b) => {
      if (a.status === b.status) return a.name.localeCompare(b.name);
      return a.status === "critical" ? -1 : 1;
    })
    .slice(0, 6);

  if (attentionPatients.length === 0) {
    attentionListEl.innerHTML = "";
    attentionEmptyEl.hidden = false;
    return;
  }

  attentionEmptyEl.hidden = true;
  attentionListEl.innerHTML = attentionPatients
    .map(
      (patient) => `
        <li class="attention-item">
          <div class="attention-main">
            <p class="attention-name">${escapeHtml(patient.name)}</p>
            <p class="attention-condition">${escapeHtml(patient.condition)}</p>
          </div>
          <span class="${attentionBadgeClass(patient.status)}">${escapeHtml(statusLabel(patient.status))}</span>
        </li>
      `,
    )
    .join("");
}

function renderTodayAppointmentsList() {
  if (!todayAppointmentsListEl || !todayAppointmentsEmptyEl) return;

  const todays = todayAppointments(appointmentsCache);
  if (todays.length === 0) {
    todayAppointmentsListEl.innerHTML = "";
    todayAppointmentsEmptyEl.hidden = false;
    return;
  }

  todayAppointmentsEmptyEl.hidden = true;
  todayAppointmentsListEl.innerHTML = todays
    .map(
      (appointment) => `
        <li class="appointment-item">
          <div class="appointment-main">
            <p class="appointment-name">${escapeHtml(appointment.patientName)}</p>
            <p class="appointment-detail">${escapeHtml(formatAppointmentTime(appointment.dateTime))} — ${escapeHtml(appointment.appointmentType)}</p>
          </div>
          <span class="appointment-assignee">${escapeHtml(shortStaffName(appointment.staff))}</span>
        </li>
      `,
    )
    .join("");
}

function renderSummaryStats() {
  const activePatients = patientsCache.filter(isActivePatient);
  const addedThisWeek = patientsAddedThisWeek(activePatients);
  const todays = todayAppointments(appointmentsCache);
  const remaining = remainingTodayAppointments(appointmentsCache);
  const activeEmergencies = emergenciesCache.filter(
    (alert) => alert.status === ALERT_STATUS_ACTIVE,
  ).length;

  if (totalPatientsEl) {
    totalPatientsEl.textContent = String(activePatients.length);
  }
  if (patientsMetaEl) {
    patientsMetaEl.textContent =
      addedThisWeek === 0
        ? "No new patients this week"
        : `+${addedThisWeek} this week`;
    patientsMetaEl.classList.toggle("stat-card-meta--positive", addedThisWeek > 0);
  }

  if (todayAppointmentsCountEl) {
    todayAppointmentsCountEl.textContent = String(todays.length);
  }
  if (appointmentsMetaEl) {
    appointmentsMetaEl.textContent =
      remaining === 0
        ? todays.length === 0
          ? "No appointments today"
          : "All completed"
        : `${remaining} remaining`;
  }

  if (emergenciesMetaEl) {
    emergenciesMetaEl.textContent =
      activeEmergencies === 0
        ? "No active alerts"
        : `${activeEmergencies} require response`;
    emergenciesMetaEl.classList.toggle(
      "stat-card-meta--positive",
      activeEmergencies === 0,
    );
  }

  const activeEmergenciesEl = document.getElementById("stat-active-emergencies");
  if (activeEmergenciesEl) {
    activeEmergenciesEl.textContent = String(activeEmergencies);
  }
}

function renderDashboard() {
  renderSummaryStats();
  renderWeeklyActivity();
  renderTodayAppointmentsList();
  renderPatientStatus();
  renderAttentionList();
}

function startDashboardRealtime() {
  releaseFirestoreListener(unsubscribePatients);
  releaseFirestoreListener(unsubscribeAppointments);
  releaseFirestoreListener(unsubscribeEmergencies);

  unsubscribePatients = subscribePatients(
    (patients) => {
      patientsCache = patients;
      renderDashboard();
    },
    (error) => {
      console.error("Dashboard patients listener failed:", error);
      if (patientsMetaEl) patientsMetaEl.textContent = "Could not load patients";
    },
  );

  unsubscribeAppointments = subscribeAppointments(
    (appointments) => {
      appointmentsCache = appointments;
      renderDashboard();
    },
    (error) => {
      console.error("Dashboard appointments listener failed:", error);
      if (appointmentsMetaEl) {
        appointmentsMetaEl.textContent = "Could not load appointments";
      }
    },
  );

  unsubscribeEmergencies = subscribeAllEmergencyAlerts(
    (alerts) => {
      emergenciesCache = alerts;
      renderDashboard();
    },
    (error) => {
      console.error("Dashboard emergencies listener failed:", error);
      if (emergenciesMetaEl) {
        emergenciesMetaEl.textContent = "Could not load emergencies";
      }
    },
  );
}

initStaffAuth((profile) => {
  if (greetingEl) greetingEl.textContent = formatGreeting(profile);
  startDashboardRealtime();
});
