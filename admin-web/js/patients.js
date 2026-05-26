import { initStaffAuth } from "./staff-shell.js";
import {
  createPatient,
  fetchPatients,
} from "./user-patients-service.js";

const HEALTH_RECORDS = {
  "pat-1": [
    {
      type: "EYE EXAMINATION",
      description:
        "Visual acuity test conducted. Prescription updated. Follow-up in 6 weeks.",
      doctor: "Dr. Sarah Tan",
    },
  ],
};

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

const addPatientModalEl = document.getElementById("add-patient-modal");
const addPatientFormEl = document.getElementById("add-patient-form");
const addPatientCloseBtn = document.getElementById("add-patient-close");
const addPatientBtn = document.getElementById("btn-add-patient");
const addPatientErrorEl = document.getElementById("add-patient-error");
const addPatientSubmitBtn = addPatientFormEl.querySelector('[type="submit"]');

let patients = [];
let statusFilter = "all";
let searchQuery = "";
let currentPage = 1;
let activePatientId = null;
let isSavingPatient = false;

function statusLabel(status) {
  return status.charAt(0).toUpperCase() + status.slice(1);
}

function patientStatusClass(status) {
  return `patient-status patient-status--${status}`;
}

function getPatientById(id) {
  return patients.find((p) => p.id === id);
}

function renderRecordCard(record) {
  return `
    <article class="health-record-card">
      <span class="health-record-tag">${record.type}</span>
      <p class="health-record-description">${record.description}</p>
      <footer class="health-record-footer">
        <span class="health-record-doctor">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2" />
            <circle cx="12" cy="7" r="4" />
          </svg>
          ${record.doctor}
        </span>
        <button type="button" class="btn-record-edit">Edit</button>
      </footer>
    </article>
  `;
}

function openHealthRecordsModal(patientId) {
  const patient = getPatientById(patientId);
  if (!patient) return;

  activePatientId = patientId;
  modalPatientEl.textContent = `Patient: ${patient.name}`;

  const records = HEALTH_RECORDS[patientId] || [];
  if (records.length === 0) {
    modalListEl.innerHTML = "";
    modalEmptyEl.hidden = false;
  } else {
    modalEmptyEl.hidden = true;
    modalListEl.innerHTML = records.map(renderRecordCard).join("");
  }

  healthModalEl.hidden = false;
  document.body.classList.add("modal-open");
  healthModalCloseBtn.focus();
}

function closeHealthRecordsModal() {
  healthModalEl.hidden = true;
  if (addPatientModalEl.hidden) document.body.classList.remove("modal-open");
  activePatientId = null;
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
  document.body.classList.add("modal-open");
  document.getElementById("add-patient-name").focus();
}

function closeAddPatientModal() {
  addPatientModalEl.hidden = true;
  if (healthModalEl.hidden) document.body.classList.remove("modal-open");
}

async function loadPatients() {
  try {
    patients = await fetchPatients();
    renderTable();
  } catch (error) {
    patients = [];
    countEl.textContent = "Could not load patients";
    tbodyEl.innerHTML = "";
    emptyEl.textContent = error?.message || "Failed to load patients from Firestore.";
    emptyEl.hidden = false;
  }
}

function filterPatients() {
  const q = searchQuery.toLowerCase();
  return patients.filter((patient) => {
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
        <button type="button" class="btn-profile-menu" aria-label="Open profile menu for ${patient.name}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <polyline points="6 9 12 15 18 9" />
          </svg>
        </button>
      </td>
    </tr>
  `;
}

function bindTableActions() {
  tbodyEl.querySelectorAll(".btn-view-records").forEach((btn) => {
    btn.addEventListener("click", () => {
      openHealthRecordsModal(btn.dataset.patientId);
    });
  });
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
    await loadPatients();
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
    filterTabs.forEach((t) => t.classList.remove("is-active"));
    tab.classList.add("is-active");
    statusFilter = tab.dataset.status;
    currentPage = 1;
    renderTable();
  });
});

healthModalCloseBtn.addEventListener("click", closeHealthRecordsModal);

healthModalEl.addEventListener("click", (event) => {
  if (event.target === healthModalEl) closeHealthRecordsModal();
});

addPatientBtn.addEventListener("click", openAddPatientModal);
addPatientCloseBtn.addEventListener("click", closeAddPatientModal);
addPatientFormEl.addEventListener("submit", handleAddPatientSubmit);

addPatientModalEl.addEventListener("click", (event) => {
  if (event.target === addPatientModalEl) closeAddPatientModal();
});

document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") return;
  if (!healthModalEl.hidden) closeHealthRecordsModal();
  else if (!addPatientModalEl.hidden) closeAddPatientModal();
});

document.getElementById("add-patient-birthdate").max = todayDateString();

initStaffAuth(() => {
  loadPatients();
});
