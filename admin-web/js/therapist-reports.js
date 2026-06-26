import { initStaffAuth } from "./staff-shell.js";
import { fetchAppointments } from "./appointments-service.js";
import { subscribePatients } from "./user-patients-service.js";
import { filterPatientsForClinicalPages, isAdmin, isTherapist } from "./staff-rbac.js";

const conductedEl = document.getElementById("activity-conducted");
const completedEl = document.getElementById("activity-completed");
const cancelledEl = document.getElementById("activity-cancelled");
const noshowEl = document.getElementById("activity-noshow");

const improvedEl = document.getElementById("progress-improved");
const stableEl = document.getElementById("progress-stable");
const trainingEl = document.getElementById("progress-training");

let activityChart = null;
let progressChart = null;

let loggedInUid = null;
let currentPatients = [];

async function loadReports() {
  const allAppointments = await fetchAppointments();
  
  // Filter for Therapy Sessions assigned to this therapist
  // For Admin, maybe we show all therapy sessions? Let's just show all if Admin, or filter by therapist if Therapist.
  const therapistSessions = allAppointments.filter(appt => 
    (appt.appointmentType === "Therapy Session" || appt.appointmentType === "Therapist Session") &&
    (isAdmin(loggedInRole) || appt.staffId === loggedInUid)
  );

  // 1. Therapy Activity Report
  let conducted = 0;
  let completed = 0;
  let cancelled = 0;
  let noshow = 0;

  therapistSessions.forEach(session => {
    const status = (session.status || "").toLowerCase();
    if (status === "done" || status === "completed") {
      conducted++;
      completed++;
    } else if (status === "cancelled") {
      cancelled++;
    } else if (status === "missed" || status === "no-show") {
      noshow++;
    }
  });

  conductedEl.textContent = conducted;
  completedEl.textContent = completed;
  cancelledEl.textContent = cancelled;
  noshowEl.textContent = noshow;

  renderActivityChart([completed, cancelled, noshow]);

  // 2. Rehabilitation Progress Report
  // Group by patient to find their latest session status
  const latestStatusByPatient = new Map();
  
  // therapistSessions are ordered by dateTime ascending (from fetchAppointments)
  therapistSessions.forEach(session => {
    const status = (session.status || "").toLowerCase();
    if ((status === "done" || status === "completed") && session.sessionStatus) {
      latestStatusByPatient.set(session.patientId, session.sessionStatus);
    }
  });

  let improved = 0;
  let stable = 0;
  let training = 0;

  latestStatusByPatient.forEach(status => {
    if (status === "Improved") improved++;
    else if (status === "Stable") stable++;
    else if (status === "Requiring Additional Training") training++;
  });

  improvedEl.textContent = improved;
  stableEl.textContent = stable;
  trainingEl.textContent = training;

  renderProgressChart([improved, stable, training]);
}

function renderActivityChart(data) {
  const ctx = document.getElementById("therapy-activity-chart");
  if (!ctx) return;
  
  if (activityChart) {
    activityChart.destroy();
  }

  activityChart = new Chart(ctx, {
    type: 'bar',
    data: {
      labels: ['Completed', 'Cancelled', 'No-show'],
      datasets: [{
        label: 'Sessions',
        data: data,
        backgroundColor: [
          '#6bc4c4',
          '#f87171',
          '#fbbf24'
        ],
        borderWidth: 0,
        borderRadius: 4
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false }
      },
      scales: {
        y: { beginAtZero: true, ticks: { stepSize: 1 } }
      }
    }
  });
}

function renderProgressChart(data) {
  const ctx = document.getElementById("rehab-progress-chart");
  if (!ctx) return;
  
  if (progressChart) {
    progressChart.destroy();
  }

  progressChart = new Chart(ctx, {
    type: 'doughnut',
    data: {
      labels: ['Improved', 'Stable', 'Requiring Training'],
      datasets: [{
        data: data,
        backgroundColor: [
          '#10b981', // success
          '#f59e0b', // warning
          '#ef4444'  // danger
        ],
        borderWidth: 0
      }]
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { position: 'right' }
      }
    }
  });
}

let loggedInRole = "";

initStaffAuth(
  (profile) => {
    loggedInUid = profile.uid;
    loggedInRole = profile.role;
    
    subscribePatients(
      (patients) => {
        currentPatients = filterPatientsForClinicalPages(patients, profile);
        loadReports();
      },
      (error) => {
        console.error("Failed to load patients for reports", error);
      }
    );
  },
  { enforceAccess: true }
);
