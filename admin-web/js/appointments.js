import { initStaffAuth } from "./staff-shell.js";
import { fetchPatients } from "./user-patients-service.js";
import {
  createAppointment,
  fetchAppointments,
  todayDateString,
} from "./appointments-service.js";

const PAGE_SIZE = 4;

const tbodyEl = document.getElementById("appointments-tbody");
const emptyEl = document.getElementById("appointments-empty");
const countEl = document.getElementById("appointments-count");
const paginationEl = document.getElementById("appointments-pagination");
const searchEl = document.getElementById("appointment-search");
const filterTabs = document.querySelectorAll(".filter-tab");

const addModalEl = document.getElementById("add-appointment-modal");
const addFormEl = document.getElementById("add-appointment-form");
const addCloseBtn = document.getElementById("add-appointment-close");
const addBtn = document.getElementById("btn-add-appointment");
const addErrorEl = document.getElementById("add-appointment-error");
const addSubmitBtn = addFormEl.querySelector('[type="submit"]');
const patientSelectEl = document.getElementById("add-appointment-patient");
const dateInputEl = document.getElementById("add-appointment-date");

let appointments = [];
let patientsForSelect = [];
let staffProfile = null;
let statusFilter = "all";
let searchQuery = "";
let currentPage = 1;
let isSaving = false;

function statusLabel(status) {
  if (status === "rescheduled") return "Rescheduled";
  if (status === "cancelled") return "Cancelled";
  return "Scheduled";
}

function statusClass(status) {
  if (status === "cancelled") return "status-badge status-badge--cancelled";
  if (status === "rescheduled") return "status-badge status-badge--rescheduled";
  return "status-badge status-badge--scheduled";
}

function populatePatientSelect() {
  const options = ['<option value="">Select patient</option>'];
  for (const patient of patientsForSelect) {
    options.push(
      `<option value="${patient.patientId}">${patient.name} (${patient.patientId})</option>`,
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
          <button type="button" class="row-action row-action--edit" aria-label="Edit appointment">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M12 20h9" />
              <path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z" />
            </svg>
          </button>
          <button type="button" class="row-action row-action--confirm" aria-label="Mark rescheduled">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <polyline points="20 6 9 17 4 12" />
            </svg>
          </button>
          <button type="button" class="row-action row-action--cancel" aria-label="Cancel appointment">
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

function openAddAppointmentModal() {
  addFormEl.reset();
  addErrorEl.hidden = true;
  addErrorEl.textContent = "";
  dateInputEl.min = todayDateString();
  populatePatientSelect();
  addModalEl.hidden = false;
  document.body.classList.add("modal-open");
  patientSelectEl.focus();
}

function closeAddAppointmentModal() {
  addModalEl.hidden = true;
  document.body.classList.remove("modal-open");
}

async function handleAddAppointmentSubmit(event) {
  event.preventDefault();
  if (isSaving) return;

  addErrorEl.hidden = true;

  const userId = patientSelectEl.value;
  const appointmentType = document.getElementById("add-appointment-type").value;
  const location = document.getElementById("add-appointment-location").value.trim();
  const date = document.getElementById("add-appointment-date").value;
  const time = document.getElementById("add-appointment-time").value;
  const notes = document.getElementById("add-appointment-notes").value.trim();
  const staffId = staffProfile?.staffID?.trim() || "";

  if (!userId || !appointmentType || !location || !date || !time) {
    addErrorEl.textContent = "Please fill in all required fields.";
    addErrorEl.hidden = false;
    return;
  }

  if (!staffId) {
    addErrorEl.textContent =
      "Your staff profile is missing a Staff ID. Add staffID in Firestore healthcarestaff.";
    addErrorEl.hidden = false;
    return;
  }

  isSaving = true;
  addSubmitBtn.disabled = true;
  const originalLabel = addSubmitBtn.innerHTML;
  addSubmitBtn.textContent = "Saving…";

  try {
    await createAppointment({
      userId,
      staffId,
      date,
      time,
      appointmentType,
      location,
      notes,
    });
    closeAddAppointmentModal();
    currentPage = 1;
    await loadAppointments();
  } catch (error) {
    const code = error?.code;
    if (code === "permission-denied") {
      addErrorEl.textContent =
        "Permission denied. Deploy Firestore rules for appointments.";
    } else {
      addErrorEl.textContent =
        error?.message || "Could not save appointment. Please try again.";
    }
    addErrorEl.hidden = false;
  } finally {
    isSaving = false;
    addSubmitBtn.disabled = false;
    addSubmitBtn.innerHTML = originalLabel;
  }
}

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
addCloseBtn.addEventListener("click", closeAddAppointmentModal);
addFormEl.addEventListener("submit", handleAddAppointmentSubmit);

addModalEl.addEventListener("click", (event) => {
  if (event.target === addModalEl) closeAddAppointmentModal();
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && !addModalEl.hidden) closeAddAppointmentModal();
});

dateInputEl.min = todayDateString();

initStaffAuth((profile) => {
  staffProfile = profile;
  loadPatientsForSelect();
  loadAppointments();
});
