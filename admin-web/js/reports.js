import { initStaffAuth, getInitials } from "./staff-shell.js";
import { formatFirestoreError } from "./staff-data-status.js";
import { isAdmin } from "./staff-rbac.js";
import { fetchReportsData, MED_ADHERENCE_STATUS, REPORT_RANGES } from "./reports-service.js";

const errorEl = document.getElementById("reports-error");
const filterTabs = document.querySelectorAll(".filter-tabs .filter-tab");
const exportCsvBtn = document.getElementById("btn-export-csv");
const exportPdfBtn = document.getElementById("btn-export-pdf");

const emergencyTotalAlertsEl = document.getElementById("emergency-total-alerts");
const emergencyRespondedEl = document.getElementById("emergency-responded");
const emergencyResolvedEl = document.getElementById("emergency-resolved");
const emergencyAvgResponseEl = document.getElementById("emergency-avg-response");

const patientGrowthTotalEl = document.getElementById("patient-growth-total");
const staffGrowthTotalEl = document.getElementById("staff-growth-total");
const doctorGrowthTotalEl = document.getElementById("doctor-growth-total");
const therapistGrowthTotalEl = document.getElementById("therapist-growth-total");
const caregiverGrowthTotalEl = document.getElementById("caregiver-growth-total");
const appointmentAttendanceRateEl = document.getElementById("appointment-attendance-rate");
const appointmentMissedRateEl = document.getElementById("appointment-missed-rate");
const appointmentTotalScheduledEl = document.getElementById("appointment-total-scheduled");
const emergencyResolutionRateEl = document.getElementById("emergency-resolution-rate");

const emergencyBarCanvas = document.getElementById("emergency-bar-chart");
const patientGrowthCanvas = document.getElementById("patient-growth-chart");
const appointmentReportsCanvas = document.getElementById("appointment-reports-chart");

const MAX_STEPS_SCALE = 10000;
let currentRangeKey = REPORT_RANGES.ALL;
let currentGrouping = "monthly";
let latestReport = null;
let loading = false;

let emergencyBarChart = null;
let patientGrowthChart = null;
let appointmentReportsChart = null;

const CHART_LEGEND_PRINT = {
  display: false,
};

const GROWTH_SERIES = [
  { label: "Patients", color: "#00897B", dash: [], pointStyle: "circle", style: "solid" },
  { label: "Doctors", color: "#1565C0", dash: [], pointStyle: "triangle", style: "solid" },
  { label: "Therapists", color: "#8E24AA", dash: [], pointStyle: "rect", style: "solid" },
  { label: "Caregivers", color: "#E65100", dash: [], pointStyle: "rectRot", style: "solid" },
];

const APPOINTMENT_SERIES = [
  { label: "Attendance Rate (%)", color: "#2b8a3e", dash: [], pointStyle: "circle", style: "solid" },
  { label: "Missed Appointment Rate (%)", color: "#e03131", dash: [], pointStyle: "triangle", style: "solid" },
];

const EMERGENCY_BAR_SERIES = [
  { label: "Alerts", color: "#e03131", style: "bar" },
  { label: "Responded", color: "#fd7e14", style: "bar" },
  { label: "Resolved", color: "#2f9e44", style: "bar" },
];

const REPORT_LINE_LAYOUT = {
  padding: { top: 10, right: 132, bottom: 20, left: 4 },
};

const LINE_CHART_ELEMENTS = {
  line: { clip: false },
  point: { clip: false },
};

function yScaleWithZeroPadding(extra = {}) {
  return {
    beginAtZero: true,
    min: 0,
    grace: 0,
    grid: { color: "#eef1f3" },
    afterFit(scale) {
      scale.paddingBottom = 18;
    },
    ...extra,
  };
}

const END_LABEL_GAP_X = 20;
const END_LABEL_SPREAD_Y = 16;

const REPORT_END_LABELS_PLUGIN = {
  id: "reportEndLabels",
  afterDatasetsDraw(chart) {
    const pluginOpts = chart.options.plugins?.reportEndLabels;
    if (pluginOpts?.enabled === false) return;

    const { ctx, chartArea } = chart;
    const metas = chart.getSortedVisibleDatasetMetas().filter((meta) => meta.type === "line");
    if (!metas.length) return;

    const lastIndex = chart.data.labels.length - 1;
    if (lastIndex < 0) return;

    const entries = [];
    for (const meta of metas) {
      const dataset = chart.data.datasets[meta.index];
      const point = meta.data[lastIndex];
      if (!point || point.skip) continue;
      const rawValue = dataset.data[lastIndex];
      const labelText = dataset.endLabel || dataset.label;
      entries.push({
        x: point.x,
        y: point.y,
        text: `${labelText} (${rawValue})`,
        color: dataset.borderColor,
        value: Number(rawValue),
      });
    }

    const groups = new Map();
    for (const entry of entries) {
      const key = String(entry.value);
      if (!groups.has(key)) groups.set(key, []);
      groups.get(key).push(entry);
    }

    for (const group of groups.values()) {
      const start = -((group.length - 1) * END_LABEL_SPREAD_Y) / 2;
      group.forEach((entry, index) => {
        entry.offsetY = group.length > 1 ? start + index * END_LABEL_SPREAD_Y : 0;
      });
    }

    ctx.save();
    ctx.font = "600 10px Inter, sans-serif";
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    for (const entry of entries) {
      const textX = Math.min(entry.x + END_LABEL_GAP_X, chartArea.right - 2);
      const textY = entry.y + (entry.offsetY || 0);
      ctx.lineWidth = 3;
      ctx.strokeStyle = "#ffffff";
      ctx.strokeText(entry.text, textX, textY);
      ctx.fillStyle = entry.color;
      ctx.fillText(entry.text, textX, textY);
    }
    ctx.restore();
  },
};

let chartPluginsRegistered = false;

function ensureChartPlugins() {
  if (!window.Chart || chartPluginsRegistered) return;
  window.Chart.register(REPORT_END_LABELS_PLUGIN);
  chartPluginsRegistered = true;
}

function buildLineDataset(series, data) {
  return {
    label: series.label,
    endLabel: series.endLabel || series.label,
    data,
    clip: false,
    borderColor: series.color,
    backgroundColor: series.color,
    borderWidth: 3,
    borderDash: series.dash,
    tension: 0.35,
    pointRadius: 5,
    pointHoverRadius: 7,
    pointStyle: series.pointStyle,
    pointBackgroundColor: series.color,
    pointBorderColor: "#ffffff",
    pointBorderWidth: 2,
  };
}

function renderChartKey(elementId, items) {
  const el = document.getElementById(elementId);
  if (!el) return;

  el.innerHTML = items
    .map(
      (item) => `
        <li class="reports-chart-key-item">
          <svg class="reports-chart-key-dot" width="12" height="12" viewBox="0 0 12 12" aria-hidden="true">
            <circle cx="6" cy="6" r="5.5" fill="${item.color}" stroke="rgba(0,0,0,0.12)" stroke-width="0.6"></circle>
          </svg>
          <span class="reports-chart-key-label">${escapeHtml(item.label)}</span>
        </li>`,
    )
    .join("");
}

function seriesOverlapAtLastPoint(dataArrays) {
  if (!dataArrays.length) return false;
  const lastIndex = dataArrays[0].length - 1;
  if (lastIndex < 0) return false;
  const values = dataArrays.map((series) => series[lastIndex]);
  return new Set(values.map(String)).size < values.length;
}

function setOverlapNote(elementId, visible) {
  const el = document.getElementById(elementId);
  if (el) el.hidden = !visible;
}

const LINE_CHART_PLUGINS = {
  legend: CHART_LEGEND_PRINT,
  reportEndLabels: { enabled: true },
};

function allReportCharts() {
  return [patientGrowthChart, appointmentReportsChart, emergencyBarChart].filter(Boolean);
}

function getActiveRangeLabel() {
  const activeTab = document.querySelector(".reports-filters .filter-tab.is-active");
  return activeTab?.textContent?.trim() || "All Time";
}

function prepareChartsForPrint() {
  for (const chart of allReportCharts()) {
    chart.options.animation = false;
    if (chart.options.plugins?.reportEndLabels) {
      chart.options.plugins.reportEndLabels.enabled = true;
    }
    chart.update("none");
    chart.resize();
  }
}

function updatePrintHeader() {
  const metaEl = document.getElementById("reports-print-meta");
  if (!metaEl) return;

  const generated = new Date().toLocaleString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
  metaEl.textContent = `Generated ${generated} · Range: ${getActiveRangeLabel()}`;
}

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

function medAdherenceBadgeClass(status, percent) {
  if (status === MED_ADHERENCE_STATUS.NA) return "reports-med-badge--na";
  if (status === MED_ADHERENCE_STATUS.PENDING) return "reports-med-badge--pending";
  const value = Number(percent ?? 0);
  if (value >= 90) return "reports-med-badge--good";
  if (value >= 60) return "reports-med-badge--medium";
  return "reports-med-badge--low";
}

function medAdherenceLabel(status, percent) {
  if (status === MED_ADHERENCE_STATUS.NA) return "No Medication Assigned";
  if (status === MED_ADHERENCE_STATUS.PENDING) return "Not Due Yet";
  return `${Number(percent ?? 0)}%`;
}

function renderMedAdherenceBadge(row) {
  const status = row.medAdherenceStatus || MED_ADHERENCE_STATUS.CALCULATED;
  const badgeClass = medAdherenceBadgeClass(status, row.medAdherence);
  const label = medAdherenceLabel(status, row.medAdherence);
  return `<span class="reports-med-badge ${badgeClass}">${escapeHtml(label)}</span>`;
}

function appointmentBadgeClass(rate) {
  if (rate >= 80) return "reports-appt-badge--good";
  return "reports-appt-badge--low";
}

function destroyCharts() {
  if (emergencyBarChart) {
    emergencyBarChart.destroy();
    emergencyBarChart = null;
  }
  if (patientGrowthChart) {
    patientGrowthChart.destroy();
    patientGrowthChart = null;
  }
  if (appointmentReportsChart) {
    appointmentReportsChart.destroy();
    appointmentReportsChart = null;
  }
}

function renderPatientGrowthChart(growth) {
  if (!patientGrowthCanvas || !window.Chart) return;
  ensureChartPlugins();
  if (patientGrowthChart) {
    patientGrowthChart.destroy();
    patientGrowthChart = null;
  }

  const allSeries = [
    ...growth.patientGrowth,
    ...growth.doctorGrowth,
    ...growth.therapistGrowth,
    ...growth.caregiverGrowth,
  ];
  const yMax = Math.max(5, ...allSeries, 1);
  const growthData = [
    growth.patientGrowth,
    growth.doctorGrowth,
    growth.therapistGrowth,
    growth.caregiverGrowth,
  ];

  patientGrowthChart = new Chart(patientGrowthCanvas, {
    type: "line",
    data: {
      labels: growth.labels,
      datasets: GROWTH_SERIES.map((series, index) => buildLineDataset(series, growthData[index])),
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      layout: REPORT_LINE_LAYOUT,
      elements: LINE_CHART_ELEMENTS,
      plugins: LINE_CHART_PLUGINS,
      scales: {
        y: yScaleWithZeroPadding({
          type: "linear",
          suggestedMax: yMax,
          ticks: { precision: 0 },
          title: { display: true, text: "Total registered" },
        }),
        x: {
          offset: true,
          grid: { display: false },
          ticks: { padding: 12 },
        },
      },
    },
  });

  renderChartKey("patient-growth-chart-key", GROWTH_SERIES);
  setOverlapNote(
    "patient-growth-overlap-note",
    seriesOverlapAtLastPoint(growthData),
  );
}

function renderAppointmentReportsChart(reports) {
  if (!appointmentReportsCanvas || !window.Chart) return;
  ensureChartPlugins();
  if (appointmentReportsChart) {
    appointmentReportsChart.destroy();
    appointmentReportsChart = null;
  }

  const attendanceData = reports.monthly.map((row) => row.attendanceRate);
  const missedData = reports.monthly.map((row) => row.missedRate);

  appointmentReportsChart = new Chart(appointmentReportsCanvas, {
    type: "line",
    data: {
      labels: reports.monthly.map((row) => row.label),
      datasets: [
        buildLineDataset(APPOINTMENT_SERIES[0], attendanceData),
        buildLineDataset(APPOINTMENT_SERIES[1], missedData),
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      layout: REPORT_LINE_LAYOUT,
      elements: LINE_CHART_ELEMENTS,
      plugins: LINE_CHART_PLUGINS,
      scales: {
        y: yScaleWithZeroPadding({
          max: 100,
          ticks: { precision: 0 },
          title: { display: true, text: "Percentage (%)" },
        }),
        x: {
          offset: true,
          grid: { display: false },
          ticks: { padding: 12 },
        },
      },
    },
  });

  renderChartKey("appointment-reports-chart-key", APPOINTMENT_SERIES);
}

// Health Trend line chart removed

function renderEmergencyChart(emergency) {
  if (!emergencyBarCanvas || !window.Chart) return;
  ensureChartPlugins();

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
          backgroundColor: EMERGENCY_BAR_SERIES[0].color,
          borderRadius: 4,
        },
        {
          label: "Responded",
          data: emergency.monthly.map((row) => row.responded),
          backgroundColor: EMERGENCY_BAR_SERIES[1].color,
          borderRadius: 4,
        },
        {
          label: "Resolved",
          data: emergency.monthly.map((row) => row.resolved),
          backgroundColor: EMERGENCY_BAR_SERIES[2].color,
          borderRadius: 4,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: CHART_LEGEND_PRINT,
        reportEndLabels: { enabled: false },
      },
      scales: {
        y: {
          beginAtZero: true,
          ticks: { precision: 0 },
          grid: { color: "#eef1f3" },
          title: { display: true, text: "Count" },
        },
        x: {
          grid: { display: false },
        },
      },
    },
  });

  renderChartKey("emergency-bar-chart-key", EMERGENCY_BAR_SERIES);
}

function improvementBadge(row) {
  if (row.changePct == null) return "—";
  const sign = row.changePct > 0 ? "+" : "";
  const tone = row.positive ? "reports-improvement--positive" : "reports-improvement--negative";
  const arrow = row.changePct >= 0 ? "↑" : "↓";
  return `<span class="reports-improvement ${tone}">${arrow} ${sign}${row.changePct}%</span>`;
}

function renderReport(report) {
  latestReport = report;

  if (patientGrowthTotalEl) patientGrowthTotalEl.textContent = formatNumber(report.patientGrowth.totalRegisteredPatients);
  if (staffGrowthTotalEl) staffGrowthTotalEl.textContent = formatNumber(report.patientGrowth.totalStaff);
  if (doctorGrowthTotalEl) doctorGrowthTotalEl.textContent = formatNumber(report.patientGrowth.totalDoctors);
  if (therapistGrowthTotalEl) therapistGrowthTotalEl.textContent = formatNumber(report.patientGrowth.totalTherapists);
  if (caregiverGrowthTotalEl) caregiverGrowthTotalEl.textContent = formatNumber(report.patientGrowth.totalCaregivers);

  if (appointmentAttendanceRateEl) appointmentAttendanceRateEl.textContent = `${report.appointmentReports.attendanceRate}%`;
  if (appointmentMissedRateEl) appointmentMissedRateEl.textContent = `${report.appointmentReports.missedRate}%`;
  if (appointmentTotalScheduledEl) appointmentTotalScheduledEl.textContent = formatNumber(report.appointmentReports.totalNonCancelled);

  if (emergencyTotalAlertsEl) emergencyTotalAlertsEl.textContent = String(report.emergency.totals.alerts);
  if (emergencyRespondedEl) emergencyRespondedEl.textContent = String(report.emergency.totals.responded);
  if (emergencyResolvedEl) emergencyResolvedEl.textContent = String(report.emergency.totals.resolved);
  if (emergencyResolutionRateEl) emergencyResolutionRateEl.textContent = `${report.emergency.totals.resolutionRate}%`;
  if (emergencyAvgResponseEl) {
    emergencyAvgResponseEl.textContent = `${report.emergency.totals.avgResponseMin} min`;
  }

  renderPatientGrowthChart(report.patientGrowth);
  renderAppointmentReportsChart(report.appointmentReports);
  renderEmergencyChart(report.emergency);

  if (errorEl) errorEl.hidden = true;
}

async function loadReports() {
  if (loading) return;
  loading = true;

  try {
    const report = await fetchReportsData(currentRangeKey, currentGrouping);
    renderReport(report);

    if (errorEl && report.warnings?.length) {
      errorEl.hidden = false;
      errorEl.textContent = `Some optional data could not be loaded (${report.warnings.join(", ")}). Charts may be incomplete until Firestore rules are deployed.`;
    }
  } catch (error) {
    console.error("Reports load failed:", error);
    if (errorEl) {
      errorEl.hidden = false;
      errorEl.textContent = formatFirestoreError(error, "report data");
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
  if (!latestReport) return;

  let csvContent = "";

  // Section 1: Patient & Staff Growth history
  csvContent += "SECTION 1: PATIENT & STAFF GROWTH HISTORY\n";
  csvContent += "Month,Patients,Doctors,Therapists,Caregivers\n";
  latestReport.patientGrowth.labels.forEach((label, idx) => {
    csvContent += `"${label}",${latestReport.patientGrowth.patientGrowth[idx]},${latestReport.patientGrowth.doctorGrowth[idx]},${latestReport.patientGrowth.therapistGrowth[idx]},${latestReport.patientGrowth.caregiverGrowth[idx]}\n`;
  });
  csvContent += "\n";

  // Section 2: Appointment attendance metrics
  csvContent += "SECTION 2: APPOINTMENT ATTENDANCE METRICS\n";
  csvContent += "Month,Total Appointments,Attendance Rate %,Missed Rate %\n";
  latestReport.appointmentReports.monthly.forEach((row) => {
    csvContent += `"${row.label}",${row.total},${row.attendanceRate},${row.missedRate}\n`;
  });
  csvContent += "\n";

  // Section 3: Emergency alerts frequency and response times
  csvContent += "SECTION 3: EMERGENCY ALERTS FREQUENCY AND RESPONSE TIMES\n";
  csvContent += "Month,Total Alerts,Responded,Resolved,Resolution Rate %,Avg Response Time (min)\n";
  latestReport.emergency.monthly.forEach((row) => {
    csvContent += `"${row.label}",${row.alerts},${row.responded},${row.resolved},${row.resolutionRate},${row.avgResponseMin}\n`;
  });

  const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = `aura-guide-reports-analytics-${new Date().toISOString().slice(0, 10)}.csv`;
  link.click();
  URL.revokeObjectURL(url);
}

function exportPdf() {
  updatePrintHeader();
  document.body.classList.add("reports-print-mode");
  requestAnimationFrame(() => {
    prepareChartsForPrint();
    requestAnimationFrame(() => {
      window.print();
    });
  });
}

window.addEventListener("beforeprint", () => {
  updatePrintHeader();
  document.body.classList.add("reports-print-mode");
  prepareChartsForPrint();
});

window.addEventListener("afterprint", () => {
  document.body.classList.remove("reports-print-mode");
  if (latestReport) renderReport(latestReport);
});

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

initStaffAuth((profile) => {
  if (!isAdmin(profile?.role)) {
    window.location.href = "dashboard.html";
    return;
  }
  loadReports();
});
