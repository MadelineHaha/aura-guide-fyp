import { initStaffAuth } from "./staff-shell.js";
import { fetchPatients } from "./user-patients-service.js";
import {
  createAppointment,
  dateToInputValue,
  fetchAppointments,
  timeToInputValue,
  todayDateString,
  updateAppointment,
  updateAppointmentStatus,
} from "./appointments-service.js";

const PAGE_SIZE = 4;

const tbodyEl = document.getElementById("appointments-tbody");
const emptyEl = document.getElementById("appointments-empty");
const countEl = document.getElementById("appointments-count");
const paginationEl = document.getElementById("appointments-pagination");
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

function statusLabel(status) {
  if (status === "done") return "Done";
  if (status === "cancelled") return "Cancelled";
  if (status === "rescheduled") return "Rescheduled";
  return "Scheduled";
}

function statusClass(status) {
  if (status === "cancelled") return "status-badge status-badge--cancelled";
  if (status === "done") return "status-badge status-badge--done";
  if (status === "rescheduled") return "status-badge status-badge--rescheduled";
  return "status-badge status-badge--scheduled";
}

function canMarkDone(status) {
  return status === "scheduled" || status === "rescheduled";
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

async function loadPatientsForSelect() {
  try {
    patientsForSelect = await fetchPatients();
    populatePatientSelect();
  } catch {
    patientsForSelect = [];
    patientSelectEl.innerHTML =
      '<option value="">Could not load patients</option>';
  }
}

async function loadAppointments() {
  try {
    appointments = await fetchAppointments();
    renderTable();
  } catch (error) {
    appointments = [];
    countEl.textContent = "Could not load appointments";
    tbodyEl.innerHTML = "";
    emptyEl.textContent =
      error?.message || "Failed to load appointments from Firestore.";
    emptyEl.hidden = false;
  }
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

function renderRow(apt) {
  const markDoneEnabled = canMarkDone(apt.status);
  const isCancelled = apt.status === "cancelled";

  return `
    <tr data-id="${apt.id}">
      <td>
        <p class="cell-primary">${apt.patientName}</p>
        <p class="cell-secondary">${apt.patientId}</p>
      </td>
      <td>${apt.datetime}</td>
      <td>${apt.appointmentType}</td>
      <td>${apt.location}</td>
      <td>${apt.staff}</td>
      <td><span class="${statusClass(apt.status)}">${statusLabel(apt.status)}</span></td>
      <td>
        <div class="row-actions">
          <button type="button" class="row-action row-action--edit" data-action="edit" data-id="${apt.id}" aria-label="Edit appointment">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M12 20h9" />
              <path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z" />
            </svg>
          </button>
          <button type="button" class="row-action row-action--confirm" data-action="done" data-id="${apt.id}" aria-label="Mark as done" ${markDoneEnabled ? "" : "disabled"}>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <polyline points="20 6 9 17 4 12" />
            </svg>
          </button>
          <button type="button" class="row-action row-action--cancel" data-action="cancel" data-id="${apt.id}" aria-label="Cancel appointment" ${isCancelled ? "disabled" : ""}>
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <line x1="18" y1="6" x2="6" y2="18" />
              <line x1="6" y1="6" x2="18" y2="18" />
            </svg>
          </button>
        </div>
      </td>
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

async function handleMarkDone(appointmentId) {
  const apt = getAppointmentById(appointmentId);
  if (!apt || !canMarkDone(apt.status)) return;

  try {
    await updateAppointmentStatus(appointmentId, "Done");
    await loadAppointments();
  } catch (error) {
    alert(error?.message || "Could not mark appointment as done.");
  }
}

async function handleCancel(appointmentId) {
  const apt = getAppointmentById(appointmentId);
  if (!apt || apt.status === "cancelled") return;

  if (!confirm(`Cancel appointment for ${apt.patientName}?`)) return;

  try {
    await updateAppointmentStatus(appointmentId, "Cancelled");
    await loadAppointments();
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
    await loadAppointments();
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

  if (action === "edit") {
    openEditAppointmentModal(appointmentId);
  } else if (action === "done") {
    handleMarkDone(appointmentId);
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

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !formModalEl.hidden) closeFormModal();
});

dateInputEl.min = todayDateString();

initStaffAuth((profile) => {
  staffProfile = profile;
  loadPatientsForSelect();
  loadAppointments();
});
