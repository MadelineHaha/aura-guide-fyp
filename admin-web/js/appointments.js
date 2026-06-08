import { initStaffAuth } from "./staff-shell.js";
import { subscribePatients } from "./user-patients-service.js";
import {
  createAppointment,
  completeAppointment,
  dateToInputValue,
  subscribeAppointments,
  timeToInputValue,
  todayDateString,
  acceptAppointment,
  updateAppointment,
  updateAppointmentStatus,
} from "./appointments-service.js";
import {
  defaultMedicationEndDate,
  reminderCountForFrequency,
} from "./medications-service.js";
import { releaseFirestoreListener } from "./firestore-realtime.js";

const PAGE_SIZE = 4;

const tbodyEl = document.getElementById("appointments-tbody");
const emptyEl = document.getElementById("appointments-empty");
const countEl = document.getElementById("appointments-count");
const paginationEl = document.getElementById("appointments-pagination");
const actionsHeaderEl = document.getElementById("appointments-actions-header");
const searchEl = document.getElementById("appointment-search");
const filterTabs = document.querySelectorAll(".filter-tab");

const formModalEl = document.getElementById("add-appointment-modal");
const appointmentFormEl = document.getElementById("add-appointment-form");
const formCloseBtn = document.getElementById("add-appointment-close");
const addBtn = document.getElementById("btn-add-appointment");
const formErrorEl = document.getElementById("add-appointment-error");
const formSubmitBtn = appointmentFormEl.querySelector('[type="submit"]');
const formTitleEl = document.getElementById("add-appointment-title");
const patientSelectEl = document.getElementById("add-appointment-patient");
const patientDisplayEl = document.getElementById("add-appointment-patient-display");
const patientFieldEl = document.getElementById("appointment-patient-field");
const dateInputEl = document.getElementById("add-appointment-date");

const ADD_SUBMIT_HTML = `
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true">
    <line x1="12" y1="5" x2="12" y2="19" />
    <line x1="5" y1="12" x2="19" y2="12" />
  </svg>
  Add Appointment`;

const SAVE_SUBMIT_HTML = `
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true">
    <polyline points="20 6 9 17 4 12" />
  </svg>
  Save Changes`;

let appointments = [];
let patientsForSelect = [];
let staffProfile = null;
let statusFilter = "all";
let searchQuery = "";
let currentPage = 1;
let isSaving = false;
let editingAppointmentId = null;
let acceptingAppointmentId = null;
let completingAppointmentId = null;

const acceptModalEl = document.getElementById("accept-appointment-modal");
const acceptFormEl = document.getElementById("accept-appointment-form");
const acceptCloseBtn = document.getElementById("accept-appointment-close");
const acceptDetailPatientEl = document.getElementById("accept-detail-patient");
const acceptDetailUserIdEl = document.getElementById("accept-detail-user-id");
const acceptDetailDatetimeEl = document.getElementById("accept-detail-datetime");
const acceptDetailTypeEl = document.getElementById("accept-detail-type");
const acceptDetailStaffEl = document.getElementById("accept-detail-staff");
const acceptDetailIdEl = document.getElementById("accept-detail-id");
const acceptDetailStatusEl = document.getElementById("accept-detail-status");
const acceptLocationEl = document.getElementById("accept-appointment-location");
const acceptErrorEl = document.getElementById("accept-appointment-error");
const acceptSubmitBtn = document.getElementById("accept-appointment-submit");

const completeModalEl = document.getElementById("complete-appointment-modal");
const completeFormEl = document.getElementById("complete-appointment-form");
const completeCloseBtn = document.getElementById("complete-appointment-close");
const completeDetailPatientEl = document.getElementById("complete-detail-patient");
const completeDetailDatetimeEl = document.getElementById("complete-detail-datetime");
const completeDetailTypeEl = document.getElementById("complete-detail-type");
const completeClinicalSummaryEl = document.getElementById("complete-clinical-summary");
const completeRecommendationEl = document.getElementById("complete-recommendation");
const completeFollowUpDateEl = document.getElementById("complete-follow-up-date");
const completeAddMedicationEl = document.getElementById("complete-add-medication");
const completeMedicationFieldsEl = document.getElementById("complete-medication-fields");
const completeMedicationsListEl = document.getElementById("complete-medications-list");
const completeAddMedRowBtn = document.getElementById("complete-add-med-row");
const completeErrorEl = document.getElementById("complete-appointment-error");
const completeSubmitBtn = document.getElementById("complete-appointment-submit");

const viewModalEl = document.getElementById("view-appointment-modal");
const viewCloseBtn = document.getElementById("view-appointment-close");
const viewDoneBtn = document.getElementById("view-appointment-done");
const viewDetailPatientEl = document.getElementById("view-detail-patient");
const viewDetailDatetimeEl = document.getElementById("view-detail-datetime");
const viewDetailTypeEl = document.getElementById("view-detail-type");
const viewDetailLocationEl = document.getElementById("view-detail-location");
const viewClinicalSummaryEl = document.getElementById("view-clinical-summary");
const viewRecommendationEl = document.getElementById("view-recommendation");
const viewFollowUpDateEl = document.getElementById("view-follow-up-date");

function formatFollowUpDateDisplay(value) {
  const trimmed = String(value || "").trim();
  return trimmed || "No follow-up date";
}

function statusLabel(status) {
  if (status === "done") return "Done";
  if (status === "cancelled") return "Cancelled";
  if (status === "rescheduled") return "Rescheduled";
  if (status === "pending") return "Pending";
  return "Scheduled";
}

function statusClass(status) {
  if (status === "cancelled") return "status-badge status-badge--cancelled";
  if (status === "done") return "status-badge status-badge--done";
  if (status === "rescheduled") return "status-badge status-badge--rescheduled";
  if (status === "pending") return "status-badge status-badge--pending";
  return "status-badge status-badge--scheduled";
}

function canMarkDone(status) {
  return status === "scheduled" || status === "rescheduled";
}

function canAccept(status) {
  return status === "pending";
}

function canEditDateTime(status) {
  return status === "scheduled" || status === "rescheduled";
}

function getAppointmentById(id) {
  return appointments.find((apt) => apt.id === id);
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/"/g, "&quot;");
}

/** @param {{ patientId: string, patientName: string } | null} lockedPatient */
function populatePatientSelect(lockedPatient = null) {
  if (lockedPatient?.patientId) {
    const name = lockedPatient.patientName || "Patient";
    const id = lockedPatient.patientId;
    patientSelectEl.innerHTML = `<option value="${escapeHtml(id)}">${escapeHtml(name)} (${escapeHtml(id)})</option>`;
    patientSelectEl.value = id;
    return;
  }

  const options = ['<option value="">Select patient</option>'];
  for (const patient of patientsForSelect) {
    options.push(
      `<option value="${escapeHtml(patient.patientId)}">${escapeHtml(patient.name)} (${escapeHtml(patient.patientId)})</option>`,
    );
  }
  patientSelectEl.innerHTML = options.join("");
}

let unsubscribePatients = null;
let unsubscribeAppointments = null;

function startPatientsForSelectRealtime() {
  releaseFirestoreListener(unsubscribePatients);
  unsubscribePatients = subscribePatients(
    (list) => {
      patientsForSelect = list;
      populatePatientSelect();
    },
    () => {
      patientsForSelect = [];
      patientSelectEl.innerHTML =
        '<option value="">Could not load patients</option>';
    },
  );
}

function startAppointmentsRealtime() {
  releaseFirestoreListener(unsubscribeAppointments);
  unsubscribeAppointments = subscribeAppointments(
    (list) => {
      appointments = list;
      renderTable();
    },
    (error) => {
      appointments = [];
      countEl.textContent = "Could not load appointments";
      tbodyEl.innerHTML = "";
      emptyEl.textContent =
        error?.message || "Failed to load appointments from Firestore.";
      emptyEl.hidden = false;
    },
  );
}

function filterAppointments() {
  const q = searchQuery.toLowerCase();
  return appointments.filter((apt) => {
    const matchesStatus =
      statusFilter === "all" || apt.status === statusFilter;
    const haystack = `${apt.patientName} ${apt.patientId} ${apt.staff} ${apt.appointmentType} ${apt.location} ${apt.appointmentId}`.toLowerCase();
    const matchesSearch = !q || haystack.includes(q);
    return matchesStatus && matchesSearch;
  });
}

function renderPendingActions(apt) {
  return `
    <div class="row-actions row-actions--text">
      <button
        type="button"
        class="btn-row-text btn-row-text--accept"
        data-action="accept"
        data-id="${apt.id}"
      >
        Accept
      </button>
      <button
        type="button"
        class="btn-row-text btn-row-text--decline"
        data-action="cancel"
        data-id="${apt.id}"
      >
        Decline
      </button>
    </div>
  `;
}

function renderScheduledActions(apt) {
  const markDoneEnabled = canMarkDone(apt.status);
  const isCancelled = apt.status === "cancelled";
  const isDone = apt.status === "done";

  if (isDone) {
    return `
      <div class="row-actions">
        <button type="button" class="row-action row-action--edit" data-action="details" data-id="${apt.id}" aria-label="View appointment details">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z" />
            <circle cx="12" cy="12" r="3" />
          </svg>
        </button>
      </div>
    `;
  }

  return `
    <div class="row-actions">
      <button type="button" class="row-action row-action--edit" data-action="edit" data-id="${apt.id}" aria-label="Edit appointment" ${isCancelled ? "disabled" : ""}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M12 20h9" />
          <path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z" />
        </svg>
      </button>
      <button type="button" class="row-action row-action--confirm" data-action="done" data-id="${apt.id}" aria-label="Mark as done" ${markDoneEnabled ? "" : "disabled"}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <polyline points="20 6 9 17 4 12" />
        </svg>
      </button>
      <button type="button" class="row-action row-action--cancel" data-action="cancel" data-id="${apt.id}" aria-label="Cancel appointment" ${isCancelled ? "disabled" : ""}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <line x1="18" y1="6" x2="6" y2="18" />
          <line x1="6" y1="6" x2="18" y2="18" />
        </svg>
      </button>
    </div>
  `;
}

function renderRow(apt) {
  const isPending = apt.status === "pending";
  const actionsHtml = isPending
    ? renderPendingActions(apt)
    : renderScheduledActions(apt);

  return `
    <tr data-id="${apt.id}">
      <td class="appointments-td appointments-td--patient">
        <p class="cell-primary">${apt.patientName}</p>
        <p class="cell-secondary">${apt.patientId}</p>
      </td>
      <td class="appointments-td appointments-td--datetime">${apt.datetime}</td>
      <td class="appointments-td appointments-td--type">${apt.appointmentType}</td>
      <td class="appointments-td appointments-td--location">${isPending ? "—" : apt.location}</td>
      <td class="appointments-td appointments-td--staff">${apt.staff}</td>
      <td class="appointments-td appointments-td--status"><span class="${statusClass(apt.status)}">${statusLabel(apt.status)}</span></td>
      <td class="appointments-td appointments-td--actions">${actionsHtml}</td>
    </tr>
  `;
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
  const filtered = filterAppointments();
  const total = filtered.length;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

  if (currentPage > totalPages) currentPage = totalPages;

  const start = (currentPage - 1) * PAGE_SIZE;
  const pageItems = filtered.slice(start, start + PAGE_SIZE);

  if (actionsHeaderEl) {
    actionsHeaderEl.textContent = statusFilter === "done" ? "Details" : "Actions";
  }

  countEl.textContent = `${total} appointment${total === 1 ? "" : "s"}`;
  emptyEl.textContent = "No appointments match your search.";

  if (pageItems.length === 0) {
    tbodyEl.innerHTML = "";
    emptyEl.hidden = false;
    paginationEl.innerHTML = "";
    return;
  }

  emptyEl.hidden = true;
  tbodyEl.innerHTML = pageItems.map(renderRow).join("");
  renderPagination(totalPages);
}

function openFormModal({ repopulatePatients = true, lockedPatient = null } = {}) {
  formErrorEl.hidden = true;
  formErrorEl.textContent = "";
  dateInputEl.min = todayDateString();
  if (repopulatePatients) {
    populatePatientSelect(lockedPatient);
  }
  formModalEl.hidden = false;
  document.body.classList.add("modal-open");
}

function showPatientFieldForAdd() {
  patientFieldEl.classList.remove("form-field--disabled");
  patientSelectEl.hidden = false;
  patientSelectEl.disabled = false;
  patientSelectEl.required = true;
  patientDisplayEl.hidden = true;
  patientDisplayEl.setAttribute("aria-hidden", "true");
}

function showPatientFieldForEdit(patientId, patientName) {
  const name = patientName || patientId;
  patientFieldEl.classList.add("form-field--disabled");
  patientSelectEl.hidden = true;
  patientSelectEl.required = false;
  patientDisplayEl.value = `${name} (${patientId})`;
  patientDisplayEl.hidden = false;
  patientDisplayEl.removeAttribute("aria-hidden");
}

function closeFormModal() {
  formModalEl.hidden = true;
  document.body.classList.remove("modal-open");
  showPatientFieldForAdd();
  editingAppointmentId = null;
}

function openAddAppointmentModal() {
  editingAppointmentId = null;
  appointmentFormEl.reset();
  formTitleEl.textContent = "Add Appointment";
  formSubmitBtn.innerHTML = ADD_SUBMIT_HTML;
  showPatientFieldForAdd();
  openFormModal();
  patientSelectEl.focus();
}

function openEditAppointmentModal(appointmentId) {
  const apt = getAppointmentById(appointmentId);
  if (!apt) return;

  editingAppointmentId = appointmentId;
  appointmentFormEl.reset();
  formTitleEl.textContent = "Edit Appointment";
  formSubmitBtn.innerHTML = SAVE_SUBMIT_HTML;

  const patientName =
    apt.patientName === "—" ? apt.patientId : apt.patientName;
  populatePatientSelect({
    patientId: apt.patientId,
    patientName,
  });
  showPatientFieldForEdit(apt.patientId, patientName);
  document.getElementById("add-appointment-type").value = apt.appointmentType;
  document.getElementById("add-appointment-location").value =
    apt.location === "—" ? "" : apt.location;
  document.getElementById("add-appointment-notes").value = apt.notes || "";

  if (apt.dateTime) {
    dateInputEl.value = dateToInputValue(apt.dateTime);
    document.getElementById("add-appointment-time").value = timeToInputValue(
      apt.dateTime,
    );
  }

  openFormModal({ repopulatePatients: false });
  document.getElementById("add-appointment-type").focus();
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

function defaultMedicationRowValues() {
  const today = todayDateString();
  const frequency = "Once daily";
  return {
    name: "",
    dosage: "",
    frequency,
    instructions: "",
    startDate: today,
    endDate: defaultMedicationEndDate(today),
    reminderTimes: defaultReminderTimesForFrequency(frequency),
  };
}

function reminderTimesLabelForFrequency(frequency) {
  const count = reminderCountForFrequency(frequency);
  if (frequency === "Weekly") return "Weekly reminder time";
  if (count === 1) return "Reminder time";
  return `Reminder times (${count} per day)`;
}

function syncMedicationReminderTimes(
  card,
  preserveExisting = true,
  initialTimes = null,
) {
  if (!card) return;

  const frequencyEl = card.querySelector(".complete-med-frequency");
  const container = card.querySelector(".complete-med-reminder-times");
  const labelEl = card.querySelector(".complete-med-reminder-times-label");
  if (!frequencyEl || !container) return;

  const frequency = frequencyEl.value;
  const count = reminderCountForFrequency(frequency);
  const defaults = defaultReminderTimesForFrequency(frequency);
  const existing = preserveExisting
    ? [...container.querySelectorAll(".complete-med-reminder-time")].map(
        (el) => el.value,
      )
    : initialTimes || defaults;

  if (labelEl) {
    labelEl.textContent = reminderTimesLabelForFrequency(frequency);
  }

  container.innerHTML = "";
  for (let i = 0; i < count; i += 1) {
    const value = existing[i] || defaults[i] || "08:00";
    container.insertAdjacentHTML(
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

function medicationFrequencyOptions(selected = "") {
  const options = [
    { value: "", label: "Select frequency" },
    { value: "Once daily", label: "Once daily" },
    { value: "Twice daily", label: "Twice daily" },
    { value: "Three times daily", label: "Three times daily" },
    { value: "Weekly", label: "Weekly" },
  ];
  return options
    .map(
      (opt) =>
        `<option value="${escapeHtml(opt.value)}"${opt.value === selected ? " selected" : ""}>${escapeHtml(opt.label)}</option>`,
    )
    .join("");
}

function medicationEndMinDate(startValue, today = todayDateString()) {
  if (startValue && startValue > today) return startValue;
  return today;
}

function syncMedicationDateConstraints(card) {
  if (!card) return;

  const today = todayDateString();
  const startEl = card.querySelector(".complete-med-start");
  const endEl = card.querySelector(".complete-med-end");
  if (!startEl || !endEl) return;

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

function syncAllMedicationDateConstraints() {
  for (const card of completeMedicationsListEl.querySelectorAll(
    ".complete-med-card",
  )) {
    syncMedicationDateConstraints(card);
  }
}

function createMedicationRowHtml(index, values = defaultMedicationRowValues()) {
  const showRemove = completeMedicationsListEl.children.length > 0;
  const today = todayDateString();
  return `
    <article class="complete-med-card" data-med-index="${index}">
      <div class="complete-med-card-header">
        <h3 class="complete-med-card-title">Medication ${index + 1}</h3>
        <button
          type="button"
          class="complete-med-remove-btn"
          data-action="remove-med"
          aria-label="Remove medication ${index + 1}"
          ${showRemove ? "" : "hidden"}
        >
          Remove
        </button>
      </div>
      <div class="add-patient-grid">
        <label class="form-field form-field--full">
          <span class="form-field-label">Medication Name</span>
          <input
            class="form-field-input complete-med-name"
            type="text"
            placeholder="e.g. Vitamin D 1000IU"
            value="${escapeHtml(values.name)}"
            required
          />
        </label>
        <label class="form-field">
          <span class="form-field-label">Dosage</span>
          <input
            class="form-field-input complete-med-dosage"
            type="text"
            placeholder="e.g. 1 capsule"
            value="${escapeHtml(values.dosage)}"
            required
          />
        </label>
        <label class="form-field">
          <span class="form-field-label">Frequency</span>
          <select class="form-field-input form-field-select complete-med-frequency" required>
            ${medicationFrequencyOptions(values.frequency)}
          </select>
        </label>
        <label class="form-field form-field--full">
          <span class="form-field-label">Instructions</span>
          <textarea
            class="form-field-input form-field-textarea complete-med-instructions"
            rows="2"
            placeholder="How the patient should take it"
            required
          >${escapeHtml(values.instructions)}</textarea>
        </label>
        <label class="form-field">
          <span class="form-field-label">Start Date</span>
          <input
            class="form-field-input complete-med-start"
            type="date"
            min="${escapeHtml(today)}"
            value="${escapeHtml(values.startDate)}"
            required
          />
        </label>
        <label class="form-field">
          <span class="form-field-label">End Date</span>
          <input
            class="form-field-input complete-med-end"
            type="date"
            min="${escapeHtml(today)}"
            value="${escapeHtml(values.endDate)}"
            required
          />
          <span class="form-field-hint">Cannot be before today or the start date.</span>
        </label>
        <div class="form-field form-field--full complete-med-reminder-times-field">
          <span class="form-field-label complete-med-reminder-times-label">${escapeHtml(reminderTimesLabelForFrequency(values.frequency || "Once daily"))}</span>
          <div class="complete-med-reminder-times"></div>
        </div>
      </div>
    </article>
  `;
}

function refreshMedicationRowLabels() {
  const cards = [...completeMedicationsListEl.querySelectorAll(".complete-med-card")];
  cards.forEach((card, index) => {
    card.dataset.medIndex = String(index);
    const title = card.querySelector(".complete-med-card-title");
    if (title) title.textContent = `Medication ${index + 1}`;
    const removeBtn = card.querySelector('[data-action="remove-med"]');
    if (removeBtn) removeBtn.hidden = cards.length <= 1;
  });
}

function addMedicationRow(values = defaultMedicationRowValues()) {
  const index = completeMedicationsListEl.children.length;
  completeMedicationsListEl.insertAdjacentHTML(
    "beforeend",
    createMedicationRowHtml(index, values),
  );
  const card = completeMedicationsListEl.lastElementChild;
  syncMedicationDateConstraints(card);
  syncMedicationReminderTimes(card, false, values.reminderTimes);
  refreshMedicationRowLabels();
}

function resetMedicationRows() {
  completeMedicationsListEl.innerHTML = "";
  addMedicationRow();
}

function setMedicationFieldsVisible(visible) {
  completeMedicationFieldsEl.hidden = !visible;
  if (visible && completeMedicationsListEl.children.length === 0) {
    resetMedicationRows();
  }
  if (visible) {
    syncAllMedicationDateConstraints();
  }
}

function readMedicationFromCard(card) {
  return {
    name: card.querySelector(".complete-med-name")?.value.trim() || "",
    dosage: card.querySelector(".complete-med-dosage")?.value.trim() || "",
    frequency: card.querySelector(".complete-med-frequency")?.value || "",
    instructions: card.querySelector(".complete-med-instructions")?.value.trim() || "",
    startDate: card.querySelector(".complete-med-start")?.value || "",
    endDate: card.querySelector(".complete-med-end")?.value || "",
    reminderTimes: [
      ...card.querySelectorAll(".complete-med-reminder-time"),
    ].map((el) => el.value.trim()),
  };
}

function collectMedicationsFromForm() {
  const cards = [...completeMedicationsListEl.querySelectorAll(".complete-med-card")];
  return cards.map((card, index) => {
    const med = readMedicationFromCard(card);
    return { index, ...med };
  });
}

function validateMedicationRows(rows) {
  const today = todayDateString();

  for (const row of rows) {
    const label = `Medication ${row.index + 1}`;
    if (!row.name) return `${label}: name is required.`;
    if (!row.dosage) return `${label}: dosage is required.`;
    if (!row.frequency) return `${label}: frequency is required.`;
    if (!row.instructions) return `${label}: instructions are required.`;
    if (!row.startDate) return `${label}: start date is required.`;
    if (!row.endDate) return `${label}: end date is required.`;
    const expectedTimes = reminderCountForFrequency(row.frequency);
    if (row.reminderTimes.length !== expectedTimes) {
      return `${label}: provide ${expectedTimes} reminder time(s) for ${row.frequency}.`;
    }
    if (row.reminderTimes.some((time) => !time)) {
      return `${label}: all reminder times are required.`;
    }
    if (new Set(row.reminderTimes).size !== row.reminderTimes.length) {
      return `${label}: reminder times must be different from each other.`;
    }
    if (row.startDate < today) {
      return `${label}: start date cannot be in the past.`;
    }
    const minEndDate = medicationEndMinDate(row.startDate, today);
    if (row.endDate < minEndDate) {
      return row.endDate < today
        ? `${label}: end date cannot be in the past.`
        : `${label}: end date must be on or after the start date.`;
    }
  }
  return null;
}

function closeCompleteModal() {
  completeModalEl.hidden = true;
  document.body.classList.remove("modal-open");
  completingAppointmentId = null;
  completeAddMedicationEl.checked = false;
  completeMedicationsListEl.innerHTML = "";
  setMedicationFieldsVisible(false);
}

function openCompleteModal(appointmentId) {
  const apt = getAppointmentById(appointmentId);
  if (!apt || !canMarkDone(apt.status)) return;

  completingAppointmentId = appointmentId;
  completeErrorEl.hidden = true;
  completeErrorEl.textContent = "";
  completeFormEl.reset();
  completeAddMedicationEl.checked = false;
  completeMedicationsListEl.innerHTML = "";
  setMedicationFieldsVisible(false);

  completeDetailPatientEl.textContent = apt.patientName || "—";
  completeDetailDatetimeEl.textContent = apt.datetime || "—";
  completeDetailTypeEl.textContent = apt.appointmentType || "—";
  completeFollowUpDateEl.value = "";
  completeFollowUpDateEl.min = todayDateString();

  completeModalEl.hidden = false;
  document.body.classList.add("modal-open");
  completeClinicalSummaryEl.focus();
}

function closeViewModal() {
  viewModalEl.hidden = true;
  document.body.classList.remove("modal-open");
}

function openViewModal(appointmentId) {
  const apt = getAppointmentById(appointmentId);
  if (!apt || apt.status !== "done") return;

  viewDetailPatientEl.textContent = `${apt.patientName} (${apt.patientId})`;
  viewDetailDatetimeEl.textContent = apt.datetime || "—";
  viewDetailTypeEl.textContent = apt.appointmentType || "—";
  viewDetailLocationEl.textContent = apt.location || "—";
  viewClinicalSummaryEl.textContent = apt.clinicalSummary || "—";
  viewRecommendationEl.textContent = apt.recommendation || "—";
  viewFollowUpDateEl.textContent = formatFollowUpDateDisplay(apt.followUpDate);

  viewModalEl.hidden = false;
  document.body.classList.add("modal-open");
}

async function handleCompleteSubmit(event) {
  event.preventDefault();
  if (!completingAppointmentId || isSaving) return;

  const apt = getAppointmentById(completingAppointmentId);
  if (!apt) return;

  const staffId = staffProfile?.staffID?.trim() || apt.staffId || "";
  const userId = apt.patientId;
  const clinicalSummary = completeClinicalSummaryEl.value.trim();
  const recommendation = completeRecommendationEl.value.trim();
  const followUpDate = completeFollowUpDateEl.value.trim();
  const addMedications = completeAddMedicationEl.checked;

  if (!clinicalSummary) {
    completeErrorEl.textContent = "Clinical summary is required.";
    completeErrorEl.hidden = false;
    return;
  }

  let medications = [];
  if (addMedications) {
    syncAllMedicationDateConstraints();
    const rows = collectMedicationsFromForm();
    const validationError = validateMedicationRows(rows);
    if (validationError) {
      completeErrorEl.textContent = validationError;
      completeErrorEl.hidden = false;
      return;
    }

    medications = rows.map((row) => ({
      name: row.name,
      dosage: row.dosage,
      frequency: row.frequency,
      instructions: row.instructions,
      startDate: row.startDate,
      endDate: row.endDate,
      reminderDate: row.startDate,
      reminderTimes: row.reminderTimes,
    }));
  }

  isSaving = true;
  completeSubmitBtn.disabled = true;
  const originalLabel = completeSubmitBtn.innerHTML;
  completeSubmitBtn.textContent = "Saving…";

  try {
    await completeAppointment({
      appointmentId: completingAppointmentId,
      clinicalSummary,
      recommendation,
      followUpDate,
      staffId,
      userId,
      medications,
    });
    closeCompleteModal();
  } catch (error) {
    const code = error?.code;
    if (code === "permission-denied") {
      completeErrorEl.textContent =
        "Permission denied. Deploy Firestore rules for appointments and medications.";
    } else {
      completeErrorEl.textContent =
        error?.message || "Could not complete appointment. Please try again.";
    }
    completeErrorEl.hidden = false;
  } finally {
    isSaving = false;
    completeSubmitBtn.disabled = false;
    completeSubmitBtn.innerHTML = originalLabel;
  }
}

function closeAcceptModal() {
  acceptModalEl.hidden = true;
  document.body.classList.remove("modal-open");
  acceptingAppointmentId = null;
}

function openAcceptModal(appointmentId) {
  const apt = getAppointmentById(appointmentId);
  if (!apt || !canAccept(apt.status)) return;

  acceptingAppointmentId = appointmentId;
  acceptErrorEl.hidden = true;
  acceptErrorEl.textContent = "";
  acceptDetailPatientEl.textContent = apt.patientName || "—";
  acceptDetailUserIdEl.textContent = apt.patientId || "—";
  acceptDetailDatetimeEl.textContent = apt.datetime || "—";
  acceptDetailTypeEl.textContent = apt.appointmentType || "—";
  acceptDetailStaffEl.textContent = apt.staff || "—";
  acceptDetailIdEl.textContent = apt.appointmentId || apt.id || "—";
  acceptDetailStatusEl.textContent = statusLabel(apt.status);
  const currentLoc =
    apt.location && apt.location !== "—" ? apt.location : "";
  acceptLocationEl.value = currentLoc;
  acceptModalEl.hidden = false;
  document.body.classList.add("modal-open");
  acceptLocationEl.focus();
}

async function handleAcceptSubmit(event) {
  event.preventDefault();
  if (!acceptingAppointmentId || isSaving) return;

  const location = acceptLocationEl.value.trim();
  if (!location) {
    acceptErrorEl.textContent = "Please enter a location before accepting.";
    acceptErrorEl.hidden = false;
    return;
  }

  isSaving = true;
  acceptSubmitBtn.disabled = true;
  const originalLabel = acceptSubmitBtn.innerHTML;
  acceptSubmitBtn.textContent = "Saving…";

  try {
    await acceptAppointment(acceptingAppointmentId, location);
    closeAcceptModal();
  } catch (error) {
    acceptErrorEl.textContent =
      error?.message || "Could not accept appointment. Please try again.";
    acceptErrorEl.hidden = false;
  } finally {
    isSaving = false;
    acceptSubmitBtn.disabled = false;
    acceptSubmitBtn.innerHTML = originalLabel;
  }
}

async function handleCancel(appointmentId) {
  const apt = getAppointmentById(appointmentId);
  if (!apt || apt.status === "cancelled") return;

  const verb = apt.status === "pending" ? "Decline" : "Cancel";
  if (!confirm(`${verb} appointment request for ${apt.patientName}?`)) return;

  try {
    await updateAppointmentStatus(appointmentId, "Cancelled");
  } catch (error) {
    alert(error?.message || "Could not cancel appointment.");
  }
}

async function handleAppointmentFormSubmit(event) {
  event.preventDefault();
  if (isSaving) return;

  formErrorEl.hidden = true;

  const userId = patientSelectEl.value;
  const appointmentType = document.getElementById("add-appointment-type").value;
  const location = document.getElementById("add-appointment-location").value.trim();
  const date = document.getElementById("add-appointment-date").value;
  const time = document.getElementById("add-appointment-time").value;
  const notes = document.getElementById("add-appointment-notes").value.trim();
  const staffId = staffProfile?.staffID?.trim() || "";

  if (!userId || !appointmentType || !location || !date || !time) {
    formErrorEl.textContent = "Please fill in all required fields.";
    formErrorEl.hidden = false;
    return;
  }

  isSaving = true;
  formSubmitBtn.disabled = true;
  const originalLabel = formSubmitBtn.innerHTML;
  formSubmitBtn.textContent = "Saving…";

  try {
    if (editingAppointmentId) {
      const apt = getAppointmentById(editingAppointmentId);
      await updateAppointment({
        appointmentId: editingAppointmentId,
        userId: apt?.patientId || userId,
        date,
        time,
        appointmentType,
        location,
        notes,
        requireFuture: canEditDateTime(apt?.status),
        currentStatus: apt?.status,
        previousDateTime: apt?.dateTime,
      });
    } else {
      if (!staffId) {
        formErrorEl.textContent =
          "Your staff profile is missing a Staff ID. Add staffID in Firestore healthcarestaff.";
        formErrorEl.hidden = false;
        return;
      }

      await createAppointment({
        userId,
        staffId,
        date,
        time,
        appointmentType,
        location,
        notes,
      });
    }

    closeFormModal();
  } catch (error) {
    const code = error?.code;
    if (code === "permission-denied") {
      formErrorEl.textContent =
        "Permission denied. Deploy Firestore rules for appointments.";
    } else {
      formErrorEl.textContent =
        error?.message || "Could not save appointment. Please try again.";
    }
    formErrorEl.hidden = false;
  } finally {
    isSaving = false;
    formSubmitBtn.disabled = false;
    formSubmitBtn.innerHTML = originalLabel;
  }
}

tbodyEl.addEventListener("click", (event) => {
  const btn = event.target.closest("[data-action]");
  if (!btn || btn.disabled) return;

  const appointmentId = btn.dataset.id;
  const action = btn.dataset.action;

  if (action === "accept") {
    openAcceptModal(appointmentId);
  } else if (action === "edit") {
    openEditAppointmentModal(appointmentId);
  } else if (action === "done") {
    openCompleteModal(appointmentId);
  } else if (action === "details") {
    openViewModal(appointmentId);
  } else if (action === "cancel") {
    handleCancel(appointmentId);
  }
});

searchEl.addEventListener("input", () => {
  searchQuery = searchEl.value.trim();
  currentPage = 1;
  renderTable();
});

filterTabs.forEach((tab) => {
  tab.addEventListener("click", () => {
    filterTabs.forEach((t) => t.classList.remove("is-active"));
    tab.classList.add("is-active");
    statusFilter = tab.dataset.status;
    currentPage = 1;
    renderTable();
  });
});

addBtn.addEventListener("click", openAddAppointmentModal);
formCloseBtn.addEventListener("click", closeFormModal);
appointmentFormEl.addEventListener("submit", handleAppointmentFormSubmit);

formModalEl.addEventListener("click", (event) => {
  if (event.target === formModalEl) closeFormModal();
});

acceptCloseBtn.addEventListener("click", closeAcceptModal);
acceptFormEl.addEventListener("submit", handleAcceptSubmit);

acceptModalEl.addEventListener("click", (event) => {
  if (event.target === acceptModalEl) closeAcceptModal();
});

completeCloseBtn.addEventListener("click", closeCompleteModal);
completeFormEl.addEventListener("submit", handleCompleteSubmit);
completeAddMedicationEl.addEventListener("change", () => {
  setMedicationFieldsVisible(completeAddMedicationEl.checked);
});

completeAddMedRowBtn.addEventListener("click", () => {
  addMedicationRow();
});

completeMedicationsListEl.addEventListener("click", (event) => {
  const removeBtn = event.target.closest('[data-action="remove-med"]');
  if (!removeBtn) return;
  const card = removeBtn.closest(".complete-med-card");
  if (!card || completeMedicationsListEl.children.length <= 1) return;
  card.remove();
  refreshMedicationRowLabels();
});

function handleMedicationDateFieldEvent(event) {
  const target = event.target;
  const card = target.closest(".complete-med-card");
  if (!card) return;

  if (target.classList.contains("complete-med-frequency")) {
    syncMedicationReminderTimes(card, true);
    return;
  }

  if (
    target.classList.contains("complete-med-start") ||
    target.classList.contains("complete-med-end")
  ) {
    syncMedicationDateConstraints(card);
  }
}

completeMedicationsListEl.addEventListener("change", handleMedicationDateFieldEvent);
completeMedicationsListEl.addEventListener("input", handleMedicationDateFieldEvent);
completeMedicationsListEl.addEventListener("blur", handleMedicationDateFieldEvent, true);

completeModalEl.addEventListener("click", (event) => {
  if (event.target === completeModalEl) closeCompleteModal();
});

viewCloseBtn.addEventListener("click", closeViewModal);
viewDoneBtn.addEventListener("click", closeViewModal);
viewModalEl.addEventListener("click", (event) => {
  if (event.target === viewModalEl) closeViewModal();
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !formModalEl.hidden) closeFormModal();
  if (event.key === "Escape" && !acceptModalEl.hidden) closeAcceptModal();
  if (event.key === "Escape" && !completeModalEl.hidden) closeCompleteModal();
  if (event.key === "Escape" && !viewModalEl.hidden) closeViewModal();
});

dateInputEl.min = todayDateString();

initStaffAuth((profile) => {
  staffProfile = profile;
  startPatientsForSelectRealtime();
  startAppointmentsRealtime();
});
