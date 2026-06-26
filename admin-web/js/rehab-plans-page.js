import { initStaffAuth } from "./staff-shell.js";
import { fetchTherapySessionsByUserId, createRehabAppointment } from "./appointments-service.js";
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

const accordionListEl = document.getElementById("rehab-plans-accordion-list");
const countEl = document.getElementById("rehab-plans-count");
const emptyEl = document.getElementById("rehab-plans-empty");

const btnCreatePlan = document.getElementById("btn-create-plan");
const modalEl = document.getElementById("create-plan-modal");
const closeBtn = document.getElementById("create-plan-close");
const formEl = document.getElementById("create-plan-form");
const patientSelectEl = document.getElementById("create-plan-patient-select");
const startEl = document.getElementById("create-plan-start");
const weeksEl = document.getElementById("create-plan-weeks");
const milestonesContainerEl = document.getElementById("create-plan-milestones");
const notesEl = document.getElementById("create-plan-notes");
const errorEl = document.getElementById("create-plan-error");
const submitBtn = formEl?.querySelector('[type="submit"]');

let loggedInUid = null;
let activeStaffProfile = null;
let patientsRealtimeStarted = false;
let currentAssignedPatients = [];
const planCountByPatient = new Map();

function isPlannedRehabSession(session) {
  const status = String(session?.status || "").toLowerCase();
  return status === "scheduled" || status === "pending";
}

function isTherapyAppointment(session) {
  const type = String(session?.appointmentType || "").toLowerCase();
  return type === "therapy session" || type === "therapist session";
}

async function prefetchPlanCounts(patients) {
  await Promise.all(
    patients.map(async (patient) => {
      try {
        const sessions = await fetchTherapySessionsByUserId(patient.patientId);
        const planned = sessions.filter(
          (session) => isTherapyAppointment(session) && isPlannedRehabSession(session),
        );
        planCountByPatient.set(patient.patientId, planned.length);
      } catch (error) {
        console.warn(`Could not prefetch rehab plans for ${patient.patientId}:`, error);
      }
    }),
  );
  updatePatientAccordionCounts(accordionListEl, planCountByPatient, formatPlanCountLabel);
}

function formatPlanCountLabel(count) {
  return `${count} planned session${count === 1 ? "" : "s"}`;
}

function renderPlanTable(sessions) {
  const plannedSessions = sessions.filter(
    (session) => isTherapyAppointment(session) && isPlannedRehabSession(session),
  );
  
  if (!plannedSessions.length) {
    return {
      html: `<div class="patient-accordion-empty">No upcoming rehab plan sessions for this patient.</div>`,
      countLabel: "0 planned sessions",
    };
  }

  const rows = plannedSessions
    .map(
      (session) => `
        <tr>
          <td>
            <div class="font-medium">${escapeHtml(session.sessionName || "Unnamed Session")}</div>
          </td>
          <td>${escapeHtml(session.datetime || "—")}</td>
          <td><span class="text-secondary">${escapeHtml(session.notes || "—")}</span></td>
          <td><span class="status-badge status-badge--warning">${escapeHtml(session.status || "Scheduled")}</span></td>
        </tr>
      `,
    )
    .join("");

  return {
    html: `
      <table class="data-table">
        <thead>
          <tr>
            <th>Milestone / Session</th>
            <th>Scheduled Date</th>
            <th>Notes</th>
            <th>Status</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    `,
    countLabel: `${plannedSessions.length} planned session${plannedSessions.length === 1 ? "" : "s"}`,
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
  countEl.textContent = `${currentAssignedPatients.length} patient${currentAssignedPatients.length === 1 ? "" : "s"} — expand a row to view plans`;

  renderPatientAccordionList({
    containerEl: accordionListEl,
    patients: currentAssignedPatients,
    countSuffix: "planned sessions",
    getCountLabel: (patient) => {
      const cached = planCountByPatient.get(patient.patientId);
      return typeof cached === "number" ? formatPlanCountLabel(cached) : "…";
    },
  });

  restorePatientAccordionState({
    containerEl: accordionListEl,
    openPatientIds,
    loadedPanels,
    onLoadPatient: loadPlansForPatient,
    countSuffix: "planned sessions",
  });
}

async function loadPlansForPatient(patientId) {
  const sessions = await fetchTherapySessionsByUserId(patientId);
  const planned = sessions.filter(
    (session) => isTherapyAppointment(session) && isPlannedRehabSession(session),
  );
  planCountByPatient.set(patientId, planned.length);
  return renderPlanTable(sessions);
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

function syncMilestones() {
  const weeks = parseInt(weeksEl.value, 10) || 4;
  milestonesContainerEl.innerHTML = "";
  
  for (let i = 1; i <= weeks; i++) {
    milestonesContainerEl.insertAdjacentHTML("beforeend", `
      <div class="form-field form-field--inline" style="margin-top: 12px; align-items: center; gap: 12px;">
        <span class="form-field-label" style="min-width: 60px;">Week ${i}</span>
        <input
          class="form-field-input milestone-input"
          type="text"
          id="milestone-week-${i}"
          placeholder="e.g. ${i === 1 ? "Orientation Training" : i === 2 ? "Indoor Navigation" : "Mobility Assessment"}"
          required
        />
      </div>
    `);
  }
}

function openAddModal() {
  errorEl.hidden = true;
  errorEl.textContent = "";
  formEl.reset();
  
  // Set default start date to today
  const today = new Date();
  const yyyy = today.getFullYear();
  const mm = String(today.getMonth() + 1).padStart(2, '0');
  const dd = String(today.getDate()).padStart(2, '0');
  startEl.value = `${yyyy}-${mm}-${dd}`;
  
  populatePatientSelect();
  syncMilestones();
  
  modalEl.hidden = false;
  document.body.classList.add("modal-open");
}

function closeAddModal() {
  modalEl.hidden = true;
  document.body.classList.remove("modal-open");
}

btnCreatePlan?.addEventListener("click", openAddModal);
closeBtn?.addEventListener("click", closeAddModal);
weeksEl?.addEventListener("input", syncMilestones);

formEl?.addEventListener("submit", async (e) => {
  e.preventDefault();
  
  const patientId = patientSelectEl.value;
  if (!patientId) {
    errorEl.textContent = "Please select a patient.";
    errorEl.hidden = false;
    return;
  }

  if (submitBtn) submitBtn.disabled = true;
  errorEl.hidden = true;

  try {
    const startDate = new Date(startEl.value);
    const weeks = parseInt(weeksEl.value, 10) || 4;
    const notes = notesEl.value.trim();
    
    // Create an appointment for each week
    for (let i = 1; i <= weeks; i++) {
      const milestoneInput = document.getElementById(`milestone-week-${i}`);
      const sessionName = milestoneInput ? milestoneInput.value.trim() : `Week ${i} Session`;
      
      const sessionDate = new Date(startDate);
      // Add exactly 7 days per week (Week 1 = start date, Week 2 = +7 days, Week 3 = +14 days...)
      sessionDate.setDate(sessionDate.getDate() + ((i - 1) * 7));
      // Default to 9:00 AM
      sessionDate.setHours(9, 0, 0, 0);
      
      await createRehabAppointment({
        patientId,
        staffId: loggedInUid,
        dateTime: sessionDate,
        sessionName,
        notes: notes
      });
    }
    
    closeAddModal();
    renderPatientList(); // Refresh accordion list
  } catch (err) {
    errorEl.textContent = formatFirestoreError(err, "rehab plan");
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
  onLoadPatient: loadPlansForPatient,
  countSuffix: "planned sessions",
});

function initializeRehabPlansPage(profile) {
  if (!profile?.role) return;

  try {
    activeStaffProfile = profile;
    loggedInUid = profile.uid;
    const isAuthorized = isAdmin(profile.role) || isTherapist(profile.role);
    if (btnCreatePlan) btnCreatePlan.hidden = !isAuthorized;

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
            void prefetchPlanCounts(currentAssignedPatients);
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

initStaffAuth(initializeRehabPlansPage);

const cachedStaffProfile = getStaffSession();
if (cachedStaffProfile?.role) {
  initializeRehabPlansPage(cachedStaffProfile);
}
