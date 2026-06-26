import { initStaffAuth } from "./staff-shell.js";
import { fetchMedicationsByUserId, fetchMedicationCountsByUserId, createMedicationWithReminder, fetchMedicationAdherence } from "./medications-service.js";
import { subscribePatients } from "./user-patients-service.js";
import { filterPatientsForClinicalPages, isAdmin, isDoctor } from "./staff-rbac.js";
import { todayDateString } from "./appointments-service.js";
import { formatFirestoreError } from "./staff-data-status.js";
import {
  bindPatientAccordionLoader,
  capturePatientAccordionState,
  escapeHtml,
  renderPatientAccordionList,
  refreshPatientAccordionPanel,
  restorePatientAccordionState,
  updatePatientAccordionCounts,
} from "./patient-accordion-ui.js";

const accordionListEl = document.getElementById("medications-accordion-list");
const countEl = document.getElementById("medications-count");
const emptyEl = document.getElementById("medications-empty");

const btnAddMed = document.getElementById("btn-add-medication");
const modalEl = document.getElementById("add-medication-modal");
const closeBtn = document.getElementById("add-medication-close");
const formEl = document.getElementById("add-medication-form");
const patientSelectEl = document.getElementById("add-medication-patient-select");
const nameEl = document.getElementById("add-medication-name");
const dosageEl = document.getElementById("add-medication-dosage");
const frequencyEl = document.getElementById("add-medication-frequency");
const instructionsEl = document.getElementById("add-medication-instructions");
const startEl = document.getElementById("add-medication-start");
const endEl = document.getElementById("add-medication-end");
const reminderTimesLabelEl = document.getElementById("add-medication-reminder-times-label");
const reminderTimesEl = document.getElementById("add-medication-reminder-times");
const errorEl = document.getElementById("add-medication-error");
const submitBtn = formEl?.querySelector('[type="submit"]');

let loggedInUid = null;
let currentAssignedPatients = [];
const medicationCountByPatient = new Map();
let medicationCountPrefetchToken = 0;

function formatMedicationCountLabel(count) {
  return `${count} med${count === 1 ? "" : "s"}`;
}

function applyMedicationCounts(counts, patients) {
  patients.forEach((patient) => {
    medicationCountByPatient.set(patient.patientId, counts.get(patient.patientId) || 0);
  });
  updatePatientAccordionCounts(
    accordionListEl,
    medicationCountByPatient,
    formatMedicationCountLabel,
  );
}

async function prefetchMedicationCounts(patients) {
  const token = ++medicationCountPrefetchToken;
  try {
    const counts = await fetchMedicationCountsByUserId();
    if (token !== medicationCountPrefetchToken) return;
    applyMedicationCounts(counts, patients);
  } catch (error) {
    console.error("Medication count prefetch failed:", error);
  }
}

function formatMedicationPeriod(med) {
  const start = med.startDate || "—";
  const end = med.endDate || "—";
  return `${start} → ${end}`;
}

function getAdherenceHtml(rate) {
  if (typeof rate !== "number" || isNaN(rate)) {
    return `<span class="text-secondary">—</span>`;
  }
  const colorClass = rate < 50 ? "text-danger" : rate < 80 ? "text-warning" : "text-success";
  return `<span class="font-medium ${colorClass}">${Math.round(rate)}%</span>`;
}

function renderMedicationTable(medications) {
  if (!medications.length) {
    return {
      html: `<div class="patient-accordion-empty">No active medications for this patient.</div>`,
      countLabel: "0 meds",
    };
  }

  const rows = medications
    .map(
      (med) => `
        <tr>
          <td>
            <div class="font-medium">${escapeHtml(med.name || "—")}</div>
            <div class="text-sm text-secondary">${escapeHtml(med.instructions || "—")}</div>
          </td>
          <td>${escapeHtml(med.dosage || "—")}</td>
          <td>${escapeHtml(med.frequency || "—")}</td>
          <td>${getAdherenceHtml(med.adherenceRate)}</td>
          <td><span class="text-secondary">${escapeHtml(med.doctor || "—")}</span></td>
          <td><span class="status-badge status-badge--success">${med.active !== false ? "Active" : "Inactive"}</span></td>
        </tr>
      `,
    )
    .join("");

  return {
    html: `
      <table class="data-table">
        <thead>
          <tr>
            <th>Medication</th>
            <th>Dosage</th>
            <th>Frequency</th>
            <th>Adherence</th>
            <th>Prescribed by</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    `,
    countLabel: `${medications.length} med${medications.length === 1 ? "" : "s"}`,
  };
}

function renderPatientList() {
  if (currentAssignedPatients.length === 0) {
    countEl.textContent = "No patients in the system";
    accordionListEl.innerHTML = "";
    emptyEl.hidden = false;
    return;
  }

  const { openPatientIds, loadedPanels } = capturePatientAccordionState(accordionListEl);

  emptyEl.hidden = true;
  countEl.textContent = `${currentAssignedPatients.length} patient${currentAssignedPatients.length === 1 ? "" : "s"} — expand a row to view medications`;

  renderPatientAccordionList({
    containerEl: accordionListEl,
    patients: currentAssignedPatients,
    countSuffix: "medications",
    getCountLabel: (patient) => {
      const cached = medicationCountByPatient.get(patient.patientId);
      return typeof cached === "number" ? formatMedicationCountLabel(cached) : "…";
    },
  });

  restorePatientAccordionState({
    containerEl: accordionListEl,
    openPatientIds,
    loadedPanels,
    onLoadPatient: loadMedicationsForPatient,
    countSuffix: "medications",
  });
}

async function loadMedicationsForPatient(patientId) {
  const medications = await fetchMedicationsByUserId(patientId);
  medicationCountByPatient.set(patientId, medications.length);

  // Fetch adherence rates concurrently
  await Promise.all(
    medications.map(async (med) => {
      const adherence = await fetchMedicationAdherence(med.medicationId || med.id);
      med.adherenceRate = adherence;
    })
  );

  return renderMedicationTable(medications);
}

function reminderCountForFrequency(frequency) {
  switch (frequency) {
    case "Twice daily":
      return 2;
    case "Three times daily":
      return 3;
    default:
      return 1;
  }
}

function defaultReminderTimesForFrequency(frequency) {
  switch (frequency) {
    case "Twice daily":
      return ["08:00", "20:00"];
    case "Three times daily":
      return ["08:00", "14:00", "20:00"];
    case "Weekly":
      return ["09:00"];
    default:
      return ["08:00"];
  }
}

function reminderTimesLabelForFrequency(frequency) {
  const count = reminderCountForFrequency(frequency);
  if (frequency === "Weekly") return "Weekly reminder time";
  if (count === 1) return "Reminder time";
  return `Reminder times (${count} per day)`;
}

function syncAddMedicationReminderTimes() {
  const frequency = frequencyEl.value || "Once daily";
  const count = reminderCountForFrequency(frequency);
  const defaults = defaultReminderTimesForFrequency(frequency);
  const existing = [...reminderTimesEl.querySelectorAll(".complete-med-reminder-time")].map(
    (el) => el.value,
  );

  reminderTimesLabelEl.textContent = reminderTimesLabelForFrequency(frequency);
  reminderTimesEl.innerHTML = "";
  for (let i = 0; i < count; i += 1) {
    const value = existing[i] || defaults[i] || "08:00";
    reminderTimesEl.insertAdjacentHTML(
      "beforeend",
      `
        <label class="complete-med-reminder-time-row">
          <span class="complete-med-reminder-time-label">Time ${i + 1}</span>
          <input
            class="form-field-input complete-med-reminder-time"
            type="time"
            value="${escapeHtml(value)}"
            required
          />
        </label>
      `,
    );
  }
}

function medicationEndMinDate(startValue, today = todayDateString()) {
  if (startValue && startValue > today) return startValue;
  return today;
}

function syncAddMedicationDateConstraints() {
  const today = todayDateString();
  startEl.min = today;
  startEl.setAttribute("min", today);
  if (startEl.value && startEl.value < today) {
    startEl.value = today;
  }

  const endMin = medicationEndMinDate(startEl.value, today);
  endEl.min = endMin;
  endEl.setAttribute("min", endMin);
  if (endEl.value && endEl.value < endMin) {
    endEl.value = endMin;
  }
}

function populatePatientDropdown() {
  if (!patientSelectEl) return;
  patientSelectEl.innerHTML = '<option value="">Choose a patient...</option>';
  currentAssignedPatients.forEach((patient) => {
    const option = document.createElement("option");
    option.value = patient.patientId;
    option.textContent = `${patient.name} (${patient.patientId})`;
    patientSelectEl.appendChild(option);
  });
}

function closeAddMedModal() {
  modalEl.hidden = true;
}

if (btnAddMed) {
  btnAddMed.addEventListener("click", () => {
    formEl.reset();
    errorEl.hidden = true;
    populatePatientDropdown();
    syncAddMedicationDateConstraints();
    syncAddMedicationReminderTimes();
    modalEl.hidden = false;
  });
}

if (closeBtn) closeBtn.addEventListener("click", closeAddMedModal);
if (frequencyEl) frequencyEl.addEventListener("change", syncAddMedicationReminderTimes);
if (startEl) startEl.addEventListener("change", syncAddMedicationDateConstraints);

if (formEl) {
  formEl.addEventListener("submit", async (e) => {
    e.preventDefault();
    errorEl.hidden = true;

    const patientId = patientSelectEl.value;
    if (!patientId) {
      errorEl.textContent = "Please select a patient.";
      errorEl.hidden = false;
      return;
    }

    const reminderTimes = [...reminderTimesEl.querySelectorAll(".complete-med-reminder-time")].map(
      (el) => el.value,
    );

    submitBtn.disabled = true;
    const originalText = submitBtn.innerHTML;
    submitBtn.innerHTML = "Saving...";

    try {
      await createMedicationWithReminder({
        userId: patientId,
        staffId: loggedInUid,
        name: nameEl.value.trim(),
        dosage: dosageEl.value.trim(),
        frequency: frequencyEl.value,
        instructions: instructionsEl.value.trim(),
        startDate: startEl.value,
        endDate: endEl.value,
        reminderDate: startEl.value,
        reminderTimes,
      });

      closeAddMedModal();
      refreshPatientAccordionPanel(accordionListEl, patientId, loadMedicationsForPatient);
      renderPatientList();
      void prefetchMedicationCounts(currentAssignedPatients);
    } catch (err) {
      console.error(err);
      errorEl.textContent = err.message || "Failed to add medication.";
      errorEl.hidden = false;
    } finally {
      submitBtn.disabled = false;
      submitBtn.innerHTML = originalText;
    }
  });
}

bindPatientAccordionLoader({
  containerEl: accordionListEl,
  onLoadPatient: loadMedicationsForPatient,
  countSuffix: "medications",
});

initStaffAuth((profile) => {
  loggedInUid = profile.uid;

  if (btnAddMed && (isDoctor(profile.role) || isAdmin(profile.role))) {
    btnAddMed.hidden = false;
  }

  subscribePatients(
    (allPatients) => {
      currentAssignedPatients = filterPatientsForClinicalPages(allPatients, profile);
      renderPatientList();
      void prefetchMedicationCounts(currentAssignedPatients);
    },
    (error) => {
      console.error("Patient subscription error:", error);
      countEl.textContent = "Error loading patients.";
      accordionListEl.innerHTML = `<div class="patient-accordion-empty text-danger">${escapeHtml(formatFirestoreError(error, "patients"))}</div>`;
    },
  );
});
