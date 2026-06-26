import { initStaffAuth } from "./staff-shell.js";
import { formatFirestoreError, showStaffDataBanner } from "./staff-data-status.js";
import { isAdmin, roleDisplayLabel } from "./staff-rbac.js";
import {
  createPatient,
  createStaff,
  deactivatePatient,
  deactivateStaff,
  subscribePatients,
  updatePatient,
} from "./user-patients-service.js";
import { subscribeAllStaff } from "./staff-list-service.js";
import { releaseFirestoreListener } from "./firestore-realtime.js";

const tabsEl = document.getElementById("admin-tabs");
const createFormEl = document.getElementById("create-account-form");
const createTypeEl = document.getElementById("create-account-type");
const createNameEl = document.getElementById("create-account-name");
const createEmailEl = document.getElementById("create-account-email");
const createPasswordEl = document.getElementById("create-account-password");
const createBirthdateEl = document.getElementById("create-account-birthdate");
const createAddressEl = document.getElementById("create-account-address");
const createSpecialtyEl = document.getElementById("create-account-specialty");
const createBirthdateFieldEl = document.getElementById("create-account-birthdate-field");
const createAddressFieldEl = document.getElementById("create-account-address-field");
const createSpecialtyFieldEl = document.getElementById("create-account-specialty-field");
const createErrorEl = document.getElementById("create-account-error");
const createSubmitEl = document.getElementById("create-account-submit");

const staffTbodyEl = document.getElementById("staff-accounts-tbody");
const staffEmptyEl = document.getElementById("staff-accounts-empty");
const assignmentTbodyEl = document.getElementById("assignment-tbody");
const assignmentEmptyEl = document.getElementById("assignment-empty");

let patientsCache = [];
let staffCache = [];
let unsubscribePatients = null;
let unsubscribeStaff = null;
let isSaving = false;

function todayDateString() {
  const d = new Date();
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function syncCreateAccountFields() {
  const type = createTypeEl.value;
  const isPatient = type === "patient";
  createBirthdateFieldEl.hidden = !isPatient;
  createAddressFieldEl.hidden = !isPatient;
  createSpecialtyFieldEl.hidden = isPatient;
  createBirthdateEl.required = isPatient;
  createAddressEl.required = isPatient;
}

function switchTab(tabName) {
  tabsEl?.querySelectorAll(".admin-tab").forEach((btn) => {
    btn.classList.toggle("is-active", btn.dataset.tab === tabName);
  });
  document.querySelectorAll("[data-panel]").forEach((panel) => {
    panel.hidden = panel.dataset.panel !== tabName;
  });
}

function renderStaffTable() {
  if (!staffTbodyEl) return;
  const rows = staffCache.filter((member) => member.role.toLowerCase() !== "admin");
  if (rows.length === 0) {
    staffTbodyEl.innerHTML = "";
    staffEmptyEl.hidden = false;
    return;
  }
  staffEmptyEl.hidden = true;
  staffTbodyEl.innerHTML = rows
    .map(
      (member) => `
      <tr data-uid="${member.uid}">
        <td>${escapeHtml(member.name)}</td>
        <td>${escapeHtml(member.staffID || "—")}</td>
        <td>${escapeHtml(roleDisplayLabel(member.role))}</td>
        <td>${escapeHtml(member.status || "—")}</td>
        <td>
          ${
            member.status === "Active"
              ? `<button type="button" class="btn-secondary btn-sm" data-disable-staff="${member.uid}">Disable</button>`
              : `<span class="cell-secondary">Disabled</span>`
          }
        </td>
      </tr>`,
    )
    .join("");
}

function doctorOptions(selectedUid = "") {
  return staffCache
    .filter((member) => member.status === "Active" && member.role.toLowerCase() === "doctor")
    .map(
      (member) =>
        `<option value="${member.uid}" ${member.uid === selectedUid ? "selected" : ""}>${escapeHtml(member.name)}</option>`,
    )
    .join("");
}

function therapistOptions(selectedUid = "") {
  return staffCache
    .filter((member) => member.status === "Active" && member.role.toLowerCase() === "therapist")
    .map(
      (member) =>
        `<option value="${member.uid}" ${member.uid === selectedUid ? "selected" : ""}>${escapeHtml(member.name)}</option>`,
    )
    .join("");
}

function renderAssignmentTable() {
  if (!assignmentTbodyEl) return;
  const activePatients = patientsCache.filter((patient) => patient.accountStatus !== "Inactive");
  if (activePatients.length === 0) {
    assignmentTbodyEl.innerHTML = "";
    assignmentEmptyEl.hidden = false;
    return;
  }
  assignmentEmptyEl.hidden = true;
  assignmentTbodyEl.innerHTML = activePatients
    .map(
      (patient) => `
      <tr data-patient-id="${patient.id}">
        <td>
          <p class="cell-primary">${escapeHtml(patient.name)}</p>
          <p class="cell-secondary">${escapeHtml(patient.patientId)}</p>
        </td>
        <td>
          <select class="form-field-input" data-doctor-select="${patient.id}">
            <option value="">— Unassigned —</option>
            ${doctorOptions(patient.assignedDoctorId)}
          </select>
        </td>
        <td>
          <select class="form-field-input" data-therapist-select="${patient.id}">
            <option value="">— Unassigned —</option>
            ${therapistOptions(patient.assignedTherapistId)}
          </select>
        </td>
        <td>
          <button type="button" class="btn-primary btn-sm" data-save-assignment="${patient.id}">Save</button>
        </td>
      </tr>`,
    )
    .join("");
}

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function staffNameForUid(uid) {
  if (!uid) return "";
  const member = staffCache.find((entry) => entry.uid === uid);
  return member?.name || "";
}

async function handleCreateAccount(event) {
  event.preventDefault();
  if (isSaving) return;
  createErrorEl.hidden = true;

  const type = createTypeEl.value;
  const name = createNameEl.value.trim();
  const email = createEmailEl.value.trim();
  const password = createPasswordEl.value;

  if (!name || !email) {
    createErrorEl.textContent = "Name and email are required.";
    createErrorEl.hidden = false;
    return;
  }

  isSaving = true;
  createSubmitEl.disabled = true;
  createSubmitEl.textContent = "Creating…";

  try {
    if (type === "patient") {
      const birthDate = createBirthdateEl.value;
      const address = createAddressEl.value.trim();
      if (!birthDate || !address) {
        throw new Error("Birth date and address are required for patients.");
      }
      const result = await createPatient({ name, birthDate, address });
      window.alert(
        `Patient account created.\n\nUser ID: ${result?.userId || "—"}\n4-digit PIN: ${result?.onboardingPin || "—"}\n\nShare these with the patient for first-time app setup.`,
      );
    } else {
      const specialty = createSpecialtyEl.value.trim();
      const role =
        type === "doctor" ? "doctor" : type === "therapist" ? "therapist" : "caregiver";
      await createStaff({ name, email, role, specialty });
      window.alert(
        `Staff account created. A password setup email has been sent to ${email}.`,
      );
    }
    createFormEl.reset();
    syncCreateAccountFields();
    createBirthdateEl.max = todayDateString();
  } catch (error) {
    createErrorEl.textContent = error?.message || "Could not create account.";
    createErrorEl.hidden = false;
  } finally {
    isSaving = false;
    createSubmitEl.disabled = false;
    createSubmitEl.textContent = "Create account";
  }
}

async function handleStaffTableClick(event) {
  const button = event.target.closest("[data-disable-staff]");
  if (!button) return;
  const uid = button.getAttribute("data-disable-staff");
  if (!uid) return;
  if (!window.confirm("Disable this staff account? They will not be able to sign in.")) return;
  button.disabled = true;
  try {
    await deactivateStaff(uid);
  } catch (error) {
    window.alert(error?.message || "Could not disable staff account.");
    button.disabled = false;
  }
}

async function handleAssignmentTableClick(event) {
  const button = event.target.closest("[data-save-assignment]");
  if (!button) return;
  const patientDocId = button.getAttribute("data-save-assignment");
  const row = assignmentTbodyEl.querySelector(`tr[data-patient-id="${patientDocId}"]`);
  if (!row) return;

  const doctorUid = row.querySelector(`[data-doctor-select="${patientDocId}"]`)?.value || "";
  const therapistUid = row.querySelector(`[data-therapist-select="${patientDocId}"]`)?.value || "";

  button.disabled = true;
  button.textContent = "Saving…";
  try {
    await updatePatient(patientDocId, {
      assignedDoctorId: doctorUid,
      assignedDoctorName: staffNameForUid(doctorUid),
      assignedTherapistId: therapistUid,
      assignedTherapistName: staffNameForUid(therapistUid),
    });
    button.textContent = "Saved";
    setTimeout(() => {
      button.textContent = "Save";
      button.disabled = false;
    }, 1200);
  } catch (error) {
    window.alert(error?.message || "Could not save assignment.");
    button.textContent = "Save";
    button.disabled = false;
  }
}

function startRealtime() {
  unsubscribePatients = subscribePatients(
    (list) => {
      patientsCache = list;
      renderAssignmentTable();
    },
    (error) => {
      console.error("Administration patients listener failed:", error);
      showStaffDataBanner(formatFirestoreError(error, "patients"));
    },
  );

  unsubscribeStaff = subscribeAllStaff(
    (list) => {
      staffCache = list;
      renderStaffTable();
      renderAssignmentTable();
    },
    (error) => {
      console.error("Administration staff listener failed:", error);
      showStaffDataBanner(formatFirestoreError(error, "staff"));
    },
  );
}

tabsEl?.addEventListener("click", (event) => {
  const tab = event.target.closest(".admin-tab");
  if (!tab) return;
  switchTab(tab.dataset.tab);
});

createTypeEl?.addEventListener("change", syncCreateAccountFields);
createFormEl?.addEventListener("submit", handleCreateAccount);
staffTbodyEl?.addEventListener("click", handleStaffTableClick);
assignmentTbodyEl?.addEventListener("click", handleAssignmentTableClick);

createBirthdateEl.max = todayDateString();
syncCreateAccountFields();

initStaffAuth((profile) => {
  if (!isAdmin(profile?.role)) {
    window.location.href = "dashboard.html";
    return;
  }
  startRealtime();
});

window.addEventListener("beforeunload", () => {
  releaseFirestoreListener(unsubscribePatients);
  releaseFirestoreListener(unsubscribeStaff);
});
