const fs = require('fs');

let code = fs.readFileSync('admin-web/js/dashboard.js', 'utf8');

// Add imports
const imports = `import { collection, getDocs, query, where } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { MEDICATION_REMINDERS_COLLECTION } from "./medications-service.js";`;

code = imports + "\n" + code;

// Add medication adherence logic
const adherenceLogic = `
const adherenceTimeframeEl = document.getElementById("medication-adherence-timeframe");
if (adherenceTimeframeEl) {
  adherenceTimeframeEl.addEventListener("change", () => {
    renderMedicationAdherenceAlerts();
  });
}

function getTimeframeStart(timeframe) {
  const now = new Date();
  if (timeframe === "today") {
    return new Date(now.getFullYear(), now.getMonth(), now.getDate());
  }
  if (timeframe === "month") {
    return new Date(now.getFullYear(), now.getMonth(), 1);
  }
  return new Date(0); // all time
}

window.contactCaregiverOrPatient = function(patientId, caregiverId) {
  // Store routing information in sessionStorage so communication page knows to select them
  if (caregiverId && caregiverId !== "none") {
    sessionStorage.setItem("pending_chat_user", caregiverId);
  } else if (patientId) {
    sessionStorage.setItem("pending_chat_user", patientId);
  }
  window.location.href = "communication.html";
};

async function renderMedicationAdherenceAlerts() {
  const listEl = document.getElementById("medication-alerts-list");
  const emptyEl = document.getElementById("medication-alerts-empty");
  const timeframeEl = document.getElementById("medication-adherence-timeframe");
  
  if (!listEl || !emptyEl || !timeframeEl) return;
  
  const timeframe = timeframeEl.value;
  const startDate = getTimeframeStart(timeframe);
  const startDoseDateStr = startDate.toISOString().split("T")[0]; // YYYY-MM-DD
  
  // We only look at active patients
  const activePatients = patientsCache.filter(p => String(p.status || "").trim() === "Active");
  
  if (activePatients.length === 0) {
    listEl.innerHTML = "";
    emptyEl.hidden = false;
    emptyEl.textContent = "No active patients.";
    return;
  }
  
  listEl.innerHTML = "<p style='padding: 12px; color: var(--gray-600);'>Loading alerts...</p>";
  emptyEl.hidden = true;
  
  try {
    const alerts = [];
    
    // We could do a collectionGroup query or fetch individually.
    // For small sets, fetching per patient or fetching all reminders is an option.
    // Given no composite index is guaranteed, let's fetch all reminders for the active patients where doseDate >= startDoseDateStr?
    // Firestore requires index on doseDate. Better to just fetch all reminders or query individually.
    // To be safe and avoid index errors, we'll query by medicationId. But we don't have medicationId easily available.
    // Wait, let's query all medicationreminders and group in memory if it's small, or query by userId.
    
    // Let's query collection("medicationreminders") without where() to avoid missing indexes, then filter.
    // Or query by userId for each patient (requires many reads).
    // Let's just do getDocs on the collection if it's not huge.
    const remindersSnap = await getDocs(collection(db, MEDICATION_REMINDERS_COLLECTION));
    
    const remindersByUser = {};
    remindersSnap.forEach(doc => {
      const data = doc.data();
      const uId = String(data.userId || data.userID || "").trim();
      const dose = String(data.doseDate || "").trim();
      if (!uId || !dose) return;
      
      // Filter by timeframe
      if (dose < startDoseDateStr) return;
      
      if (!remindersByUser[uId]) remindersByUser[uId] = { totalPast: 0, completed: 0 };
      
      const status = String(data.status || "").trim();
      if (status === "Completed") {
        remindersByUser[uId].totalPast++;
        remindersByUser[uId].completed++;
      } else if (status === "Missed") {
        remindersByUser[uId].totalPast++;
      }
    });
    
    for (const patient of activePatients) {
      const stats = remindersByUser[patient.patientId];
      if (!stats || stats.totalPast === 0) continue;
      
      const adherence = (stats.completed / stats.totalPast) * 100;
      if (adherence < 100) {
        alerts.push({
          patient,
          adherence: Math.round(adherence)
        });
      }
    }
    
    if (alerts.length === 0) {
      listEl.innerHTML = "";
      emptyEl.hidden = false;
      emptyEl.textContent = "No medication adherence alerts.";
      return;
    }
    
    emptyEl.hidden = true;
    listEl.innerHTML = alerts.map(alert => {
      const p = alert.patient;
      const cgName = p.assignedCaregiverName ? escapeHtml(p.assignedCaregiverName) : "None";
      const cgId = p.assignedCaregiverId || "none";
      const btnText = cgId !== "none" ? "Contact Caregiver" : "Contact Patient";
      
      return \`
        <li class="attention-item" style="display:flex; justify-content:space-between; align-items:center; padding:12px; border-bottom:1px solid var(--border-color);">
          <div>
            <p style="margin:0; font-weight:600;">\${escapeHtml(p.name)} <span style="font-size:0.85em;color:var(--gray-500);font-weight:normal;">(\${escapeHtml(p.patientId)})</span></p>
            <p style="margin:4px 0 0; color:var(--gray-600); font-size:0.875rem;">Adherence: <span style="font-weight:600; color:var(--critical-color);">\${alert.adherence}%</span> &middot; Caregiver: \${cgName}</p>
          </div>
          <button type="button" class="btn-secondary btn-sm" onclick="window.contactCaregiverOrPatient('\${escapeHtml(p.patientId)}', '\${escapeHtml(cgId)}')">\${btnText}</button>
        </li>
      \`;
    }).join("");
    
  } catch (err) {
    console.error("Error generating adherence alerts", err);
    listEl.innerHTML = "";
    emptyEl.hidden = false;
    emptyEl.textContent = "Failed to load alerts.";
  }
}
`;

// Insert the new logic before `function applyRoleLayout`
code = code.replace(/function applyRoleLayout\(\) \{/, adherenceLogic + "\nfunction applyRoleLayout() {");

// Add call to renderMedicationAdherenceAlerts in `renderStaffDashboard`
code = code.replace(/renderAdminTodayAppointmentsList\(\);\n  renderAdminAppointmentDonut\(\);/g, "renderAdminTodayAppointmentsList();\n  renderAdminAppointmentDonut();\n  renderMedicationAdherenceAlerts();");
code = code.replace(/renderTodayAppointmentsList\(staffTodayListEl, staffTodayEmptyEl, appointmentsCache\);/g, "renderTodayAppointmentsList(staffTodayListEl, staffTodayEmptyEl, appointmentsCache);\n  renderMedicationAdherenceAlerts();");

fs.writeFileSync('admin-web/js/dashboard.js', code);
console.log("Successfully injected medication adherence alerts logic");
