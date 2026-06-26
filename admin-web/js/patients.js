import { initStaffAuth, getInitials } from "./staff-shell.js";
import { formatFirestoreError } from "./staff-data-status.js";
import {
  filterPatientsForRole,
  isAdmin,
  isDoctor,
  isTherapist,
} from "./staff-rbac.js";
import {
  createHealthRecord,
  createTextHealthRecord,
  fetchHealthRecordById,
  fetchHealthRecordsByUserId,
  getHealthRecordFileUrl,
  isHealthRecordsAccessError,
  subscribeHealthRecordsByUserId,
  INLINE_FILE_MAX_BYTES,
  MAX_FILE_BYTES,
  MAX_FILE_SIZE_MESSAGE,
  PRESET_RECORD_TYPES,
  REHAB_PLAN_RECORD_TYPE,
  THERAPY_SESSION_RECORD_TYPE,
  prepareHealthRecordInput,
  updateHealthRecord,
  validateHealthRecordInput,
} from "./health-records-service.js";
import { fetchEmergencyAlertsByUserId } from "./emergency-alerts-service.js";
import { getStaffSession } from "./staff-auth.js";
import {
  createPatient,
  dateToInputValue,
  deactivatePatient,
  subscribePatients,
  updatePatient,
} from "./user-patients-service.js";
import {
  createMedicationWithReminder,
  defaultMedicationEndDate,
  fetchMedicationWithReminders,
  isMedicationsAccessError,
  reminderCountForFrequency,
  subscribeMedicationsByUserId,
  updateMedicationWithReminder,
  cancelMedication,
  MEDICATION_STATUS_CANCELLED,
} from "./medications-service.js";
import {
  formatVisitDate,
  subscribeLatestDoneVisits,
} from "./appointments-service.js";
import { releaseFirestoreListener } from "./firestore-realtime.js";

const PAGE_SIZE = 6;

const tbodyEl = document.getElementById("patients-tbody");
const emptyEl = document.getElementById("patients-empty");
const countEl = document.getElementById("patients-count");
const paginationEl = document.getElementById("patients-pagination");
const searchEl = document.getElementById("patient-search");
const filterTabs = document.querySelectorAll(".filter-tab");

const healthModalEl = null;
const modalPatientEl = document.getElementById("patient-profile-name"); // Reused from profile modal
const modalListEl = document.getElementById("health-records-list");
const modalEmptyEl = document.getElementById("health-records-empty");
const healthModalCloseBtn = null;

const medicationsModalEl = null;
const medicationsPatientEl = null;
const medicationsListEl = document.getElementById("medications-list");
const medicationsEmptyEl = document.getElementById("medications-empty");
const medicationsCloseBtn = null;
const addMedicationModalEl = document.getElementById("add-medication-modal");
const addMedicationFormEl = document.getElementById("add-medication-form");
const addMedicationPatientEl = document.getElementById("add-medication-patient");
const addMedicationCloseBtn = document.getElementById("add-medication-close");
const addMedicationNameEl = document.getElementById("add-medication-name");
const addMedicationDosageEl = document.getElementById("add-medication-dosage");
const addMedicationFrequencyEl = document.getElementById("add-medication-frequency");
const addMedicationInstructionsEl = document.getElementById("add-medication-instructions");
const addMedicationStartEl = document.getElementById("add-medication-start");
const addMedicationEndEl = document.getElementById("add-medication-end");
const addMedicationReminderTimesLabelEl = document.getElementById(
  "add-medication-reminder-times-label",
);
const addMedicationReminderTimesEl = document.getElementById("add-medication-reminder-times");
const addMedicationErrorEl = document.getElementById("add-medication-error");
const addMedicationSubmitBtn = document.getElementById("add-medication-submit");
const addMedicationSaveLabelEl = document.getElementById("add-medication-save-label");
const addMedicationTitleEl = document.getElementById("add-medication-title");
const addMedicationCancelMedBtn = document.getElementById("add-medication-cancel-med");
const addHealthRecordModalEl = document.getElementById("add-health-record-modal");
const addHealthRecordFormEl = document.getElementById("add-health-record-form");
const addHealthRecordPatientEl = document.getElementById("add-health-record-patient");
const addHealthRecordCloseBtn = document.getElementById("add-health-record-close");
const addHealthRecordTypeEl = document.getElementById("add-health-record-type");
const addHealthRecordTypeOtherFieldEl = document.getElementById(
  "add-health-record-type-other-field",
);
const addHealthRecordTypeOtherEl = document.getElementById("add-health-record-type-other");
const addHealthRecordSummaryEl = document.getElementById("add-health-record-summary");
const addHealthRecordFileEl = document.getElementById("add-health-record-file");
const addHealthRecordFileNameEl = document.getElementById("add-health-record-file-name");
const addHealthRecordErrorEl = document.getElementById("add-health-record-error");
const addHealthRecordSubmitBtn = addHealthRecordFormEl?.querySelector('[type="submit"]');
const addHealthRecordSaveLabelEl = document.getElementById("add-health-record-save-label");
const addHealthRecordTitleEl = document.getElementById("add-health-record-title");
const addHealthRecordUploadHintEl = document.getElementById("add-health-record-upload-hint");

const DEFAULT_UPLOAD_HINT = "Maximum 2 MB. Reports up to 750 KB save faster.";
const EDIT_UPLOAD_HINT_SUFFIX = " Leave empty to keep the current file.";

const addPatientModalEl = document.getElementById("add-patient-modal");
const addPatientFormEl = document.getElementById("add-patient-form");
const addPatientCloseBtn = document.getElementById("add-patient-close");
const addPatientBtn = document.getElementById("btn-add-patient");
const addPatientErrorEl = document.getElementById("add-patient-error");
const addPatientSubmitBtn = addPatientFormEl?.querySelector('[type="submit"]');
const patientPinSuccessModalEl = document.getElementById("patient-pin-success-modal");
const patientPinSuccessUserIdEl = document.getElementById("patient-pin-success-userid");
const patientPinSuccessPinEl = document.getElementById("patient-pin-success-pin");
const patientPinSuccessCloseBtn = document.getElementById("patient-pin-success-close");
const patientPinSuccessDoneBtn = document.getElementById("patient-pin-success-done");

const profileModalEl = document.getElementById("patient-profile-modal");
const profileCloseBtn = document.getElementById("patient-profile-close");
const profileAvatarEl = document.getElementById("patient-profile-avatar");
const profileNameEl = document.getElementById("patient-profile-name");
const profileUserIdEl = document.getElementById("patient-profile-userid");
const profileEmailEl = document.getElementById("patient-profile-email");
const profilePhoneEl = document.getElementById("patient-profile-phone");
const profileAgeEl = document.getElementById("patient-profile-age");
const profileGenderEl = document.getElementById("patient-profile-gender");
const profileAddressEl = document.getElementById("patient-profile-address");
const profileGridEl = document.getElementById("patient-profile-grid");
const profileFooterViewEl = document.getElementById("patient-profile-footer-view");
const profileFooterEditEl = document.getElementById("patient-profile-footer-edit");
const profileUpdateBtn = document.getElementById("patient-profile-update");
const profileSaveBtn = document.getElementById("patient-profile-save");
const profileCancelBtn = document.getElementById("patient-profile-cancel");
const profileErrorEl = document.getElementById("patient-profile-error");
const profileEmailInput = document.getElementById("patient-profile-email-input");
const profilePhoneInput = document.getElementById("patient-profile-phone-input");
const profileAgeLabelEl = document.getElementById("patient-profile-age-label");
const profileBirthdateInput = document.getElementById("patient-profile-birthdate-input");
const profileGenderInput = document.getElementById("patient-profile-gender-input");
const profileAddressInput = document.getElementById("patient-profile-address-input");
const profileSaveLabelEl = document.getElementById("patient-profile-save-label");
const profileDeactivateBtn = document.getElementById("patient-profile-deactivate");
const addHealthRecordBtn = document.getElementById("btn-add-health-record");
const addRehabPlanModalEl = document.getElementById("add-rehab-plan-modal");
const addRehabPlanFormEl = document.getElementById("add-rehab-plan-form");
const addRehabPlanCloseBtn = document.getElementById("add-rehab-plan-close");
const addRehabPlanContentEl = document.getElementById("add-rehab-plan-content");
const addTherapySessionModalEl = document.getElementById("add-therapy-session-modal");
const addTherapySessionFormEl = document.getElementById("add-therapy-session-form");
const addTherapySessionCloseBtn = document.getElementById("add-therapy-session-close");
const addTherapySessionContentEl = document.getElementById("add-therapy-session-content");
const profileViewFields = profileModalEl?.querySelectorAll(".profile-field-view") || [];
const profileEditFields = profileModalEl?.querySelectorAll(".profile-field-edit") || [];

let patients = [];
let isProfileEditing = false;
let isSavingProfile = false;
let isDeactivatingPatient = false;
let statusFilter = "all";
let searchQuery = "";
let currentPage = 1;
let activePatientId = null;
let activeMedicationsPatientId = null;
let isSavingPatient = false;
let isSavingHealthRecord = false;
let isSavingMedication = false;
let editingHealthRecordId = null;
let editingMedicationId = null;
let loggedInStaffName = "Staff";
let loggedInStaffRole = "";
let loggedInStaffUid = "";
let showMedicationsColumn = true;
let showHealthRecordsColumn = true;
let loggedInStaffId = "";
let isSavingTherapistRecord = false;

function statusLabel(status) {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

function patientStatusClass(status) {
  return `patient-status patient-status--${status}`;
}

function normalizedAccountStatus(patient) {
  const value = String(patient?.accountStatus || "Active").trim();
  return value.toLowerCase() === "inactive" ? "Inactive" : "Active";
}

function accountStatusBadgeHtml(patient) {
  const status = normalizedAccountStatus(patient);
  const active = status === "Active";
  const cls = active
    ? "patient-status patient-status--stable"
    : "patient-status patient-status--monitoring";
  return `<span class="${cls}">${status}</span>`;
}

const ADMIN_STATUS_FILTER_TABS = [
  { status: "all", label: "All" },
  { status: "active", label: "Active" },
  { status: "inactive", label: "Inactive" },
];

const CLINICAL_STATUS_FILTER_TABS = [
  { status: "all", label: "All" },
  { status: "stable", label: "Stable" },
  { status: "monitoring", label: "Monitoring" },
  { status: "critical", label: "Critical" },
];

function applyPatientFilterTabs(admin) {
  const tabConfig = admin ? ADMIN_STATUS_FILTER_TABS : CLINICAL_STATUS_FILTER_TABS;
  filterTabs.forEach((tab, index) => {
    const config = tabConfig[index];
    if (!config) {
      tab.hidden = true;
      return;
    }
    tab.hidden = false;
    tab.dataset.status = config.status;
    tab.textContent = config.label;
  });
  const validStatuses = tabConfig.map((entry) => entry.status);
  if (!validStatuses.includes(statusFilter)) {
    setPatientStatusFilter("all");
  }
}

function getPatientById(id) {
  return patients.find((p) => p.id === id);
}

function formatRecordTypeTag(type) {
  return String(type || "")
    .trim()
    .toUpperCase();
}

function formatExistingFileLabel(filePath, fileType) {
  if (!filePath) return "No file on record.";
  const name = String(filePath).split("/").pop() || filePath;
  return `Current file: ${name}${fileType ? ` (${fileType})` : ""}`;
}

function setHealthRecordFormMode(mode) {
  const isEdit = mode === "edit";
  addHealthRecordTitleEl.textContent = isEdit ? "Edit Health Record" : "Add Health Record";
  addHealthRecordSaveLabelEl.textContent = isEdit ? "Save Changes" : "Save Record";
  addHealthRecordFileEl.required = !isEdit;
  addHealthRecordUploadHintEl.textContent = isEdit
    ? DEFAULT_UPLOAD_HINT + EDIT_UPLOAD_HINT_SUFFIX
    : DEFAULT_UPLOAD_HINT;
}

function populateHealthRecordFormFromRecord(record) {
  const type = String(record.recordType || "").trim();
  if (PRESET_RECORD_TYPES.includes(type)) {
    addHealthRecordTypeEl.value = type;
    addHealthRecordTypeOtherEl.value = "";
  } else {
    addHealthRecordTypeEl.value = "Other";
    addHealthRecordTypeOtherEl.value = type;
  }
  syncHealthRecordTypeOtherField();
  addHealthRecordSummaryEl.value = record.title || "";
  addHealthRecordFileEl.value = "";
  addHealthRecordFileNameEl.textContent = formatExistingFileLabel(
    record.filePath,
    record.fileType,
  );
  addHealthRecordFileNameEl.classList.add("has-file");
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/"/g, "&quot;");
}

function renderMedicationCard(medication) {
  const statusTag = medication.active ? "ACTIVE" : "ENDED";
  const statusClass = medication.active
    ? "medication-tag--active"
    : "medication-tag--ended";

  return `
    <article class="health-record-card medication-card" data-medication-id="${escapeHtml(medication.medicationId)}">
      <span class="health-record-tag ${statusClass}">${statusTag}</span>
      <p class="health-record-description">${escapeHtml(medication.name)}</p>
      <p class="medication-meta">${escapeHtml(medication.dosage)} · ${escapeHtml(medication.frequency)}</p>
      <p class="medication-dates">${escapeHtml(medication.startDate)} → ${escapeHtml(medication.endDate)}</p>
      ${
        medication.instructions
          ? `<p class="medication-instructions">${escapeHtml(medication.instructions)}</p>`
          : ""
      }
      <footer class="health-record-footer">
        <span class="health-record-doctor">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
            <circle cx="12" cy="7" r="4" />
          </svg>
          ${escapeHtml(medication.doctor)}
        </span>
        <button type="button" class="btn-record-edit btn-medication-edit" data-medication-id="${escapeHtml(medication.medicationId)}">Edit</button>
      </footer>
    </article>
  `;
}

function renderRecordCard(record) {
  const recordId = record.recordId || "";
  const viewBtn =
    record.hasFile || record.filePath || record.hasInlineFile
      ? `<button type="button" class="btn-record-view" data-record-id="${escapeHtml(recordId)}" data-record-title="${escapeHtml(record.description || record.type || "Medical report")}" data-file-type="${escapeHtml(record.fileType || "")}">View report</button>`
      : "";
  return `
    <article class="health-record-card" data-record-id="${recordId}">
      <span class="health-record-tag">${formatRecordTypeTag(record.type)}</span>
      <p class="health-record-description">${record.description}</p>
      <footer class="health-record-footer">
        <span class="health-record-doctor">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
            <circle cx="12" cy="7" r="4" />
          </svg>
          ${record.doctor}
        </span>
        <div class="health-record-card-actions">
          ${viewBtn}
          <button type="button" class="btn-record-edit" data-record-id="${recordId}">Edit</button>
        </div>
      </footer>
    </article>
  `;
}

let unsubscribeHealthRecords = null;
let unsubscribeMedications = null;

function renderMedicationsList(medications) {
  if (medications.length === 0) {
    medicationsListEl.innerHTML = "";
    medicationsEmptyEl.hidden = false;
    medicationsEmptyEl.textContent = "No medication yet.";
    return;
  }
  medicationsEmptyEl.hidden = true;
  medicationsListEl.innerHTML = medications.map(renderMedicationCard).join("");
}

function stopMedicationsRealtime() {
  releaseFirestoreListener(unsubscribeMedications);
  unsubscribeMedications = null;
}

function startMedicationsRealtime(patientId) {
  stopMedicationsRealtime();
  const patient = getPatientById(patientId);
  if (!patient?.patientId || patient.patientId === "—") {
    medicationsListEl.innerHTML = "";
    medicationsEmptyEl.hidden = false;
    medicationsEmptyEl.textContent = "Patient User ID is missing.";
    return;
  }

  medicationsListEl.innerHTML = "";
  medicationsEmptyEl.hidden = true;

  unsubscribeMedications = subscribeMedicationsByUserId(
    patient.patientId,
    (medications) => {
      renderMedicationsList(medications);
    },
    (error) => {
      medicationsListEl.innerHTML = "";
      medicationsEmptyEl.hidden = false;
      if (isMedicationsAccessError(error)) {
        medicationsEmptyEl.textContent = "No medication yet.";
      } else {
        medicationsEmptyEl.textContent =
          error?.message || "Could not load medications.";
      }
    },
  );
}

async function openMedicationsModal(patientId) {
  openPatientProfileModal(patientId);
  switchClinicalTab("medications");
}

function closeMedicationsModal() {
  // Handled by closing the profile modal
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

function medicationEndMinDate(startValue, today = todayDateString()) {
  if (startValue && startValue > today) return startValue;
  return today;
}

function syncAddMedicationReminderTimes(preserveExisting = true, initialTimes = null) {
  const frequency = addMedicationFrequencyEl.value || "Once daily";
  const count = reminderCountForFrequency(frequency);
  const defaults = defaultReminderTimesForFrequency(frequency);
  const existing = preserveExisting
    ? [...addMedicationReminderTimesEl.querySelectorAll(".complete-med-reminder-time")].map(
        (el) => el.value,
      )
    : initialTimes || defaults;

  addMedicationReminderTimesLabelEl.textContent =
    reminderTimesLabelForFrequency(frequency);

  addMedicationReminderTimesEl.innerHTML = "";
  for (let i = 0; i < count; i += 1) {
    const value = existing[i] || defaults[i] || "08:00";
    addMedicationReminderTimesEl.insertAdjacentHTML(
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

function syncAddMedicationDateConstraints(isEdit = Boolean(editingMedicationId)) {
  const today = todayDateString();

  if (isEdit) {
    addMedicationStartEl.removeAttribute("min");
    const endMin = addMedicationStartEl.value || today;
    addMedicationEndEl.min = endMin;
    addMedicationEndEl.setAttribute("min", endMin);
    if (addMedicationEndEl.value && addMedicationEndEl.value < endMin) {
      addMedicationEndEl.value = endMin;
    }
    return;
  }

  addMedicationStartEl.min = today;
  addMedicationStartEl.setAttribute("min", today);
  if (addMedicationStartEl.value && addMedicationStartEl.value < today) {
    addMedicationStartEl.value = today;
  }

  const endMin = medicationEndMinDate(addMedicationStartEl.value, today);
  addMedicationEndEl.min = endMin;
  addMedicationEndEl.setAttribute("min", endMin);
  if (addMedicationEndEl.value && addMedicationEndEl.value < endMin) {
    addMedicationEndEl.value = endMin;
  }
}

function setMedicationFormFieldsDisabled(disabled) {
  for (const el of addMedicationFormEl.querySelectorAll("input, select, textarea")) {
    el.disabled = disabled;
  }
}

function setMedicationFormMode(mode, { cancelled = false } = {}) {
  const isEdit = mode === "edit";
  addMedicationTitleEl.textContent = isEdit
    ? cancelled
      ? "Medication (Cancelled)"
      : "Edit Medication"
    : "Add Medication";
  addMedicationSaveLabelEl.textContent = isEdit ? "Save Changes" : "Add Medication";
  addMedicationCancelMedBtn.hidden = !isEdit || cancelled;
  addMedicationSubmitBtn.hidden = cancelled;
  setMedicationFormFieldsDisabled(cancelled);
}

function populateMedicationFormFromRecord(medication) {
  const frequency = medication.frequency || "Once daily";
  const reminderTimes =
    medication.reminderTimes?.length > 0
      ? medication.reminderTimes
      : defaultReminderTimesForFrequency(frequency);

  addMedicationNameEl.value = medication.name || "";
  addMedicationDosageEl.value = medication.dosage || "";
  addMedicationFrequencyEl.value = frequency;
  addMedicationInstructionsEl.value = medication.instructions || "";
  addMedicationStartEl.value = medication.startDate || "";
  addMedicationEndEl.value = medication.endDate || "";
  syncAddMedicationDateConstraints(true);
  syncAddMedicationReminderTimes(false, reminderTimes);
}

function resetAddMedicationForm() {
  const today = todayDateString();
  const frequency = "Once daily";
  addMedicationFormEl.reset();
  addMedicationFrequencyEl.value = frequency;
  addMedicationStartEl.value = today;
  addMedicationEndEl.value = defaultMedicationEndDate(today);
  addMedicationErrorEl.hidden = true;
  addMedicationErrorEl.textContent = "";
  syncAddMedicationDateConstraints(false);
  syncAddMedicationReminderTimes(false, defaultReminderTimesForFrequency(frequency));
}

function openAddMedicationModal() {
  if (!activeMedicationsPatientId) return;
  const patient = getPatientById(activeMedicationsPatientId);
  if (!patient) return;

  editingMedicationId = null;
  resetAddMedicationForm();
  setMedicationFormMode("add");
  addMedicationPatientEl.textContent = `Patient: ${patient.name}`;
  addMedicationModalEl.hidden = false;
  syncBodyModalLock();
  addMedicationNameEl.focus();
}

async function openEditMedicationModal(medicationId) {
  if (!activeMedicationsPatientId) return;
  const patient = getPatientById(activeMedicationsPatientId);
  if (!patient) return;

  addMedicationErrorEl.hidden = true;
  addMedicationErrorEl.textContent = "";
  addMedicationPatientEl.textContent = `Patient: ${patient.name}`;

  let medication;
  try {
    medication = await fetchMedicationWithReminders(medicationId);
  } catch (error) {
    window.alert(error?.message || "Could not load medication.");
    return;
  }

  if (!medication) {
    window.alert("Medication not found.");
    return;
  }

  if (medication.userId && medication.userId !== patient.patientId) {
    window.alert("This medication does not belong to the selected patient.");
    return;
  }

  editingMedicationId = medication.medicationId;
  addMedicationFormEl.reset();
  populateMedicationFormFromRecord(medication);
  const cancelled =
    String(medication.status || "").trim() === MEDICATION_STATUS_CANCELLED;
  setMedicationFormMode("edit", { cancelled });
  addMedicationModalEl.hidden = false;
  syncBodyModalLock();
  addMedicationNameEl.focus();
}

function closeAddMedicationModal() {
  editingMedicationId = null;
  setMedicationFormMode("add");
  setMedicationFormFieldsDisabled(false);
  addMedicationSubmitBtn.hidden = false;
  addMedicationCancelMedBtn.hidden = true;
  addMedicationModalEl.hidden = true;
  syncBodyModalLock();
  if (medicationsModalEl && !medicationsModalEl.hidden) {
    medicationsCloseBtn?.focus();
  }
}

async function handleCancelMedicationClick() {
  if (!editingMedicationId || isSavingMedication) return;

  const patient = getPatientById(activeMedicationsPatientId);
  const medicationName = addMedicationNameEl.value.trim() || editingMedicationId;
  const confirmed = window.confirm(
    `Cancel ${medicationName} for ${patient?.name || "this patient"}? ` +
      "The patient will no longer receive reminders for this medication.",
  );
  if (!confirmed) return;

  if (!loggedInStaffId) {
    addMedicationErrorEl.textContent = "Staff ID is missing. Please sign in again.";
    addMedicationErrorEl.hidden = false;
    return;
  }

  isSavingMedication = true;
  addMedicationCancelMedBtn.disabled = true;
  addMedicationSubmitBtn.disabled = true;
  addMedicationErrorEl.hidden = true;

  try {
    await cancelMedication({
      medicationId: editingMedicationId,
      staffId: loggedInStaffId,
    });
    closeAddMedicationModal();
  } catch (error) {
    addMedicationErrorEl.textContent =
      error?.message || "Could not cancel medication. Please try again.";
    addMedicationErrorEl.hidden = false;
  } finally {
    isSavingMedication = false;
    addMedicationCancelMedBtn.disabled = false;
    addMedicationSubmitBtn.disabled = false;
  }
}

async function handleAddMedicationSubmit(event) {
  event.preventDefault();
  if (!activeMedicationsPatientId || isSavingMedication) return;

  const patient = getPatientById(activeMedicationsPatientId);
  if (!patient?.patientId || patient.patientId === "—") {
    addMedicationErrorEl.textContent = "Patient User ID is missing.";
    addMedicationErrorEl.hidden = false;
    return;
  }

  if (!loggedInStaffId) {
    addMedicationErrorEl.textContent = "Staff ID is missing. Please sign in again.";
    addMedicationErrorEl.hidden = false;
    return;
  }

  syncAddMedicationDateConstraints(Boolean(editingMedicationId));
  addMedicationErrorEl.hidden = true;

  const reminderTimes = [
    ...addMedicationReminderTimesEl.querySelectorAll(".complete-med-reminder-time"),
  ].map((el) => el.value.trim());

  const isEdit = Boolean(editingMedicationId);
  const saveLabelDefault = isEdit ? "Save Changes" : "Add Medication";
  const payload = {
    name: addMedicationNameEl.value.trim(),
    dosage: addMedicationDosageEl.value.trim(),
    frequency: addMedicationFrequencyEl.value,
    instructions: addMedicationInstructionsEl.value.trim(),
    startDate: addMedicationStartEl.value,
    endDate: addMedicationEndEl.value,
    reminderDate: addMedicationStartEl.value,
    reminderTimes,
    userId: patient.patientId,
    staffId: loggedInStaffId,
  };

  isSavingMedication = true;
  addMedicationSubmitBtn.disabled = true;
  addMedicationSaveLabelEl.textContent = "Saving…";

  try {
    if (isEdit) {
      await updateMedicationWithReminder({
        medicationId: editingMedicationId,
        ...payload,
      });
    } else {
      await createMedicationWithReminder(payload);
    }
    closeAddMedicationModal();
  } catch (error) {
    addMedicationErrorEl.textContent =
      error?.message ||
      (isEdit
        ? "Could not update medication. Please try again."
        : "Could not add medication. Please try again.");
    addMedicationErrorEl.hidden = false;
  } finally {
    isSavingMedication = false;
    addMedicationSubmitBtn.disabled = false;
    addMedicationSaveLabelEl.textContent = saveLabelDefault;
  }
}

function renderHealthRecordsList(records) {
  if (records.length === 0) {
    modalListEl.innerHTML = "";
    modalEmptyEl.hidden = false;
    modalEmptyEl.textContent = "No health record yet.";
    return;
  }
  modalEmptyEl.hidden = true;
  modalListEl.innerHTML = records.map(renderRecordCard).join("");
}

function stopHealthRecordsRealtime() {
  releaseFirestoreListener(unsubscribeHealthRecords);
  unsubscribeHealthRecords = null;
}

function startHealthRecordsRealtime(patientId) {
  stopHealthRecordsRealtime();
  const patient = getPatientById(patientId);
  if (!patient?.patientId || patient.patientId === "—") {
    modalListEl.innerHTML = "";
    modalEmptyEl.hidden = false;
    modalEmptyEl.textContent = "Patient User ID is missing.";
    return;
  }

  modalListEl.innerHTML = "";
  modalEmptyEl.hidden = true;

  unsubscribeHealthRecords = subscribeHealthRecordsByUserId(
    patient.patientId,
    (records) => {
      renderHealthRecordsList(records);
    },
    (error) => {
      modalListEl.innerHTML = "";
      modalEmptyEl.hidden = false;
      if (isHealthRecordsAccessError(error)) {
        modalEmptyEl.textContent = "No health record yet.";
      } else {
        modalEmptyEl.textContent =
          error?.message || "Could not load health records.";
      }
    },
  );
}

async function openHealthRecordsModal(patientId) {
  openPatientProfileModal(patientId);
  switchClinicalTab("health-records");
}

function syncHealthRecordTypeOtherField() {
  const isOther = addHealthRecordTypeEl.value === "Other";
  addHealthRecordTypeOtherFieldEl.hidden = !isOther;
  addHealthRecordTypeOtherEl.required = isOther;
  if (!isOther) {
    addHealthRecordTypeOtherEl.value = "";
  }
}

function getResolvedHealthRecordType() {
  if (addHealthRecordTypeEl.value === "Other") {
    return addHealthRecordTypeOtherEl.value.trim();
  }
  return addHealthRecordTypeEl.value.trim();
}

function openAddHealthRecordModal() {
  const patient = getPatientById(activePatientId);
  if (!patient) return;

  editingHealthRecordId = null;
  addHealthRecordFormEl.reset();
  syncHealthRecordTypeOtherField();
  setHealthRecordFormMode("add");
  addHealthRecordFileNameEl.textContent = "No file chosen";
  addHealthRecordFileNameEl.classList.remove("has-file");
  addHealthRecordErrorEl.hidden = true;
  addHealthRecordErrorEl.textContent = "";
  addHealthRecordPatientEl.textContent = `Patient: ${patient.name}`;

  addHealthRecordModalEl.hidden = false;
  syncBodyModalLock();
  addHealthRecordTypeEl.focus();
}

async function openEditHealthRecordModal(recordId) {
  const patient = getPatientById(activePatientId);
  if (!patient) return;

  addHealthRecordErrorEl.hidden = true;
  addHealthRecordErrorEl.textContent = "";
  addHealthRecordPatientEl.textContent = `Patient: ${patient.name}`;

  let record;
  try {
    record = await fetchHealthRecordById(recordId);
  } catch (error) {
    window.alert(error?.message || "Could not load health record.");
    return;
  }

  if (!record) {
    window.alert("Health record not found.");
    return;
  }

  if (record.userId && record.userId !== patient.patientId) {
    window.alert("This record does not belong to the selected patient.");
    return;
  }

  editingHealthRecordId = recordId;
  addHealthRecordFormEl.reset();
  populateHealthRecordFormFromRecord(record);
  setHealthRecordFormMode("edit");

  addHealthRecordModalEl.hidden = false;
  syncBodyModalLock();
  addHealthRecordTypeEl.focus();
}

function closeAddHealthRecordModal() {
  editingHealthRecordId = null;
  setHealthRecordFormMode("add");
  addHealthRecordModalEl.hidden = true;
  syncBodyModalLock();
  if (healthModalEl && !healthModalEl.hidden) {
    healthModalCloseBtn?.focus();
  }
}

function syncBodyModalLock() {
  const anyOpen =
    (healthModalEl && !healthModalEl.hidden) ||
    (medicationsModalEl && !medicationsModalEl.hidden) ||
    !addMedicationModalEl.hidden ||
    !addHealthRecordModalEl.hidden ||
    !addPatientModalEl.hidden ||
    !patientPinSuccessModalEl?.hidden ||
    !profileModalEl.hidden;
  document.body.classList.toggle("modal-open", anyOpen);
}

function closeHealthRecordsModal() {
  // Now handled by closing the profile modal
}

async function handleHealthRecordFormSubmit(event) {
  event.preventDefault();
  if (!activePatientId || isSavingHealthRecord) return;

  const patient = getPatientById(activePatientId);
  if (!patient) return;

  const isEdit = Boolean(editingHealthRecordId);
  const saveLabelDefault = isEdit ? "Save Changes" : "Save Record";

  addHealthRecordErrorEl.hidden = true;

  const isOtherRecordType = addHealthRecordTypeEl.value === "Other";
  const prepared = prepareHealthRecordInput({
    recordType: getResolvedHealthRecordType(),
    title: addHealthRecordSummaryEl.value,
    isOtherRecordType,
  });
  if (prepared.error) {
    addHealthRecordErrorEl.textContent = prepared.error;
    addHealthRecordErrorEl.hidden = false;
    if (
      prepared.error.includes("Specify Record Type") ||
      prepared.error.includes("record type")
    ) {
      addHealthRecordTypeOtherEl.focus();
    } else if (prepared.error.includes("Clinical Summary")) {
      addHealthRecordSummaryEl.focus();
    }
    return;
  }

  const { recordType, title } = prepared;
  const file = addHealthRecordFileEl.files[0] || null;
  const staffId =
    loggedInStaffId.trim() || getStaffSession()?.staffID?.trim() || "";
  const userId = patient.patientId;

  const validationError = validateHealthRecordInput({
    recordType,
    title,
    file,
    userId,
    staffId,
    requireFile: !isEdit,
  });
  if (validationError) {
    addHealthRecordErrorEl.textContent = validationError;
    addHealthRecordErrorEl.hidden = false;
    if (validationError.includes("record type")) {
      if (isOtherRecordType) {
        addHealthRecordTypeOtherEl.focus();
      } else {
        addHealthRecordTypeEl.focus();
      }
    } else if (validationError.includes("Clinical Summary")) {
      addHealthRecordSummaryEl.focus();
    } else if (
      validationError.includes("file") ||
      validationError.includes("File") ||
      validationError.includes("2 MB")
    ) {
      addHealthRecordFileEl.focus();
    }
    return;
  }

  isSavingHealthRecord = true;
  addHealthRecordSubmitBtn.disabled = true;
  if (file) {
    addHealthRecordSaveLabelEl.textContent =
      file.size <= INLINE_FILE_MAX_BYTES ? "Saving…" : "Uploading file…";
  } else {
    addHealthRecordSaveLabelEl.textContent = "Saving…";
  }

  const onPhase = (phase) => {
    if (phase === "uploading") {
      addHealthRecordSaveLabelEl.textContent = "Uploading file…";
    } else if (phase === "saving") {
      addHealthRecordSaveLabelEl.textContent = "Saving…";
    }
  };

  try {
    if (isEdit) {
      const recordId = editingHealthRecordId;
      const updated = await updateHealthRecord({
        recordId,
        userId,
        staffId,
        recordType,
        title,
        file,
        staffName: loggedInStaffName,
        staffRole: loggedInStaffRole,
        onPhase,
      });
      const card = modalListEl.querySelector(
        `.health-record-card[data-record-id="${recordId}"]`,
      );
      if (card) {
        card.outerHTML = renderRecordCard(updated);
      }
      closeAddHealthRecordModal();
    } else {
      const newRecord = await createHealthRecord({
        userId,
        staffId,
        recordType,
        title,
        file,
        staffName: loggedInStaffName,
        staffRole: loggedInStaffRole,
        onPhase,
      });
      modalEmptyEl.hidden = true;
      modalListEl.insertAdjacentHTML("afterbegin", renderRecordCard(newRecord));
      closeAddHealthRecordModal();
    }
  } catch (error) {
    const code = error?.code || "";
    if (code === "permission-denied") {
      addHealthRecordErrorEl.textContent =
        "Permission denied. Ensure Firestore rules are deployed (firebase deploy --only firestore:rules) and your staff account is Active with a Staff ID.";
    } else {
      addHealthRecordErrorEl.textContent =
        error?.message ||
        (isEdit
          ? "Could not update health record. Please try again."
          : "Could not save health record. Please try again.");
    }
    addHealthRecordErrorEl.hidden = false;
  } finally {
    isSavingHealthRecord = false;
    addHealthRecordSubmitBtn.disabled = false;
    addHealthRecordSaveLabelEl.textContent = saveLabelDefault;
  }
}

function isProfileFieldEmpty(value) {
  if (value === undefined || value === null) return true;
  const text = String(value).trim();
  return text === "" || text === "—";
}

const PROFILE_UNSET_HTML = `<span class="profile-value-unset" role="status">
  <svg class="profile-value-unset-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
    <path d="M19 9l1.25-2.75L23 5l-2.75-1.25L19 1l-1.25 2.75L15 5l2.75 1.25L19 9zm-7.5.5L9 4 6.5 9.5 1 12l5.5 2.5L9 20l2.5-5.5L17 12l-5.5-2.5zM19 15l-1.25 2.75L15 19l2.75 1.25L19 23l1.25-2.75L23 19l-2.75-1.25L19 15z"/>
  </svg>
  <span class="profile-value-unset-text">Not set yet</span>
</span>`;

function renderProfileFieldValue(el, value) {
  if (isProfileFieldEmpty(value)) {
    el.innerHTML = PROFILE_UNSET_HTML;
    el.classList.add("is-unset");
    return;
  }
  el.classList.remove("is-unset");
  el.textContent = String(value);
}

function isPatientAccountInactive(patient) {
  return (patient?.accountStatus || "").toLowerCase() === "inactive";
}

function setPatientStatusFilter(status) {
  statusFilter = status;
  filterTabs.forEach((tab) => {
    tab.classList.toggle("is-active", tab.dataset.status === status);
  });
  currentPage = 1;
}

function syncProfileDeactivateButton(patient) {
  const inactive = isPatientAccountInactive(patient);
  profileDeactivateBtn.disabled = inactive;
  profileDeactivateBtn.setAttribute(
    "aria-disabled",
    inactive ? "true" : "false",
  );
}

function renderProfileView(patient) {
  renderProfileFieldValue(profileEmailEl, patient.email);
  renderProfileFieldValue(profilePhoneEl, patient.phone);
  renderProfileFieldValue(profileAgeEl, patient.age);
  renderProfileFieldValue(profileGenderEl, patient.gender);
  renderProfileFieldValue(profileAddressEl, patient.address);
  syncProfileDeactivateButton(patient);
}

function fillProfileEditInputs(patient) {
  profileEmailInput.value = patient.email || "";
  profilePhoneInput.value = patient.phone || "";
  profileBirthdateInput.value = patient.birthDate
    ? dateToInputValue(patient.birthDate)
    : "";
  profileBirthdateInput.max = todayDateString();
  if (profileGenderInput) {
    profileGenderInput.value =
      patient.gender && patient.gender !== "—" ? patient.gender : "";
  }
  profileAddressInput.value = patient.address || "";
}

function getProfileFormData() {
  return {
    email: profileEmailInput.value.trim().toLowerCase(),
    phone: profilePhoneInput.value.trim(),
    birthDate: profileBirthdateInput.value,
    address: profileAddressInput.value.trim(),
    gender: profileGenderInput?.value.trim() || "",
  };
}

function getPatientProfileBaseline(patient) {
  return {
    email: (patient.email || "").trim().toLowerCase(),
    phone: (patient.phone || "").trim(),
    birthDate: patient.birthDate ? dateToInputValue(patient.birthDate) : "",
    address: (patient.address || "").trim(),
    gender:
      patient.gender && patient.gender !== "—"
        ? String(patient.gender).trim()
        : "",
  };
}

function getProfileChangedFields(patient) {
  const baseline = getPatientProfileBaseline(patient);
  const current = getProfileFormData();
  const changes = {};

  if (baseline.email !== current.email) changes.email = current.email;
  if (baseline.phone !== current.phone) changes.phone = current.phone;
  if (baseline.birthDate !== current.birthDate) {
    changes.birthDate = current.birthDate;
  }
  if (baseline.address !== current.address) changes.address = current.address;
  if (baseline.gender !== current.gender) changes.gender = current.gender;

  return changes;
}

/** Validates only fields the staff actually changed. */
function validateProfileChanges(changes) {
  if ("email" in changes) {
    if (!changes.email) {
      return "Email cannot be empty.";
    }
    if (!changes.email.includes("@")) {
      return "Please enter a valid email address.";
    }
  }
  if ("birthDate" in changes) {
    if (!changes.birthDate) {
      return "Please select a birthdate.";
    }
    if (isFutureBirthdate(changes.birthDate)) {
      return "Birthdate cannot be in the future.";
    }
  }
  return null;
}

function setProfileEditMode(editing) {
  isProfileEditing = editing;
  profileGridEl.classList.toggle("is-editing", editing);
  profileAgeLabelEl.textContent = editing ? "Birthdate" : "Age";
  profileViewFields.forEach((el) => {
    el.hidden = editing;
  });
  profileEditFields.forEach((el) => {
    el.hidden = !editing;
  });
  profileFooterViewEl.hidden = editing;
  profileFooterEditEl.hidden = !editing;
  profileErrorEl.hidden = true;
}

function openPatientProfileModal(patientId) {
  const patient = getPatientById(patientId);
  if (!patient) return;

  activePatientId = patientId;
  setProfileEditMode(false);
  profileAvatarEl.textContent = getInitials(
    patient.name === "—" ? "?" : patient.name,
  );
  profileNameEl.textContent = patient.name;
  profileUserIdEl.textContent = `User ID: ${patient.patientId}`;
  renderProfileView(patient);
  fillProfileEditInputs(patient);
  if (isTherapist(loggedInStaffRole)) {
    void loadTherapistPatientData(patient);
  }

  profileModalEl.hidden = false;
  syncBodyModalLock();
  profileCloseBtn.focus();

  if (isDoctor(loggedInStaffRole) || isTherapist(loggedInStaffRole)) {
    startHealthRecordsRealtime(patientId);
    startMedicationsRealtime(patientId);
  }
}

function closePatientProfileModal() {
  profileModalEl.hidden = true;
  setProfileEditMode(false);
  syncBodyModalLock();
  activePatientId = null;
  
  stopHealthRecordsRealtime();
  stopMedicationsRealtime();
}

function handleProfileUpdateClick() {
  setProfileEditMode(true);
  profileEmailInput.focus();
}

async function handleProfileSaveClick() {
  const patient = getPatientById(activePatientId);
  if (!patient || isSavingProfile) return;

  profileErrorEl.hidden = true;

  const changes = getProfileChangedFields(patient);
  if (Object.keys(changes).length === 0) {
    setProfileEditMode(false);
    return;
  }

  const validationError = validateProfileChanges(changes);
  if (validationError) {
    profileErrorEl.textContent = validationError;
    profileErrorEl.hidden = false;
    return;
  }

  isSavingProfile = true;
  profileSaveBtn.disabled = true;
  profileSaveLabelEl.textContent = "Saving…";

  try {
    await updatePatient(patient.id, changes);
    const updated = getPatientById(patient.id);
    if (updated) {
      renderProfileView(updated);
      fillProfileEditInputs(updated);
    }
    setProfileEditMode(false);
  } catch (error) {
    profileErrorEl.textContent =
      error?.message || "Could not save profile. Please try again.";
    profileErrorEl.hidden = false;
  } finally {
    isSavingProfile = false;
    profileSaveBtn.disabled = false;
    profileSaveLabelEl.textContent = "Save Changes";
  }
}

function handleProfileCancelEdit() {
  const patient = getPatientById(activePatientId);
  if (patient) {
    fillProfileEditInputs(patient);
    renderProfileView(patient);
  }
  setProfileEditMode(false);
}

async function handleProfileDeactivateClick() {
  const patient = getPatientById(activePatientId);
  if (!patient || isDeactivatingPatient) return;

  if (isPatientAccountInactive(patient)) {
    window.alert("This patient is already inactive.");
    return;
  }

  const confirmed = window.confirm(
    `Deactivate ${patient.name}? Their account status will be set to Inactive.`,
  );
  if (!confirmed) return;

  profileErrorEl.hidden = true;
  isDeactivatingPatient = true;
  profileDeactivateBtn.disabled = true;

  try {
    await deactivatePatient(patient.id);
    closePatientProfileModal();
    setPatientStatusFilter("all");
  } catch (error) {
    profileErrorEl.textContent =
      error?.message || "Could not deactivate patient. Please try again.";
    profileErrorEl.hidden = false;
    syncProfileDeactivateButton(patient);
  } finally {
    isDeactivatingPatient = false;
  }
}

function todayDateString() {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function isFutureBirthdate(dateStr) {
  return dateStr > todayDateString();
}

function closePatientPinSuccessModal() {
  if (!patientPinSuccessModalEl) return;
  patientPinSuccessModalEl.hidden = true;
  syncBodyModalLock();
}

function openPatientPinSuccessModal({ userId, onboardingPin, pin }) {
  const pinValue = String(onboardingPin || pin || "").trim();
  const userIdValue = userId || "—";

  if (!pinValue) {
    window.alert(
      "Patient was created, but the PIN could not be loaded. Deploy the latest Cloud Functions and try again.",
    );
    return;
  }

  if (patientPinSuccessUserIdEl) {
    patientPinSuccessUserIdEl.textContent = userIdValue;
  }
  if (patientPinSuccessPinEl) {
    patientPinSuccessPinEl.textContent = pinValue;
  }

  if (patientPinSuccessModalEl) {
    patientPinSuccessModalEl.hidden = false;
    syncBodyModalLock();
    patientPinSuccessDoneBtn?.focus();
    return;
  }

  window.alert(
    `Patient added successfully.\n\nUser ID: ${userIdValue}\n4-digit PIN: ${pinValue}\n\nShare these with the patient for first-time app setup.`,
  );
}

function openAddPatientModal() {
  if (!addPatientModalEl) return;
  addPatientFormEl?.reset();
  addPatientErrorEl.hidden = true;
  addPatientErrorEl.textContent = "";
  const birthdateInput = document.getElementById("add-patient-birthdate");
  if (birthdateInput) birthdateInput.max = todayDateString();
  addPatientModalEl.hidden = false;
  syncBodyModalLock();
  document.getElementById("add-patient-name")?.focus();
}

function closeAddPatientModal() {
  addPatientModalEl.hidden = true;
  syncBodyModalLock();
}

let unsubscribePatients = null;
let unsubscribeDoneVisits = null;
let patientsBase = [];
let latestDoneVisitByUserId = new Map();
let patientsRealtimeStarted = false;
let patientsLoading = false;
let activePatientsStaffProfile = null;

function switchClinicalTab(tabName) {
  document.querySelectorAll(".clinical-tab").forEach((button) => {
    button.classList.toggle("is-active", button.dataset.tab === tabName);
  });
  const panels = [
    "health-records",
    "medications",
    "appointments",
    "emergencies",
    "rehab",
    "sessions"
  ];
  panels.forEach((panel) => {
    const el = document.getElementById(`clinical-tab-${panel}`);
    if (el) el.hidden = tabName !== panel;
  });
}

function renderRehabPlans(records) {
  const listEl = document.getElementById("rehab-plans-list");
  if (!listEl) return;
  if (!records.length) {
    listEl.innerHTML = `<p class="cell-secondary">No rehabilitation plans yet.</p>`;
    return;
  }
  listEl.innerHTML = records
    .map(
      (record) => `
      <article class="health-record-card">
        <span class="health-record-tag">${escapeHtml(formatRecordTypeTag(record.type))}</span>
        <p class="health-record-description">${escapeHtml(record.description)}</p>
        <footer class="health-record-footer">
          <span class="health-record-doctor">${escapeHtml(record.dateCreated)} · ${escapeHtml(record.doctor)}</span>
        </footer>
      </article>`,
    )
    .join("");
}

function renderTherapySessions(records) {
  const listEl = document.getElementById("therapy-sessions-list");
  if (!listEl) return;
  if (!records.length) {
    listEl.innerHTML = `<p class="cell-secondary">No therapy sessions recorded yet.</p>`;
    return;
  }
  listEl.innerHTML = records
    .map(
      (record) => `
      <article class="health-record-card">
        <span class="health-record-tag">${escapeHtml(formatRecordTypeTag(record.type))}</span>
        <p class="health-record-description">${escapeHtml(record.description)}</p>
        <footer class="health-record-footer">
          <span class="health-record-doctor">${escapeHtml(record.dateCreated)} · ${escapeHtml(record.doctor)}</span>
        </footer>
      </article>`,
    )
    .join("");
}

function renderPatientEmergencyHistory(alerts) {
  const listEl = document.getElementById("patient-emergency-history-list");
  if (!listEl) return;
  if (!alerts.length) {
    listEl.innerHTML = `<p class="cell-secondary">No emergency alerts for this patient.</p>`;
    return;
  }
  listEl.innerHTML = alerts
    .map(
      (alert) => `
      <article class="health-record-card">
        <span class="health-record-tag">${escapeHtml(String(alert.status || "Active"))}</span>
        <p class="health-record-description">${escapeHtml(alert.alertType || "Emergency")} — ${escapeHtml(alert.location || "Location pending")}</p>
        <footer class="health-record-footer">
          <span class="health-record-doctor">${escapeHtml(alert.dateTimeLabel || alert.dateTime || "—")}</span>
        </footer>
      </article>`,
    )
    .join("");
}

// Fetch therapy sessions dynamically
async function loadTherapistPatientData(patient) {
  if (!isTherapist(loggedInStaffRole) || !patient?.patientId) return;
  try {
    const { fetchTherapySessionsByUserId } = await import("./appointments-service.js");
    const sessions = await fetchTherapySessionsByUserId(patient.patientId);

    // Filter rehab plans (scheduled/pending therapy sessions)
    const rehabPlans = sessions.filter(s => s.status === "scheduled" || s.status === "pending").map(s => ({
      type: "Rehab Plan",
      description: s.sessionName || "Unnamed Plan",
      dateCreated: s.datetime || "—",
      doctor: s.staff || "—"
    }));
    
    // Filter completed/done therapy sessions
    const therapySessions = sessions.filter(s => s.status !== "scheduled" && s.status !== "pending").map(s => ({
      type: "Therapy Session",
      description: s.sessionName || s.appointmentType || "Unnamed Session",
      dateCreated: s.datetime || "—",
      doctor: s.staff || "—"
    }));

    renderRehabPlans(rehabPlans);
    renderTherapySessions(therapySessions);
    
    const alerts = await fetchEmergencyAlertsByUserId(patient.patientId);
    renderPatientEmergencyHistory(alerts);
  } catch (error) {
    console.warn("Could not load therapist patient data:", error);
  }
}

function openAddRehabPlanModal() {
  const patient = getPatientById(activePatientId);
  if (!patient) return;
  addRehabPlanContentEl.value = "";
  addRehabPlanModalEl.hidden = false;
  syncBodyModalLock();
  addRehabPlanContentEl.focus();
}

function closeAddRehabPlanModal() {
  addRehabPlanModalEl.hidden = true;
  syncBodyModalLock();
}

function openAddTherapySessionModal() {
  const patient = getPatientById(activePatientId);
  if (!patient) return;
  addTherapySessionContentEl.value = "";
  addTherapySessionModalEl.hidden = false;
  syncBodyModalLock();
  addTherapySessionContentEl.focus();
}

function closeAddTherapySessionModal() {
  addTherapySessionModalEl.hidden = true;
  syncBodyModalLock();
}

async function handleRehabPlanSubmit(event) {
  event.preventDefault();
  if (isSavingTherapistRecord) return;
  const patient = getPatientById(activePatientId);
  const content = addRehabPlanContentEl.value.trim();
  if (!patient || !content) return;
  if (!loggedInStaffId) {
    window.alert("Your staff profile is missing a valid Staff ID.");
    return;
  }

  isSavingTherapistRecord = true;
  try {
    await createTextHealthRecord({
      userId: patient.patientId,
      staffId: loggedInStaffId,
      recordType: REHAB_PLAN_RECORD_TYPE,
      title: content,
    });
    closeAddRehabPlanModal();
    await loadTherapistPatientData(patient);
  } catch (error) {
    window.alert(error?.message || "Could not save rehabilitation plan.");
  } finally {
    isSavingTherapistRecord = false;
  }
}

async function handleTherapySessionSubmit(event) {
  event.preventDefault();
  if (isSavingTherapistRecord) return;
  const patient = getPatientById(activePatientId);
  const content = addTherapySessionContentEl.value.trim();
  if (!patient || !content) return;
  if (!loggedInStaffId) {
    window.alert("Your staff profile is missing a valid Staff ID.");
    return;
  }

  isSavingTherapistRecord = true;
  try {
    await createTextHealthRecord({
      userId: patient.patientId,
      staffId: loggedInStaffId,
      recordType: THERAPY_SESSION_RECORD_TYPE,
      title: content,
    });
    closeAddTherapySessionModal();
    await loadTherapistPatientData(patient);
  } catch (error) {
    window.alert(error?.message || "Could not save therapy session.");
  } finally {
    isSavingTherapistRecord = false;
  }
}

function formatRegistrationDate(date) {
  if (!date) return "—";
  return date.toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

let adminMode = false;
let accountStatusFilterMode = false;
let showGenderContactReg = false;
let showCondition = false;
let showCaregiver = false;
showHealthRecordsColumn = false;
showMedicationsColumn = false;
let showProfileColumn = false;
let showActionsColumn = false;
let showLastVisitColumn = false;

function applyPatientsRoleUi(profile) {
  const admin = isAdmin(profile?.role);
  const doctor = isDoctor(profile?.role);
  const therapist = isTherapist(profile?.role);
  const clinicalListLayout = admin || doctor || therapist;

  adminMode = admin;
  accountStatusFilterMode = clinicalListLayout;

  if (addPatientBtn) addPatientBtn.hidden = !admin;

  if (admin) {
    showGenderContactReg = true;
    showCondition = false;
    showCaregiver = false;
    showLastVisitColumn = false;
    showHealthRecordsColumn = false;
    showMedicationsColumn = false;
    showProfileColumn = false;
    showActionsColumn = true;
  } else if (doctor || therapist) {
    showGenderContactReg = true;
    showCondition = false;
    showCaregiver = true;
    showLastVisitColumn = false;
    showHealthRecordsColumn = false;
    showMedicationsColumn = false;
    showProfileColumn = false;
    showActionsColumn = false;
  } else {
    showGenderContactReg = false;
    showCondition = true;
    showCaregiver = true;
    showLastVisitColumn = true;
    showHealthRecordsColumn = true;
    showMedicationsColumn = true;
    showProfileColumn = true;
    showActionsColumn = false;
  }

  document.querySelectorAll(".patients-col-gender, .patients-col-contact, .patients-col-registered").forEach((el) => {
    el.hidden = !showGenderContactReg;
  });
  document.querySelectorAll(".patients-col-condition").forEach((el) => {
    el.hidden = !showCondition;
  });
  document.querySelectorAll(".patients-col-caregiver").forEach((el) => {
    el.hidden = !showCaregiver;
  });
  document.querySelectorAll(".patients-col-visit").forEach((el) => {
    el.hidden = !showLastVisitColumn;
  });
  document.querySelectorAll(".patients-col-records").forEach((el) => {
    el.hidden = !showHealthRecordsColumn;
  });
  document.querySelectorAll(".patients-col-meds").forEach((el) => {
    el.hidden = !showMedicationsColumn;
  });
  document.querySelectorAll(".patients-col-profile").forEach((el) => {
    el.hidden = !showProfileColumn;
  });
  document.querySelectorAll(".patients-col-actions").forEach((el) => {
    el.hidden = !showActionsColumn;
  });

  applyPatientFilterTabs(clinicalListLayout);

  const therapistSection = document.getElementById("therapist-section");
  if (therapistSection) therapistSection.hidden = !therapist;

  if (profileDeactivateBtn) profileDeactivateBtn.hidden = !admin;
  if (profileUpdateBtn) profileUpdateBtn.hidden = !admin;
  if (addHealthRecordBtn) addHealthRecordBtn.hidden = !(admin || doctor || therapist);

  if (patientsBase.length > 0 || patients.length > 0) {
    renderTable();
  }
}

function setPatientsLoadingState(loading) {
  patientsLoading = loading;
  if (!countEl || !tbodyEl || !emptyEl) return;

  if (loading) {
    countEl.textContent = "Loading patients…";
    emptyEl.hidden = true;
    paginationEl.innerHTML = "";
    tbodyEl.innerHTML = `
      <tr class="patients-loading-row">
        <td colspan="8">Loading patient records…</td>
      </tr>`;
    return;
  }
}

function showPatientsInitError(message) {
  if (countEl) countEl.textContent = "Could not load patients";
  if (tbodyEl) tbodyEl.innerHTML = "";
  if (emptyEl) {
    emptyEl.textContent = message || "Could not initialize the patients page.";
    emptyEl.hidden = false;
  }
}

function initializePatientsPage(profile) {
  if (!profile?.role) return;

  try {
    activePatientsStaffProfile = profile;
    if (profile.name) loggedInStaffName = profile.name;
    if (profile.role) loggedInStaffRole = profile.role;
    if (profile.staffID) loggedInStaffId = profile.staffID;
    if (profile.uid) loggedInStaffUid = profile.uid;

    applyPatientsRoleUi(profile);

    if (!patientsRealtimeStarted) {
      patientsRealtimeStarted = true;
      setPatientsLoadingState(true);
      startPatientsRealtime();
      return;
    }

    if (!patientsLoading) {
      applyPatientsWithLastVisit();
    }
  } catch (error) {
    console.error("Patients page init failed:", error);
    showPatientsInitError(error?.message || "Could not initialize the patients page.");
  }
}

function applyPatientsWithLastVisit() {
  const scoped = filterPatientsForRole(patientsBase, activePatientsStaffProfile || {
    role: loggedInStaffRole,
    uid: loggedInStaffUid,
  });
  patients = scoped.map((patient) => ({
    ...patient,
    lastVisit: latestDoneVisitByUserId.has(patient.patientId)
      ? formatVisitDate(latestDoneVisitByUserId.get(patient.patientId))
      : "—",
  }));
  patientsLoading = false;
  renderTable();
}

function startPatientsRealtime() {
  releaseFirestoreListener(unsubscribePatients);
  releaseFirestoreListener(unsubscribeDoneVisits);

  unsubscribePatients = subscribePatients(
    (list) => {
      patientsBase = list;
      patientsLoading = false;
      applyPatientsWithLastVisit();
    },
    (error) => {
      patientsLoading = false;
      patientsBase = [];
      patients = [];
      countEl.textContent = "Could not load patients";
      tbodyEl.innerHTML = "";
      emptyEl.textContent = formatFirestoreError(error, "patients");
      emptyEl.hidden = false;
    },
  );

  unsubscribeDoneVisits = subscribeLatestDoneVisits(
    (visitMap) => {
      latestDoneVisitByUserId = visitMap;
      applyPatientsWithLastVisit();
    },
    (error) => {
      console.warn("Could not load appointment visits:", error);
      latestDoneVisitByUserId = new Map();
      applyPatientsWithLastVisit();
    },
  );
}

function filterPatients() {
  const q = searchQuery.toLowerCase();
  const usesAdminFilters = accountStatusFilterMode;
  
  return patients.filter((patient) => {
    if (!usesAdminFilters && isPatientAccountInactive(patient)) return false;

    let matchesStatus = true;
    if (statusFilter !== "all") {
      if (usesAdminFilters) {
        const isActive = normalizedAccountStatus(patient) === "Active";
        matchesStatus =
          (statusFilter === "active" && isActive) ||
          (statusFilter === "inactive" && !isActive);
      } else {
        matchesStatus = patient.status === statusFilter;
      }
    }

    const haystack = `${patient.name} ${patient.patientId} ${patient.condition}`.toLowerCase();
    const matchesSearch = !q || haystack.includes(q);
    return matchesStatus && matchesSearch;
  });
}

function renderRow(patient) {
  const ageDisplay = typeof patient.age === "number" ? patient.age : patient.age;

  return `
    <tr data-id="${patient.id}">
      <td class="patients-col-id"><p class="cell-primary">${escapeHtml(patient.patientId)}</p></td>
      <td class="patients-col-name"><p class="cell-primary">${escapeHtml(patient.name)}</p></td>
      <td class="patients-col-age">${ageDisplay}</td>
      ${showGenderContactReg ? `
      <td class="patients-col-gender">${escapeHtml(patient.gender || "—")}</td>
      <td class="patients-col-contact">${escapeHtml(patient.phone || "—")}</td>
      <td class="patients-col-registered">${formatRegistrationDate(patient.createdAt)}</td>
      ` : ""}
      ${showCondition ? `<td class="patients-col-condition">${escapeHtml(patient.condition)}</td>` : ""}
      ${showCaregiver ? `<td class="patients-col-caregiver">${patient.assignedCaregiverName ? escapeHtml(patient.assignedCaregiverName) : '<span style="color:var(--gray-500)">None</span>'}</td>` : ""}
      ${showLastVisitColumn ? `<td class="patients-col-visit">${escapeHtml(patient.lastVisit || "—")}</td>` : ""}
      <td class="patients-col-status">${accountStatusBadgeHtml(patient)}</td>
      ${showHealthRecordsColumn ? `<td class="patients-col-records">
        <button type="button" class="btn-view-records" data-patient-id="${patient.id}" aria-label="View health records for ${patient.name}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7-10-7-10-7z" />
            <circle cx="12" cy="12" r="3" />
          </svg>
          View
        </button>
      </td>` : ""}
      ${showMedicationsColumn ? `<td class="patients-col-meds">
        <button type="button" class="btn-view-records btn-view-medications" data-patient-id="${patient.id}" aria-label="View medications for ${patient.name}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M10.5 20.5l10-10a4.95 4.95 0 1 0-7-7l-10 10a4.95 4.95 0 1 0 7 7z" />
            <line x1="8.5" y1="8.5" x2="15.5" y2="15.5" />
          </svg>
          View
        </button>
      </td>` : ""}
      ${showProfileColumn ? `<td class="table-actions patients-col-profile">
        <button type="button" class="btn-secondary btn-sm btn-view-profile" data-patient-id="${patient.id}">Profile</button>
      </td>` : ""}
      ${showActionsColumn ? `<td class="table-actions patients-col-actions">
        <button type="button" class="btn-secondary btn-sm btn-edit-patient" data-patient-id="${patient.id}">Edit</button>
      </td>` : ""}
    </tr>
  `;
}

function bindTableActions() {
  /* Handled via tbody event delegation */
}

function renderPagination(totalPages) {
  if (totalPages <= 1) {
    paginationEl.innerHTML = "";
    return;
  }

  paginationEl.innerHTML = Array.from({ length: totalPages }, (_, i) => {
    const page = i + 1;
    const active = page === currentPage ? " is-active" : "";
    return `<button type="button" class="page-btn${active}" data-page="${page}">${page}</button>`;
  }).join("");

  paginationEl.querySelectorAll(".page-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      currentPage = Number(btn.dataset.page);
      renderTable();
    });
  });
}

function renderTable() {
  if (!tbodyEl || !countEl || !emptyEl) return;

  const filtered = filterPatients();
  const total = filtered.length;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  if (currentPage > totalPages) currentPage = totalPages;

  const start = (currentPage - 1) * PAGE_SIZE;
  const pageItems = filtered.slice(start, start + PAGE_SIZE);

  if (patientsLoading && patientsBase.length === 0) {
    setPatientsLoadingState(true);
    return;
  }

  countEl.textContent = `${total} patient${total === 1 ? "" : "s"}`;

  if (pageItems.length === 0) {
    tbodyEl.innerHTML = "";
    const hasFilters = Boolean(searchQuery) || statusFilter !== "all";
    emptyEl.textContent = hasFilters
      ? "No patients match your search."
      : patientsBase.length === 0
        ? "No patient records yet."
        : "No patients match the current filter.";
    emptyEl.hidden = false;
    paginationEl.innerHTML = "";
    return;
  }

  emptyEl.hidden = true;
  tbodyEl.innerHTML = pageItems.map(renderRow).join("");
  bindTableActions();
  renderPagination(totalPages);
}

async function handleAddPatientSubmit(event) {
  event.preventDefault();
  if (isSavingPatient) return;

  addPatientErrorEl.hidden = true;

  const name = document.getElementById("add-patient-name").value.trim();
  const birthDate = document.getElementById("add-patient-birthdate").value;
  const gender = document.getElementById("add-patient-gender")?.value.trim() || "";
  const address = document.getElementById("add-patient-address").value.trim();

  if (!name || !birthDate || !address) {
    addPatientErrorEl.textContent = "Please fill in all fields.";
    addPatientErrorEl.hidden = false;
    return;
  }

  if (isFutureBirthdate(birthDate)) {
    addPatientErrorEl.textContent = "Birthdate cannot be in the future.";
    addPatientErrorEl.hidden = false;
    return;
  }

  const birth = new Date(`${birthDate}T00:00:00`);
  if (Number.isNaN(birth.getTime())) {
    addPatientErrorEl.textContent = "Please enter a valid birthdate.";
    addPatientErrorEl.hidden = false;
    return;
  }

  isSavingPatient = true;
  addPatientSubmitBtn.disabled = true;
  addPatientSubmitBtn.textContent = "Saving…";

  try {
    const result = await createPatient({ name, birthDate, address, gender });
    closeAddPatientModal();
    openPatientPinSuccessModal({
      userId: result?.userId,
      onboardingPin: result?.onboardingPin,
      pin: result?.pin,
    });
    currentPage = 1;
  } catch (error) {
    const code = error?.code;
    if (code === "permission-denied") {
      addPatientErrorEl.textContent =
        "Permission denied. Deploy updated Firestore rules and sign in as active staff.";
    } else {
      addPatientErrorEl.textContent =
        error?.message || "Could not save patient. Please try again.";
    }
    addPatientErrorEl.hidden = false;
  } finally {
    isSavingPatient = false;
    addPatientSubmitBtn.disabled = false;
    addPatientSubmitBtn.innerHTML = `
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true">
        <line x1="12" y1="5" x2="12" y2="19" />
        <line x1="5" y1="12" x2="19" y2="12" />
      </svg>
      Add Patient`;
  }
}

searchEl.addEventListener("input", () => {
  searchQuery = searchEl.value.trim();
  currentPage = 1;
  renderTable();
});

filterTabs.forEach((tab) => {
  tab.addEventListener("click", () => {
    setPatientStatusFilter(tab.dataset.status);
    renderTable();
  });
});

function openPatientProfileForEdit(patientId) {
  openPatientProfileModal(patientId);
  handleProfileUpdateClick();
}

tbodyEl.addEventListener("click", (event) => {
  const editBtn = event.target.closest(".btn-edit-patient");
  if (editBtn) {
    openPatientProfileForEdit(editBtn.dataset.patientId);
    return;
  }

  const profileBtn = event.target.closest(".btn-profile-menu");
  if (profileBtn) {
    openPatientProfileModal(profileBtn.dataset.patientId);
    return;
  }

  const medicationsBtn = event.target.closest(".btn-view-medications");
  if (medicationsBtn) {
    openMedicationsModal(medicationsBtn.dataset.patientId);
    return;
  }

  const recordsBtn = event.target.closest(".btn-view-records");
  if (recordsBtn) {
    openHealthRecordsModal(recordsBtn.dataset.patientId);
  }
});

  healthModalCloseBtn?.addEventListener("click", closeHealthRecordsModal);
  medicationsCloseBtn?.addEventListener("click", closeMedicationsModal);
medicationsListEl?.addEventListener("click", (event) => {
  const editBtn = event.target.closest(".btn-medication-edit");
  if (!editBtn?.dataset.medicationId) return;
  openEditMedicationModal(editBtn.dataset.medicationId);
});
  document.getElementById("btn-add-medication")?.addEventListener("click", openAddMedicationModal);
addMedicationCloseBtn?.addEventListener("click", closeAddMedicationModal);
addMedicationCancelMedBtn?.addEventListener("click", handleCancelMedicationClick);
addMedicationFormEl?.addEventListener("submit", handleAddMedicationSubmit);
addMedicationFrequencyEl?.addEventListener("change", () => {
  syncAddMedicationReminderTimes();
});
addMedicationStartEl?.addEventListener("change", () => {
  syncAddMedicationDateConstraints(Boolean(editingMedicationId));
  if (
    addMedicationEndEl.value &&
    addMedicationEndEl.min &&
    addMedicationEndEl.value < addMedicationEndEl.min
  ) {
    addMedicationEndEl.value = addMedicationEndEl.min;
  }
});
addMedicationModalEl?.addEventListener("click", (event) => {
  if (event.target === addMedicationModalEl) closeAddMedicationModal();
});
modalListEl?.addEventListener("click", async (event) => {
  const viewBtn = event.target.closest(".btn-record-view");
  if (viewBtn?.dataset.recordId) {
    try {
      const url = await getHealthRecordFileUrl(viewBtn.dataset.recordId);
      if (!url) {
        throw new Error("No file is attached to this record, or it could not be loaded.");
      }
      window.open(url, "_blank", "noopener,noreferrer");
    } catch (error) {
      console.error(error);
      addHealthRecordErrorEl.textContent =
        error?.message || "Could not open the medical report.";
      addHealthRecordErrorEl.hidden = false;
    }
    return;
  }

  const editBtn = event.target.closest(".btn-record-edit");
  if (!editBtn?.dataset.recordId) return;
  openEditHealthRecordModal(editBtn.dataset.recordId);
});
  document.getElementById("btn-add-health-record")?.addEventListener("click", openAddHealthRecordModal);
addHealthRecordCloseBtn?.addEventListener("click", closeAddHealthRecordModal);
addHealthRecordFormEl?.addEventListener("submit", handleHealthRecordFormSubmit);
addHealthRecordTypeEl?.addEventListener("change", () => {
  syncHealthRecordTypeOtherField();
  if (addHealthRecordTypeEl.value === "Other") {
    addHealthRecordTypeOtherEl.focus();
  }
});

addHealthRecordTypeOtherEl?.addEventListener("input", () => {
  const cleaned = addHealthRecordTypeOtherEl.value.replace(/[^A-Za-z0-9 ]/g, "");
  if (cleaned !== addHealthRecordTypeOtherEl.value) {
    addHealthRecordTypeOtherEl.value = cleaned;
  }
});
addHealthRecordFileEl?.addEventListener("change", () => {
  const file = addHealthRecordFileEl.files[0];
  addHealthRecordErrorEl.hidden = true;

  if (!file) {
    addHealthRecordFileNameEl.textContent = "No file chosen";
    addHealthRecordFileNameEl.classList.remove("has-file");
    return;
  }

  if (file.size > MAX_FILE_BYTES) {
    addHealthRecordFileEl.value = "";
    addHealthRecordFileNameEl.textContent = "No file chosen";
    addHealthRecordFileNameEl.classList.remove("has-file");
    addHealthRecordErrorEl.textContent = MAX_FILE_SIZE_MESSAGE;
    addHealthRecordErrorEl.hidden = false;
    return;
  }

  addHealthRecordFileNameEl.textContent = file.name;
  addHealthRecordFileNameEl.classList.add("has-file");
});
profileCloseBtn?.addEventListener("click", closePatientProfileModal);



addHealthRecordModalEl?.addEventListener("click", (event) => {
  if (event.target === addHealthRecordModalEl) closeAddHealthRecordModal();
});

profileModalEl?.addEventListener("click", (event) => {
  if (event.target === profileModalEl) closePatientProfileModal();
});

addPatientBtn?.addEventListener("click", openAddPatientModal);
addPatientCloseBtn?.addEventListener("click", closeAddPatientModal);
addPatientFormEl?.addEventListener("submit", handleAddPatientSubmit);
patientPinSuccessCloseBtn?.addEventListener("click", closePatientPinSuccessModal);
patientPinSuccessDoneBtn?.addEventListener("click", closePatientPinSuccessModal);
patientPinSuccessModalEl?.addEventListener("click", (event) => {
  if (event.target === patientPinSuccessModalEl) closePatientPinSuccessModal();
});

addPatientModalEl?.addEventListener("click", (event) => {
  if (event.target === addPatientModalEl) closeAddPatientModal();
});

document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") return;
  if (!addMedicationModalEl.hidden) closeAddMedicationModal();
  else if (!addRehabPlanModalEl?.hidden) closeAddRehabPlanModal();
  else if (!addTherapySessionModalEl?.hidden) closeAddTherapySessionModal();
  else if (!addHealthRecordModalEl.hidden) closeAddHealthRecordModal();
  else if (!profileModalEl.hidden) {
    if (isProfileEditing) handleProfileCancelEdit();
    else closePatientProfileModal();
  } else if (!patientPinSuccessModalEl?.hidden) closePatientPinSuccessModal();
  else if (!addPatientModalEl.hidden) closeAddPatientModal();
});

profileUpdateBtn?.addEventListener("click", handleProfileUpdateClick);
profileSaveBtn?.addEventListener("click", handleProfileSaveClick);
profileCancelBtn?.addEventListener("click", handleProfileCancelEdit);

const OPEN_COMMUNICATION_PATIENT_KEY = "auraOpenCommunicationPatientId";

document.getElementById("patient-profile-message")?.addEventListener("click", () => {
  const patient = getPatientById(activePatientId);
  if (!patient?.patientId || patient.patientId === "—") {
    window.alert("Patient User ID is missing.");
    return;
  }
  sessionStorage.setItem(OPEN_COMMUNICATION_PATIENT_KEY, patient.patientId);
  window.location.href = `communication.html?patient=${encodeURIComponent(patient.patientId)}`;
});

profileDeactivateBtn?.addEventListener("click", handleProfileDeactivateClick);

document.querySelectorAll(".clinical-tab").forEach((button) => {
  button.addEventListener("click", () => {
    switchClinicalTab(button.dataset.tab || "health-records");
  });
});
document.getElementById("btn-add-rehab-plan")?.addEventListener("click", openAddRehabPlanModal);
document.getElementById("btn-add-therapy-session")?.addEventListener("click", openAddTherapySessionModal);
document.getElementById("btn-add-health-record-tab")?.addEventListener("click", openAddHealthRecordModal);
document.getElementById("btn-add-medication-tab")?.addEventListener("click", openAddMedicationModal);
addRehabPlanCloseBtn?.addEventListener("click", closeAddRehabPlanModal);
addTherapySessionCloseBtn?.addEventListener("click", closeAddTherapySessionModal);
addRehabPlanFormEl?.addEventListener("submit", handleRehabPlanSubmit);
addTherapySessionFormEl?.addEventListener("submit", handleTherapySessionSubmit);
addRehabPlanModalEl?.addEventListener("click", (event) => {
  if (event.target === addRehabPlanModalEl) closeAddRehabPlanModal();
});
addTherapySessionModalEl?.addEventListener("click", (event) => {
  if (event.target === addTherapySessionModalEl) closeAddTherapySessionModal();
});

document.getElementById("add-patient-birthdate")?.setAttribute("max", todayDateString());

window.addEventListener("error", (event) => {
  if (countEl) {
    countEl.textContent = "Could not load patients";
  }
  console.error("Patients page error:", event.message, event.filename, event.lineno);
});

window.addEventListener("unhandledrejection", (event) => {
  if (countEl) {
    countEl.textContent = "Could not load patients";
  }
  console.error("Patients page async error:", event.reason);
});

initStaffAuth(initializePatientsPage);

const cachedStaffProfile = getStaffSession();
if (cachedStaffProfile?.role) {
  initializePatientsPage(cachedStaffProfile);
}
