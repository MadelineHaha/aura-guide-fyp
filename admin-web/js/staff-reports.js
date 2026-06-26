import { initStaffAuth } from "./staff-shell.js";
import { subscribeAppointments, normalizeStatus } from "./appointments-service.js";
import { subscribePatients } from "./user-patients-service.js";
import { filterPatientsForClinicalPages } from "./staff-rbac.js";
import {
  isActivePatient,
  isLowMedicationAdherence,
  loadMedicationAdherenceRows,
  medAdherenceBadgeHtml,
  medAdherenceLabelForExport,
  parseAdherenceRangeKey,
} from "./medication-adherence-view.js";
import { escapeHtml } from "./patient-accordion-ui.js";
import { formatFirestoreError } from "./staff-data-status.js";

const appointmentsWeekEl = document.getElementById("appointments-week");
const appointmentsMonthEl = document.getElementById("appointments-month");
const averageDailyEl = document.getElementById("average-daily");
const peakDayEl = document.getElementById("peak-day");
const lastUpdatedEl = document.getElementById("reports-last-updated");

const lowAdherenceCountEl = document.getElementById("low-adherence-count");
const medicationPatientCountEl = document.getElementById("medication-patient-count");
const lowAdherenceTbodyEl = document.getElementById("low-adherence-tbody");
const lowAdherenceEmptyEl = document.getElementById("low-adherence-empty");
const lowAdherenceTableEl = document.getElementById("low-adherence-table");
const medAdherenceLastUpdatedEl = document.getElementById("med-adherence-last-updated");
const medAdherenceTimeframeEl = document.getElementById("med-adherence-timeframe");
const exportCsvBtn = document.getElementById("btn-export-csv");
const exportPdfBtn = document.getElementById("btn-export-pdf");
const reportsPrintMetaEl = document.getElementById("reports-print-meta");

let unsubscribeAppointments = null;
let unsubscribePatients = null;
let scopedPatients = [];
let staffProfile = null;
let medAdherenceLoading = false;
let latestMedicationRows = [];

const DAY_NAMES = [
  "Sunday",
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
];

function startOfWeekMonday(date) {
  const start = new Date(date);
  const day = start.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  start.setDate(start.getDate() + diff);
  start.setHours(0, 0, 0, 0);
  return start;
}

function staffIdsForProfile(profile) {
  const ids = new Set();
  const staffId = String(profile?.staffID || profile?.staffId || "").trim();
  const uid = String(profile?.uid || "").trim();
  if (staffId) ids.add(staffId);
  if (uid) ids.add(uid);
  return ids;
}

function belongsToStaff(appointment, staffIds) {
  const appointmentStaffId = String(appointment?.staffId || appointment?.staffID || "").trim();
  return staffIds.has(appointmentStaffId);
}

function isCountableAppointment(appointment) {
  return normalizeStatus(appointment?.status) !== "cancelled";
}

function filterStaffAppointments(appointments, profile) {
  const staffIds = staffIdsForProfile(profile);
  return appointments.filter(
    (appointment) => belongsToStaff(appointment, staffIds) && isCountableAppointment(appointment),
  );
}

function scopePatientsForStaff(patients, profile) {
  return filterPatientsForClinicalPages(patients, profile).filter(isActivePatient);
}

function medicationTimeframeLabel() {
  const value = medAdherenceTimeframeEl?.value || "month";
  if (value === "today") return "Today";
  if (value === "month") return "This Month";
  return "All Time";
}

function csvCell(value) {
  const text = String(value ?? "");
  if (/[",\n]/.test(text)) {
    return `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

function updatePrintHeader() {
  if (!reportsPrintMetaEl) return;
  const generated = new Date().toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
  const doctorName = staffProfile?.name ? ` · ${staffProfile.name}` : "";
  reportsPrintMetaEl.textContent =
    `Generated ${generated}${doctorName} · Medication period: ${medicationTimeframeLabel()}`;
}

function exportCsv() {
  const patientById = new Map(scopedPatients.map((patient) => [patient.patientId, patient]));
  const generated = new Date().toISOString().slice(0, 10);
  let csvContent = "";

  csvContent += "SECTION 1: APPOINTMENT PERFORMANCE METRICS\n";
  csvContent += "Metric,Value\n";
  csvContent += `Appointments This Week,${csvCell(appointmentsWeekEl?.textContent || "—")}\n`;
  csvContent += `Appointments This Month,${csvCell(appointmentsMonthEl?.textContent || "—")}\n`;
  csvContent += `Average Daily Consultations,${csvCell(averageDailyEl?.textContent || "—")}\n`;
  csvContent += `Peak Consultation Day,${csvCell(peakDayEl?.textContent || "—")}\n`;
  csvContent += `Last Computed,${csvCell(lastUpdatedEl?.textContent || "—")}\n`;
  csvContent += "\n";

  csvContent += "SECTION 2: MEDICATION ADHERENCE REPORT\n";
  csvContent += "Metric,Value\n";
  csvContent += `Period,${csvCell(medicationTimeframeLabel())}\n`;
  csvContent += `On Active Medication,${csvCell(medicationPatientCountEl?.textContent || "0")}\n`;
  csvContent += `Low Adherence (< 100%),${csvCell(lowAdherenceCountEl?.textContent || "0")}\n`;
  csvContent += `Last Computed,${csvCell(medAdherenceLastUpdatedEl?.textContent || "—")}\n`;
  csvContent += "\n";

  const lowAdherenceRows = latestMedicationRows.filter((row) => isLowMedicationAdherence(row));
  csvContent += "PATIENTS WITH LOW MEDICATION ADHERENCE (< 100%)\n";
  csvContent += "Patient ID,Patient Name,Caregiver,Adherence\n";

  lowAdherenceRows.forEach((row) => {
    const patient = patientById.get(row.patientId) || {};
    const caregiverName = patient.assignedCaregiverName || "None";
    csvContent += [
      csvCell(row.patientId),
      csvCell(row.name),
      csvCell(caregiverName),
      csvCell(medAdherenceLabelForExport(row)),
    ].join(",") + "\n";
  });

  const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `aura-guide-doctor-reports-${generated}.csv`;
  link.click();
  URL.revokeObjectURL(url);
}

function exportPdf() {
  updatePrintHeader();
  document.body.classList.add("reports-print-mode");
  requestAnimationFrame(() => {
    window.print();
  });
}

function patientInitials(name) {
  const parts = String(name || "")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
}

function calculateMetrics(appointments) {
  const now = new Date();
  const startOfWeek = startOfWeekMonday(now);
  const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);

  let thisWeekCount = 0;
  let thisMonthCount = 0;

  const dayCounts = Object.fromEntries(DAY_NAMES.map((name) => [name, 0]));

  appointments.forEach((appointment) => {
    const dateTime = appointment.dateTime;
    if (!(dateTime instanceof Date) || Number.isNaN(dateTime.getTime())) return;

    const inWeek = dateTime >= startOfWeek;
    const inMonth = dateTime >= startOfMonth;

    if (inWeek) thisWeekCount += 1;
    if (inMonth) {
      thisMonthCount += 1;
      dayCounts[DAY_NAMES[dateTime.getDay()]] += 1;
    }
  });

  appointmentsWeekEl.textContent = String(thisWeekCount);
  appointmentsMonthEl.textContent = String(thisMonthCount);

  const daysInMonthSoFar = Math.max(1, now.getDate());
  const avg = (thisMonthCount / daysInMonthSoFar).toFixed(1);
  averageDailyEl.textContent = `${avg} consultations`;

  let peakDayName = "—";
  let max = 0;
  for (const [dayName, count] of Object.entries(dayCounts)) {
    if (count > max) {
      max = count;
      peakDayName = dayName;
    }
  }

  peakDayEl.textContent = max > 0 ? peakDayName : "—";
  lastUpdatedEl.textContent = `Last computed: ${now.toLocaleTimeString()}`;
}

function showReportsError(error) {
  const message = formatFirestoreError(error, "appointments");
  appointmentsWeekEl.textContent = "—";
  appointmentsMonthEl.textContent = "—";
  averageDailyEl.textContent = "—";
  peakDayEl.textContent = "—";
  lastUpdatedEl.textContent = message;
}

function showMedAdherenceError(error) {
  const message = formatFirestoreError(error, "medication adherence");
  if (lowAdherenceCountEl) lowAdherenceCountEl.textContent = "—";
  if (medicationPatientCountEl) medicationPatientCountEl.textContent = "—";
  if (lowAdherenceTbodyEl) lowAdherenceTbodyEl.innerHTML = "";
  if (lowAdherenceTableEl) lowAdherenceTableEl.hidden = true;
  if (lowAdherenceEmptyEl) {
    lowAdherenceEmptyEl.hidden = false;
    lowAdherenceEmptyEl.textContent = message;
  }
  if (medAdherenceLastUpdatedEl) {
    medAdherenceLastUpdatedEl.hidden = false;
    medAdherenceLastUpdatedEl.textContent = message;
  }
}

function renderMedAdherenceRows(rows) {
  if (!lowAdherenceTbodyEl || !lowAdherenceEmptyEl || !lowAdherenceTableEl) return;

  const patientById = new Map(
    scopedPatients.map((patient) => [patient.patientId, patient]),
  );

  if (rows.length === 0) {
    lowAdherenceTbodyEl.innerHTML = "";
    lowAdherenceTableEl.hidden = true;
    lowAdherenceEmptyEl.hidden = false;
    lowAdherenceEmptyEl.textContent = "No patients with active medication for this period.";
    return;
  }

  lowAdherenceTableEl.hidden = false;
  lowAdherenceEmptyEl.hidden = true;
  lowAdherenceTbodyEl.innerHTML = rows
    .map((row) => {
      const patient = patientById.get(row.patientId) || {};
      const caregiverName = patient.assignedCaregiverName || "None";
      const lowAdherence = isLowMedicationAdherence(row);

      return `
        <tr class="${lowAdherence ? "med-adherence-row--low" : ""}">
          <td class="reports-patient-col">
            <div class="reports-patient-cell">
              <span class="reports-patient-avatar" aria-hidden="true">${escapeHtml(patientInitials(row.name))}</span>
              <div class="reports-patient-meta">
                <p class="cell-primary">${escapeHtml(row.name || "Unknown")}</p>
                ${lowAdherence ? '<span class="med-adherence-flag">Low adherence</span>' : ""}
                <p class="cell-secondary">${escapeHtml(row.patientId || "—")}</p>
              </div>
            </div>
          </td>
          <td class="reports-med-adherence-col">${medAdherenceBadgeHtml(row)}</td>
          <td class="reports-caregiver-col">${escapeHtml(caregiverName)}</td>
        </tr>`;
    })
    .join("");
}

async function loadMedicationAdherenceReport() {
  if (
    !lowAdherenceCountEl ||
    !medicationPatientCountEl ||
    !medAdherenceTimeframeEl ||
    medAdherenceLoading
  ) {
    return;
  }

  if (scopedPatients.length === 0) {
    latestMedicationRows = [];
    medicationPatientCountEl.textContent = "0";
    lowAdherenceCountEl.textContent = "0";
    renderMedAdherenceRows([]);
    if (medAdherenceLastUpdatedEl) {
      medAdherenceLastUpdatedEl.hidden = false;
      medAdherenceLastUpdatedEl.textContent = "No active patients available.";
    }
    return;
  }

  medAdherenceLoading = true;
  medicationPatientCountEl.textContent = "…";
  lowAdherenceCountEl.textContent = "…";
  if (lowAdherenceEmptyEl) {
    lowAdherenceEmptyEl.hidden = true;
  }

  try {
    const rangeKey = parseAdherenceRangeKey(medAdherenceTimeframeEl.value);
    const { allRows, lowRows } = await loadMedicationAdherenceRows(scopedPatients, rangeKey);

    latestMedicationRows = allRows;
    medicationPatientCountEl.textContent = String(allRows.length);
    lowAdherenceCountEl.textContent = String(lowRows.length);
    renderMedAdherenceRows(allRows);

    if (medAdherenceLastUpdatedEl) {
      medAdherenceLastUpdatedEl.hidden = false;
      medAdherenceLastUpdatedEl.textContent = `Last computed: ${new Date().toLocaleTimeString()}`;
    }
  } catch (error) {
    console.error("Failed to load medication adherence report", error);
    showMedAdherenceError(error);
  } finally {
    medAdherenceLoading = false;
  }
}

if (medAdherenceTimeframeEl) {
  medAdherenceTimeframeEl.addEventListener("change", () => {
    void loadMedicationAdherenceReport();
  });
}

exportCsvBtn?.addEventListener("click", exportCsv);
exportPdfBtn?.addEventListener("click", exportPdf);

window.addEventListener("beforeprint", () => {
  updatePrintHeader();
  document.body.classList.add("reports-print-mode");
});

window.addEventListener("afterprint", () => {
  document.body.classList.remove("reports-print-mode");
});

initStaffAuth((profile) => {
  staffProfile = profile;
  if (unsubscribeAppointments) {
    unsubscribeAppointments();
    unsubscribeAppointments = null;
  }
  if (unsubscribePatients) {
    unsubscribePatients();
    unsubscribePatients = null;
  }

  unsubscribeAppointments = subscribeAppointments(
    (appointments) => {
      calculateMetrics(filterStaffAppointments(appointments, profile));
    },
    (error) => {
      console.error("Failed to load appointments", error);
      showReportsError(error);
    },
  );

  unsubscribePatients = subscribePatients(
    (patients) => {
      scopedPatients = scopePatientsForStaff(patients, profile);
      void loadMedicationAdherenceReport();
    },
    (error) => {
      console.error("Failed to load patients for reports", error);
      showMedAdherenceError(error);
    },
  );
});
