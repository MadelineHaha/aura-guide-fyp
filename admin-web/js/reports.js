import { initStaffAuth, getInitials } from "./staff-shell.js";
import { fetchReportsData, REPORT_RANGES } from "./reports-service.js";

const errorEl = document.getElementById("reports-error");
const userActivityBodyEl = document.getElementById("user-activity-body");
const userActivityCountEl = document.getElementById("user-activity-count");
const outcomesBodyEl = document.getElementById("health-outcomes-body");
const baselineColEl = document.getElementById("outcomes-baseline-col");
const latestColEl = document.getElementById("outcomes-latest-col");
const filterTabs = document.querySelectorAll(".filter-tabs .filter-tab");
const exportCsvBtn = document.getElementById("btn-export-csv");
const exportPdfBtn = document.getElementById("btn-export-pdf");

const emergencyTotalAlertsEl = document.getElementById("emergency-total-alerts");
const emergencyRespondedEl = document.getElementById("emergency-responded");
const emergencyResolvedEl = document.getElementById("emergency-resolved");
const emergencyAvgResponseEl = document.getElementById("emergency-avg-response");

const healthTrendCanvas = document.getElementById("health-trend-chart");
const emergencyBarCanvas = document.getElementById("emergency-bar-chart");

const MAX_STEPS_SCALE = 10000;
let currentRangeKey = REPORT_RANGES.ALL;
let latestReport = null;
let loading = false;

let healthTrendChart = null;
let emergencyBarChart = null;

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function parseRangeKey(raw) {
  const num = Number(raw);
  if (Number.isNaN(num)) return REPORT_RANGES.ALL;
  return num;
}

function formatNumber(value) {
  return Number(value || 0).toLocaleString("en-US");
}

function stepsBarWidth(steps, scale = MAX_STEPS_SCALE) {
  const pct = Math.min(100, Math.round((steps / scale) * 100));
  return Math.max(steps > 0 ? 6 : 0, pct);
}

function medAdherenceClass(value) {
  if (value >= 85) return "reports-metric--good";
  return "reports-metric--warn";
}

function appointmentBadgeClass(rate) {
  if (rate >= 80) return "reports-appt-badge--good";
  return "reports-appt-badge--low";
}

function renderUserActivity(rows) {
  if (!userActivityBodyEl) return;

  if (!rows.length) {
    userActivityBodyEl.innerHTML =
      '<tr><td colspan="5" class="table-empty">No patient activity in this range.</td></tr>';
    return;
  }

  const stepScale = Math.max(MAX_STEPS_SCALE, ...rows.map((row) => row.avgSteps), 1);

  userActivityBodyEl.innerHTML = rows
    .map((row) => {
      const initials = escapeHtml(getInitials(row.name));
      const medClass = medAdherenceClass(row.medAdherence);
      const medWarn =
        row.medAdherence < 85
          ? '<svg class="reports-warn-icon" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z"/></svg>'
          : "";
      const apptBadgeClass = appointmentBadgeClass(row.appointmentRate);
      const barWidth = stepsBarWidth(row.avgSteps, stepScale);
      const apptTotal = row.appointmentsTotal || 0;
      const apptAttended = row.appointmentsAttended || 0;
      const apptLabel = apptTotal > 0 ? `${apptAttended}/${apptTotal}` : "0/0";

      return `
        <tr>
          <td>
            <div class="reports-patient-cell">
              <span class="reports-patient-avatar" aria-hidden="true">${initials}</span>
              <div class="reports-patient-meta">
                <p class="cell-primary">${escapeHtml(row.name)}</p>
                <p class="cell-secondary">${escapeHtml(row.patientId)}</p>
              </div>
            </div>
          </td>
          <td>
            <div class="reports-steps-cell">
              <span class="reports-steps-value">${formatNumber(row.avgSteps)}</span>
              <div class="reports-steps-track" aria-hidden="true">
                <span class="reports-steps-bar" style="width:${barWidth}%"></span>
              </div>
            </div>
          </td>
          <td>
            <span class="reports-metric ${medClass}">
              ${medWarn}
              <span>${row.medAdherence}%</span>
            </span>
          </td>
          <td>
            <div class="reports-appt-cell">
              <span class="reports-appt-ratio">${apptLabel}</span>
              <span class="reports-appt-badge ${apptBadgeClass}">${row.appointmentRate}%</span>
            </div>
          </td>
          <td class="reports-last-active">${escapeHtml(row.lastActive)}</td>
        </tr>
      `;
    })
    .join("");
}

function destroyCharts() {
  if (healthTrendChart) {
    healthTrendChart.destroy();
    healthTrendChart = null;
  }
  if (emergencyBarChart) {
    emergencyBarChart.destroy();
    emergencyBarChart = null;
  }
}

function renderHealthTrendChart(trend) {
  if (!healthTrendCanvas || !window.Chart) return;
  if (healthTrendChart) {
    healthTrendChart.destroy();
    healthTrendChart = null;
  }

  healthTrendChart = new Chart(healthTrendCanvas, {
    type: "line",
    data: {
      labels: trend.labels,
      datasets: [
        {
          label: "Med. Adherence (%)",
          data: trend.medSeries,
          borderColor: "#4caf7d",
          backgroundColor: "rgba(76, 175, 125, 0.12)",
          tension: 0.35,
          fill: false,
          pointRadius: 4,
        },
        {
          label: "Appt. Rate (%)",
          data: trend.apptSeries,
          borderColor: "#6bc4c4",
          backgroundColor: "rgba(107, 196, 196, 0.12)",
          tension: 0.35,
          fill: false,
          pointRadius: 4,
        },
        {
          label: "Avg Steps (x100)",
          data: trend.stepsSeries,
          borderColor: "#6b9fd4",
          backgroundColor: "rgba(107, 159, 212, 0.12)",
          tension: 0.35,
          fill: false,
          pointRadius: 4,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          position: "bottom",
          labels: { boxWidth: 12, usePointStyle: true },
        },
      },
      scales: {
        y: {
          beginAtZero: true,
          max: 100,
          grid: { color: "#eef1f3" },
        },
        x: {
          grid: { display: false },
        },
      },
    },
  });
}

function renderEmergencyChart(emergency) {
  if (!emergencyBarCanvas || !window.Chart) return;

  if (emergencyBarChart) {
    emergencyBarChart.destroy();
    emergencyBarChart = null;
  }

  emergencyBarChart = new Chart(emergencyBarCanvas, {
    type: "bar",
    data: {
      labels: emergency.monthly.map((row) => row.label),
      datasets: [
        {
          label: "Alerts",
          data: emergency.monthly.map((row) => row.alerts),
          backgroundColor: "#e03131",
          borderRadius: 4,
        },
        {
          label: "Responded",
          data: emergency.monthly.map((row) => row.responded),
          backgroundColor: "#fd7e14",
          borderRadius: 4,
        },
        {
          label: "Resolved",
          data: emergency.monthly.map((row) => row.resolved),
          backgroundColor: "#2f9e44",
          borderRadius: 4,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          position: "bottom",
          labels: { boxWidth: 12, usePointStyle: true },
        },
      },
      scales: {
        y: {
          beginAtZero: true,
          ticks: { precision: 0 },
          grid: { color: "#eef1f3" },
        },
        x: {
          grid: { display: false },
        },
      },
    },
  });
}

function improvementBadge(row) {
  if (row.changePct == null) return "—";
  const sign = row.changePct > 0 ? "+" : "";
  const tone = row.positive ? "reports-improvement--positive" : "reports-improvement--negative";
  const arrow = row.changePct >= 0 ? "↑" : "↓";
  return `<span class="reports-improvement ${tone}">${arrow} ${sign}${row.changePct}%</span>`;
}

function renderHealthOutcomes(outcomes) {
  if (!outcomesBodyEl) return;

  if (baselineColEl) {
    baselineColEl.textContent = `${outcomes.baselineLabel} (Baseline)`;
  }
  if (latestColEl) {
    latestColEl.textContent = `${outcomes.latestLabel} (Latest)`;
  }

  outcomesBodyEl.innerHTML = outcomes.rows
    .map(
      (row) => `
        <tr>
          <td class="cell-primary">${escapeHtml(row.metric)}</td>
          <td>${escapeHtml(row.baselineText)}</td>
          <td>${escapeHtml(row.latestText)}</td>
          <td>${improvementBadge(row)}</td>
        </tr>
      `,
    )
    .join("");
}

function renderReport(report) {
  latestReport = report;

  if (userActivityCountEl) {
    const count = report.patientCount;
    userActivityCountEl.textContent = `${count} patient${count === 1 ? "" : "s"}`;
  }

  renderUserActivity(report.userActivity);

  if (emergencyTotalAlertsEl) emergencyTotalAlertsEl.textContent = String(report.emergency.totals.alerts);
  if (emergencyRespondedEl) emergencyRespondedEl.textContent = String(report.emergency.totals.responded);
  if (emergencyResolvedEl) emergencyResolvedEl.textContent = String(report.emergency.totals.resolved);
  if (emergencyAvgResponseEl) {
    emergencyAvgResponseEl.textContent = `${report.emergency.totals.avgResponseMin} min`;
  }

  renderHealthTrendChart(report.healthTrend);
  renderEmergencyChart(report.emergency);
  renderHealthOutcomes(report.outcomes);

  if (errorEl) errorEl.hidden = true;
}

async function loadReports() {
  if (loading) return;
  loading = true;

  try {
    const report = await fetchReportsData(currentRangeKey);
    renderReport(report);

    if (errorEl && report.warnings?.length) {
      errorEl.hidden = false;
      errorEl.textContent = `Some optional data could not be loaded (${report.warnings.join(", ")}). Charts may be incomplete until Firestore rules are deployed.`;
    }
  } catch (error) {
    console.error("Reports load failed:", error);
    if (errorEl) {
      errorEl.hidden = false;
      const code = error?.code || "";
      if (code === "permission-denied") {
        errorEl.textContent =
          "Could not load report data. Deploy Firestore rules: firebase deploy --only firestore:rules";
      } else {
        errorEl.textContent = error?.message || "Could not load report data.";
      }
    }
  } finally {
    loading = false;
  }
}

function setActiveRangeTab(rangeKey) {
  filterTabs.forEach((tab) => {
    const key = parseRangeKey(tab.dataset.range);
    tab.classList.toggle("is-active", key === rangeKey);
  });
}

function exportCsv() {
  if (!latestReport?.userActivity?.length) return;

  const header = [
    "Patient Name",
    "User ID",
    "Avg Steps/Day",
    "Med Adherence %",
    "Appointments Attended",
    "Appointments Total",
    "Appointment Rate %",
    "Last Active",
  ];
  const lines = latestReport.userActivity.map((row) => [
    row.name,
    row.patientId,
    row.avgSteps,
    row.medAdherence,
    row.appointmentsAttended,
    row.appointmentsTotal,
    row.appointmentRate,
    row.lastActive,
  ]);

  const csv = [header, ...lines]
    .map((line) =>
      line
        .map((cell) => `"${String(cell ?? "").replace(/"/g, '""')}"`)
        .join(","),
    )
    .join("\n");

  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `aura-guide-user-activity-${new Date().toISOString().slice(0, 10)}.csv`;
  link.click();
  URL.revokeObjectURL(url);
}

function exportPdf() {
  window.print();
}

filterTabs.forEach((tab) => {
  tab.addEventListener("click", () => {
    const rangeKey = parseRangeKey(tab.dataset.range);
    if (rangeKey === currentRangeKey) return;
    currentRangeKey = rangeKey;
    setActiveRangeTab(rangeKey);
    loadReports();
  });
});

exportCsvBtn?.addEventListener("click", exportCsv);
exportPdfBtn?.addEventListener("click", exportPdf);

window.addEventListener("pagehide", () => {
  destroyCharts();
});

initStaffAuth(() => {
  loadReports();
});
