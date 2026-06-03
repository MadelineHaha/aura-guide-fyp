import { initStaffAuth, getInitials } from "./staff-shell.js";
import {
  createHealthRecord,
  fetchHealthRecordById,
  isHealthRecordsAccessError,
  subscribeHealthRecordsByUserId,
  INLINE_FILE_MAX_BYTES,
  MAX_FILE_BYTES,
  MAX_FILE_SIZE_MESSAGE,
  PRESET_RECORD_TYPES,
  prepareHealthRecordInput,
  updateHealthRecord,
  validateHealthRecordInput,
} from "./health-records-service.js";
import { getStaffSession } from "./staff-auth.js";
import {
  createPatient,
  dateToInputValue,
  deactivatePatient,
  subscribePatients,
  updatePatient,
} from "./user-patients-service.js";
import { releaseFirestoreListener } from "./firestore-realtime.js";

const PAGE_SIZE = 4;

const tbodyEl = document.getElementById("patients-tbody");
const emptyEl = document.getElementById("patients-empty");
const countEl = document.getElementById("patients-count");
const paginationEl = document.getElementById("patients-pagination");
const searchEl = document.getElementById("patient-search");
const filterTabs = document.querySelectorAll(".filter-tab");

const healthModalEl = document.getElementById("health-records-modal");
const modalPatientEl = document.getElementById("health-records-patient");
const modalListEl = document.getElementById("health-records-list");
const modalEmptyEl = document.getElementById("health-records-empty");
const healthModalCloseBtn = document.getElementById("health-records-close");
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
const addHealthRecordSubmitBtn = addHealthRecordFormEl.querySelector('[type="submit"]');
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
const addPatientSubmitBtn = addPatientFormEl.querySelector('[type="submit"]');

const profileModalEl = document.getElementById("patient-profile-modal");
const profileCloseBtn = document.getElementById("patient-profile-close");
const profileAvatarEl = document.getElementById("patient-profile-avatar");
const profileNameEl = document.getElementById("patient-profile-name");
const profileUserIdEl = document.getElementById("patient-profile-userid");
const profileEmailEl = document.getElementById("patient-profile-email");
const profilePhoneEl = document.getElementById("patient-profile-phone");
const profileAgeEl = document.getElementById("patient-profile-age");
const profileConditionEl = document.getElementById("patient-profile-condition");
const profileStatusEl = document.getElementById("patient-profile-status");
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
const profileConditionInput = document.getElementById("patient-profile-condition-input");
const profileStatusInput = document.getElementById("patient-profile-status-input");
const profileAddressInput = document.getElementById("patient-profile-address-input");
const profileSaveLabelEl = document.getElementById("patient-profile-save-label");
const profileDeactivateBtn = document.getElementById("patient-profile-deactivate");
const profileViewFields = profileModalEl.querySelectorAll(".profile-field-view");
const profileEditFields = profileModalEl.querySelectorAll(".profile-field-edit");

let patients = [];
let isProfileEditing = false;
let isSavingProfile = false;
let isDeactivatingPatient = false;
let statusFilter = "all";
let searchQuery = "";
let currentPage = 1;
let activePatientId = null;
let isSavingPatient = false;
let isSavingHealthRecord = false;
let editingHealthRecordId = null;
let loggedInStaffName = "Staff";
let loggedInStaffId = "";

function statusLabel(status) {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

function patientStatusClass(status) {
  return `patient-status patient-status--${status}`;
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

function renderRecordCard(record) {
  const recordId = record.recordId || "";
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
        <button type="button" class="btn-record-edit" data-record-id="${recordId}">Edit</button>
      </footer>
    </article>
  `;
}

let unsubscribeHealthRecords = null;

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
  const patient = getPatientById(patientId);
  if (!patient) return;

  activePatientId = patientId;
  modalPatientEl.textContent = `Patient: ${patient.name}`;

  healthModalEl.hidden = false;
  syncBodyModalLock();
  healthModalCloseBtn.focus();
  startHealthRecordsRealtime(patientId);
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
  if (!healthModalEl.hidden) {
    healthModalCloseBtn.focus();
  }
}

function syncBodyModalLock() {
  const anyOpen =
    !healthModalEl.hidden ||
    !addHealthRecordModalEl.hidden ||
    !addPatientModalEl.hidden ||
    !profileModalEl.hidden;
  document.body.classList.toggle("modal-open", anyOpen);
}

function closeHealthRecordsModal() {
  closeAddHealthRecordModal();
  stopHealthRecordsRealtime();
  healthModalEl.hidden = true;
  syncBodyModalLock();
  activePatientId = null;
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
  renderProfileFieldValue(profileConditionEl, patient.condition);
  profileStatusEl.classList.remove("is-unset");
  profileStatusEl.innerHTML = `<span class="${patientStatusClass(patient.status)}">${statusLabel(patient.status)}</span>`;
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
  profileConditionInput.value =
    patient.condition === "—" ? "" : patient.condition;
  profileStatusInput.value = patient.status || "stable";
  profileAddressInput.value = patient.address || "";
}

function getProfileFormData() {
  return {
    email: profileEmailInput.value.trim().toLowerCase(),
    phone: profilePhoneInput.value.trim(),
    birthDate: profileBirthdateInput.value,
    condition: profileConditionInput.value.trim(),
    clinicalStatus: profileStatusInput.value,
    address: profileAddressInput.value.trim(),
  };
}

function getPatientProfileBaseline(patient) {
  return {
    email: (patient.email || "").trim().toLowerCase(),
    phone: (patient.phone || "").trim(),
    birthDate: patient.birthDate ? dateToInputValue(patient.birthDate) : "",
    condition:
      patient.condition === "—" ? "" : String(patient.condition || "").trim(),
    clinicalStatus: patient.status || "stable",
    address: (patient.address || "").trim(),
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
  if (baseline.condition !== current.condition) {
    changes.condition = current.condition;
  }
  if (baseline.clinicalStatus !== current.clinicalStatus) {
    changes.clinicalStatus = current.clinicalStatus;
  }
  if (baseline.address !== current.address) changes.address = current.address;

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

  profileModalEl.hidden = false;
  syncBodyModalLock();
  profileCloseBtn.focus();
}

function closePatientProfileModal() {
  profileModalEl.hidden = true;
  setProfileEditMode(false);
  syncBodyModalLock();
  activePatientId = null;
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

function openAddPatientModal() {
  addPatientFormEl.reset();
  addPatientErrorEl.hidden = true;
  addPatientErrorEl.textContent = "";
  const birthdateInput = document.getElementById("add-patient-birthdate");
  birthdateInput.max = todayDateString();
  addPatientModalEl.hidden = false;
  syncBodyModalLock();
  document.getElementById("add-patient-name").focus();
}

function closeAddPatientModal() {
  addPatientModalEl.hidden = true;
  syncBodyModalLock();
}

let unsubscribePatients = null;

function startPatientsRealtime() {
  releaseFirestoreListener(unsubscribePatients);
  unsubscribePatients = subscribePatients(
    (list) => {
      patients = list;
      renderTable();
    },
    (error) => {
      patients = [];
      countEl.textContent = "Could not load patients";
      tbodyEl.innerHTML = "";
      emptyEl.textContent =
        error?.message || "Failed to load patients from Firestore.";
      emptyEl.hidden = false;
    },
  );
}

function filterPatients() {
  const q = searchQuery.toLowerCase();
  return patients.filter((patient) => {
    if (isPatientAccountInactive(patient)) return false;
    const matchesStatus =
      statusFilter === "all" || patient.status === statusFilter;
    const haystack = `${patient.name} ${patient.patientId} ${patient.condition}`.toLowerCase();
    const matchesSearch = !q || haystack.includes(q);
    return matchesStatus && matchesSearch;
  });
}

function renderRow(patient) {
  const ageDisplay =
    typeof patient.age === "number" ? patient.age : patient.age;
  return `
    <tr data-id="${patient.id}">
      <td>
        <p class="cell-primary">${patient.name}</p>
        <p class="cell-secondary">${patient.patientId}</p>
      </td>
      <td>${ageDisplay}</td>
      <td>${patient.condition}</td>
      <td>${patient.lastVisit}</td>
      <td><span class="${patientStatusClass(patient.status)}">${statusLabel(patient.status)}</span></td>
      <td>
        <button type="button" class="btn-view-records" data-patient-id="${patient.id}" aria-label="View health records for ${patient.name}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7-10-7-10-7z" />
            <circle cx="12" cy="12" r="3" />
          </svg>
          View
        </button>
      </td>
      <td>
        <button type="button" class="btn-profile-menu" data-patient-id="${patient.id}" aria-label="View profile for ${patient.name}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="6 9 12 15 18 9" />
          </svg>
        </button>
      </td>
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
  const filtered = filterPatients();
  const total = filtered.length;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  if (currentPage > totalPages) currentPage = totalPages;

  const start = (currentPage - 1) * PAGE_SIZE;
  const pageItems = filtered.slice(start, start + PAGE_SIZE);

  countEl.textContent = `${total} patient${total === 1 ? "" : "s"}`;
  emptyEl.textContent = "No patients match your search.";

  if (pageItems.length === 0) {
    tbodyEl.innerHTML = "";
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
  const email = document.getElementById("add-patient-email").value.trim();
  const birthDate = document.getElementById("add-patient-birthdate").value;
  const address = document.getElementById("add-patient-address").value.trim();

  if (!name || !email || !birthDate || !address) {
    addPatientErrorEl.textContent = "Please fill in all fields.";
    addPatientErrorEl.hidden = false;
    return;
  }

  if (!email.includes("@")) {
    addPatientErrorEl.textContent = "Please enter a valid email address.";
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
    await createPatient({ name, email, birthDate, address });
    closeAddPatientModal();
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
      Add Profile`;
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

tbodyEl.addEventListener("click", (event) => {
  const profileBtn = event.target.closest(".btn-profile-menu");
  if (profileBtn) {
    openPatientProfileModal(profileBtn.dataset.patientId);
    return;
  }

  const recordsBtn = event.target.closest(".btn-view-records");
  if (recordsBtn) {
    openHealthRecordsModal(recordsBtn.dataset.patientId);
  }
});

healthModalCloseBtn.addEventListener("click", closeHealthRecordsModal);
modalListEl.addEventListener("click", (event) => {
  const editBtn = event.target.closest(".btn-record-edit");
  if (!editBtn?.dataset.recordId) return;
  openEditHealthRecordModal(editBtn.dataset.recordId);
});
document.getElementById("btn-add-health-record").addEventListener("click", openAddHealthRecordModal);
addHealthRecordCloseBtn.addEventListener("click", closeAddHealthRecordModal);
addHealthRecordFormEl.addEventListener("submit", handleHealthRecordFormSubmit);
addHealthRecordTypeEl.addEventListener("change", () => {
  syncHealthRecordTypeOtherField();
  if (addHealthRecordTypeEl.value === "Other") {
    addHealthRecordTypeOtherEl.focus();
  }
});

addHealthRecordTypeOtherEl.addEventListener("input", () => {
  const cleaned = addHealthRecordTypeOtherEl.value.replace(/[^A-Za-z0-9 ]/g, "");
  if (cleaned !== addHealthRecordTypeOtherEl.value) {
    addHealthRecordTypeOtherEl.value = cleaned;
  }
});
addHealthRecordFileEl.addEventListener("change", () => {
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
profileCloseBtn.addEventListener("click", closePatientProfileModal);

healthModalEl.addEventListener("click", (event) => {
  if (event.target === healthModalEl) closeHealthRecordsModal();
});

addHealthRecordModalEl.addEventListener("click", (event) => {
  if (event.target === addHealthRecordModalEl) closeAddHealthRecordModal();
});

profileModalEl.addEventListener("click", (event) => {
  if (event.target === profileModalEl) closePatientProfileModal();
});

addPatientBtn.addEventListener("click", openAddPatientModal);
addPatientCloseBtn.addEventListener("click", closeAddPatientModal);
addPatientFormEl.addEventListener("submit", handleAddPatientSubmit);

addPatientModalEl.addEventListener("click", (event) => {
  if (event.target === addPatientModalEl) closeAddPatientModal();
});

document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") return;
  if (!addHealthRecordModalEl.hidden) closeAddHealthRecordModal();
  else if (!profileModalEl.hidden) {
    if (isProfileEditing) handleProfileCancelEdit();
    else closePatientProfileModal();
  } else if (!healthModalEl.hidden) closeHealthRecordsModal();
  else if (!addPatientModalEl.hidden) closeAddPatientModal();
});

profileUpdateBtn.addEventListener("click", handleProfileUpdateClick);
profileSaveBtn.addEventListener("click", handleProfileSaveClick);
profileCancelBtn.addEventListener("click", handleProfileCancelEdit);

document.getElementById("patient-profile-message").addEventListener("click", () => {
  window.location.href = "communication.html";
});

profileDeactivateBtn.addEventListener("click", handleProfileDeactivateClick);

document.getElementById("add-patient-birthdate").max = todayDateString();

initStaffAuth((profile) => {
  if (profile?.name) loggedInStaffName = profile.name;
  if (profile?.staffID) loggedInStaffId = profile.staffID;
  startPatientsRealtime();
});
