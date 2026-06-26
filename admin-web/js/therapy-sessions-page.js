import { initStaffAuth } from "./staff-shell.js";
import { fetchTherapySessionsByUserId, saveTherapySession } from "./appointments-service.js";
import { subscribePatients } from "./user-patients-service.js";
import { filterPatientsForClinicalPages, isAdmin, isTherapist } from "./staff-rbac.js";
import { getStaffSession } from "./staff-auth.js";
import { formatFirestoreError } from "./staff-data-status.js";
import {
  bindPatientAccordionLoader,
  capturePatientAccordionState,
  escapeHtml,
  renderPatientAccordionList,
  restorePatientAccordionState,
  updatePatientAccordionCounts,
} from "./patient-accordion-ui.js";

const accordionListEl = document.getElementById("therapy-sessions-accordion-list");
const countEl = document.getElementById("therapy-sessions-count");
const emptyEl = document.getElementById("therapy-sessions-empty");

const btnAddSession = document.getElementById("btn-add-session");
const modalEl = document.getElementById("add-session-modal");
const closeBtn = document.getElementById("add-session-close");
const formEl = document.getElementById("add-session-form");
const patientSelectEl = document.getElementById("add-session-patient-select");
const appointmentSelectEl = document.getElementById("add-session-appointment-select");
const nameEl = document.getElementById("add-session-name");
const durationEl = document.getElementById("add-session-duration");
const remarksEl = document.getElementById("add-session-remarks");
const statusEl = document.getElementById("add-session-status");
const outcomeEl = document.getElementById("add-session-outcome");
const errorEl = document.getElementById("add-session-error");
const submitBtn = formEl?.querySelector('[type="submit"]');

let loggedInUid = null;
let activeStaffProfile = null;
let patientsRealtimeStarted = false;
let currentAssignedPatients = [];
const sessionCountByPatient = new Map();
let currentTherapySessions = [];

function isTherapyAppointment(session) {
  const type = String(session?.appointmentType || "").toLowerCase();
  return type === "therapy session" || type === "therapist session";
}

async function prefetchSessionCounts(patients) {
  await Promise.all(
    patients.map(async (patient) => {
      try {
        const sessions = await fetchTherapySessionsByUserId(patient.patientId);
        sessionCountByPatient.set(patient.patientId, sessions.length);
      } catch (error) {
        console.warn(`Could not prefetch sessions for ${patient.patientId}:`, error);
      }
    }),
  );
  updatePatientAccordionCounts(accordionListEl, sessionCountByPatient, formatSessionCountLabel);
}

function formatSessionCountLabel(count) {
  return `${count} session${count === 1 ? "" : "s"}`;
}

function renderSessionTable(sessions) {
  if (!sessions.length) {
    return {
      html: `<div class="patient-accordion-empty">No therapy sessions found for this patient.</div>`,
      countLabel: "0 sessions",
    };
  }

  const rows = sessions
    .map(
      (session) => `
        <tr>
          <td>
            <div class="font-medium">${escapeHtml(session.sessionName || "Unnamed Session")}</div>
            <div class="text-sm text-secondary">${escapeHtml(session.datetime || "—")}</div>
          </td>
          <td>${escapeHtml(session.sessionDuration || "—")}</td>
          <td>${escapeHtml(session.sessionRemarks || "—")}</td>
          <td><span class="status-badge">${escapeHtml(session.sessionStatus || "—")}</span></td>
          <td><span class="status-badge">${escapeHtml(session.sessionOutcome || "—")}</span></td>
        </tr>
      `,
    )
    .join("");

  return {
    html: `
      <table class="data-table">
        <thead>
          <tr>
            <th>Session</th>
            <th>Duration</th>
            <th>Remarks</th>
            <th>Status</th>
            <th>Outcome</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    `,
    countLabel: `${sessions.length} session${sessions.length === 1 ? "" : "s"}`,
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
  countEl.textContent = `${currentAssignedPatients.length} patient${currentAssignedPatients.length === 1 ? "" : "s"} — expand a row to view sessions`;

  renderPatientAccordionList({
    containerEl: accordionListEl,
    patients: currentAssignedPatients,
    countSuffix: "sessions",
    getCountLabel: (patient) => {
      const cached = sessionCountByPatient.get(patient.patientId);
      return typeof cached === "number" ? formatSessionCountLabel(cached) : "…";
    },
  });

  restorePatientAccordionState({
    containerEl: accordionListEl,
    openPatientIds,
    loadedPanels,
    onLoadPatient: loadSessionsForPatient,
    countSuffix: "sessions",
  });
}

async function loadSessionsForPatient(patientId) {
  const sessions = (await fetchTherapySessionsByUserId(patientId)).filter(isTherapyAppointment);
  sessionCountByPatient.set(patientId, sessions.length);
  return renderSessionTable(sessions);
}

function populatePatientSelect() {
  patientSelectEl.innerHTML = '<option value="">Choose a patient...</option>';
  currentAssignedPatients.forEach((p) => {
    const opt = document.createElement("option");
    opt.value = p.patientId;
    opt.textContent = `${p.name} (${p.patientId})`;
    patientSelectEl.appendChild(opt);
  });
}

async function populateAppointmentSelect(patientId) {
  appointmentSelectEl.innerHTML = '<option value="">Loading appointments...</option>';
  appointmentSelectEl.disabled = true;
  
  if (!patientId) {
    appointmentSelectEl.innerHTML = '<option value="">Select an appointment...</option>';
    return;
  }

  try {
    const sessions = await fetchTherapySessionsByUserId(patientId);
    currentTherapySessions = sessions;
    
    appointmentSelectEl.innerHTML = '<option value="">Select an appointment...</option>';
    if (sessions.length === 0) {
      appointmentSelectEl.innerHTML = '<option value="">No therapy appointments found</option>';
      return;
    }

    sessions.forEach(session => {
      const opt = document.createElement("option");
      opt.value = session.id;
      opt.textContent = `${session.datetime} - ${session.appointmentType}`;
      appointmentSelectEl.appendChild(opt);
    });
    appointmentSelectEl.disabled = false;
  } catch (error) {
    appointmentSelectEl.innerHTML = '<option value="">Error loading appointments</option>';
  }
}

function openAddModal() {
  errorEl.hidden = true;
  errorEl.textContent = "";
  formEl.reset();
  populatePatientSelect();
  appointmentSelectEl.innerHTML = '<option value="">Select a patient first...</option>';
  appointmentSelectEl.disabled = true;
  modalEl.hidden = false;
  document.body.classList.add("modal-open");
}

function closeAddModal() {
  modalEl.hidden = true;
  document.body.classList.remove("modal-open");
}

btnAddSession?.addEventListener("click", openAddModal);
closeBtn?.addEventListener("click", closeAddModal);

patientSelectEl?.addEventListener("change", (e) => {
  populateAppointmentSelect(e.target.value);
});

appointmentSelectEl?.addEventListener("change", (e) => {
  const selectedId = e.target.value;
  const session = currentTherapySessions.find(s => s.id === selectedId);
  if (session) {
    nameEl.value = session.sessionName || "Mobility Training";
    durationEl.value = session.sessionDuration || "60 minutes";
    remarksEl.value = session.sessionRemarks || "";
    statusEl.value = session.sessionStatus || "";
    outcomeEl.value = session.sessionOutcome || "";
  }
});

formEl?.addEventListener("submit", async (e) => {
  e.preventDefault();
  const appointmentId = appointmentSelectEl.value;
  if (!appointmentId) {
    errorEl.textContent = "Please select an appointment.";
    errorEl.hidden = false;
    return;
  }

  if (submitBtn) submitBtn.disabled = true;
  errorEl.hidden = true;

  try {
    await saveTherapySession(appointmentId, {
      sessionName: nameEl.value.trim(),
      sessionDuration: durationEl.value.trim(),
      sessionRemarks: remarksEl.value.trim(),
      sessionStatus: statusEl.value,
      sessionOutcome: outcomeEl.value
    });
    closeAddModal();
    renderPatientList(); // Refresh accordion list
  } catch (err) {
    errorEl.textContent = formatFirestoreError(err, "session");
    errorEl.hidden = false;
  } finally {
    if (submitBtn) submitBtn.disabled = false;
  }
});

window.addEventListener('error', (event) => {
  if (countEl) countEl.textContent = `JS Error: ${event.message} at ${event.filename}:${event.lineno}`;
});

window.addEventListener('unhandledrejection', (event) => {
  if (countEl) countEl.textContent = `Async Error: ${event.reason}`;
});

bindPatientAccordionLoader({
  containerEl: accordionListEl,
  onLoadPatient: loadSessionsForPatient,
  countSuffix: "sessions",
});

function initializeTherapySessionsPage(profile) {
  if (!profile?.role) return;

  try {
    activeStaffProfile = profile;
    loggedInUid = profile.uid;
    const isAuthorized = isAdmin(profile.role) || isTherapist(profile.role);
    if (btnAddSession) btnAddSession.hidden = !isAuthorized;

    if (!patientsRealtimeStarted) {
      patientsRealtimeStarted = true;
      subscribePatients(
        (patients) => {
          try {
            currentAssignedPatients = filterPatientsForClinicalPages(
              patients,
              activeStaffProfile || profile,
            );
            renderPatientList();
            void prefetchSessionCounts(currentAssignedPatients);
          } catch (err) {
            if (countEl) countEl.textContent = `Render Error: ${err.message}`;
          }
        },
        (error) => {
          if (countEl) countEl.textContent = "Could not load patients";
          if (accordionListEl) accordionListEl.innerHTML = "";
          if (emptyEl) {
            emptyEl.textContent = formatFirestoreError(error, "patients");
            emptyEl.hidden = false;
          }
        },
      );
    } else if (currentAssignedPatients.length > 0) {
      renderPatientList();
    }
  } catch (err) {
    if (countEl) countEl.textContent = `Init Error: ${err.message}`;
  }
}

initStaffAuth(initializeTherapySessionsPage);

const cachedStaffProfile = getStaffSession();
if (cachedStaffProfile?.role) {
  initializeTherapySessionsPage(cachedStaffProfile);
}
