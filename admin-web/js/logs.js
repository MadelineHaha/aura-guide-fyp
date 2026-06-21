import { initStaffAuth } from "./staff-shell.js";
import { subscribeActivityLogs } from "./activity-logs-service.js";

const tbodyEl = document.getElementById("logs-tbody");
const emptyEl = document.getElementById("logs-empty");
const loadingEl = document.getElementById("logs-loading");
const searchEl = document.getElementById("logs-search");
const dateRangeEl = document.getElementById("logs-date-range");
const filterTabs = document.querySelectorAll(".logs-filter-tabs .filter-tab");
const exportBtn = document.getElementById("logs-export-btn");

const DATE_RANGE_DAYS = {
  7: 7,
  30: 30,
  60: 60,
};

let logs = [];
let activeTypeFilter = "all";
let activeDateRange = "30";
let searchQuery = "";
let unsubscribeLogs = null;
let logsLoaded = false;

function setLoading(isLoading) {
  if (loadingEl) loadingEl.hidden = !isLoading;
}

function badgeLabel(type) {
  return type.charAt(0).toUpperCase() + type.slice(1);
}

function renderTypeBadge(type) {
  return `<span class="logs-type-badge logs-type-badge--${type}">${badgeLabel(type)}</span>`;
}

function matchesDateRange(log) {
  if (activeDateRange === "all") return true;

  const days = DATE_RANGE_DAYS[activeDateRange];
  if (!days) return true;

  const timestampMs = log.timestampMs || 0;
  if (!timestampMs) return false;

  const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;
  return timestampMs >= cutoff;
}

function filterLogs() {
  const q = searchQuery.toLowerCase();
  return logs.filter((log) => {
    const matchesType = activeTypeFilter === "all" || log.type === activeTypeFilter;
    const matchesDate = matchesDateRange(log);
    const haystack = `${log.userName} ${log.userId} ${log.action} ${log.details} ${log.ipAddress}`.toLowerCase();
    const matchesSearch = !q || haystack.includes(q);
    return matchesType && matchesDate && matchesSearch;
  });
}

function renderLogRow(log) {
  return `
    <tr>
      <td>
        <span class="logs-timestamp">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <circle cx="12" cy="12" r="9" />
            <polyline points="12 7 12 12 15 14" />
          </svg>
          ${log.timestamp}
        </span>
      </td>
      <td>
        <p class="cell-primary">${log.userName}</p>
        <p class="cell-secondary">${log.userId}</p>
      </td>
      <td>${log.action}</td>
      <td class="logs-details">${log.details}</td>
      <td>${renderTypeBadge(log.type)}</td>
      <td>${log.ipAddress}</td>
    </tr>
  `;
}

function emptyMessage() {
  if (logs.length === 0) {
    return "No activity logs yet. Actions from the mobile app and admin portal will appear here.";
  }

  const hasOtherFilters =
    activeTypeFilter !== "all" || searchQuery.length > 0;
  const dateOnly = activeDateRange !== "all" && !hasOtherFilters;

  if (dateOnly) {
    const label =
      activeDateRange === "7"
        ? "the past 7 days"
        : activeDateRange === "60"
          ? "the past 60 days"
          : "the past 30 days";
    return `No logs found in ${label}. Try a wider date range.`;
  }

  return "No logs match your filters.";
}

function renderLogsTable() {
  if (!logsLoaded) return;

  setLoading(false);
  const filtered = filterLogs();
  if (filtered.length === 0) {
    tbodyEl.innerHTML = "";
    emptyEl.hidden = false;
    emptyEl.textContent = emptyMessage();
    return;
  }

  emptyEl.hidden = true;
  tbodyEl.innerHTML = filtered.map(renderLogRow).join("");
}

function exportLogs() {
  const filtered = filterLogs();
  const header = "timestamp,userName,userId,action,details,type,ipAddress";
  const rows = filtered.map((log) =>
    [
      log.timestamp,
      log.userName,
      log.userId,
      log.action,
      log.details,
      log.type,
      log.ipAddress,
    ]
      .map((value) => `"${String(value).replace(/"/g, '""')}"`)
      .join(","),
  );

  const csv = [header, ...rows].join("\n");
  const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = "system-activity-logs.csv";
  document.body.appendChild(link);
  link.click();
  link.remove();
  URL.revokeObjectURL(url);
}

function startLogsSubscription() {
  if (unsubscribeLogs) unsubscribeLogs();
  logsLoaded = false;
  setLoading(true);
  if (emptyEl) emptyEl.hidden = true;

  unsubscribeLogs = subscribeActivityLogs(
    (nextLogs) => {
      logs = nextLogs;
      logsLoaded = true;
      renderLogsTable();
    },
    (error) => {
      console.error("Activity logs subscription failed:", error);
      logs = [];
      logsLoaded = true;
      setLoading(false);
      renderLogsTable();
      emptyEl.hidden = false;
      const code = error?.code || "";
      if (code === "permission-denied") {
        emptyEl.textContent =
          "Could not load activity logs. Deploy Firestore rules: firebase deploy --only firestore:rules";
      } else if (code === "failed-precondition") {
        emptyEl.textContent =
          "Activity logs index is building. Wait a minute and refresh this page.";
      } else {
        emptyEl.textContent =
          error?.message || "Could not load activity logs.";
      }
    },
  );
}

searchEl.addEventListener("input", () => {
  searchQuery = searchEl.value.trim();
  renderLogsTable();
});

dateRangeEl.addEventListener("change", () => {
  activeDateRange = dateRangeEl.value;
  renderLogsTable();
});

filterTabs.forEach((tab) => {
  tab.addEventListener("click", () => {
    filterTabs.forEach((item) => item.classList.remove("is-active"));
    tab.classList.add("is-active");
    activeTypeFilter = tab.dataset.type;
    renderLogsTable();
  });
});

exportBtn.addEventListener("click", exportLogs);

window.addEventListener("pagehide", () => {
  if (unsubscribeLogs) unsubscribeLogs();
});

initStaffAuth(() => {
  startLogsSubscription();
});
