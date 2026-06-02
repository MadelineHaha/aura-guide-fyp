import { initStaffAuth } from "./staff-shell.js";

const logs = [
  {
    timestamp: "2026-03-28 10:15:22",
    userName: "Ahmad Bin Ismail",
    userId: "U00015",
    action: "Login",
    details: "Successful login to staff portal.",
    type: "info",
    ipAddress: "192.168.1.15",
  },
  {
    timestamp: "2026-03-28 10:20:05",
    userName: "Ahmad Bin Ismail",
    userId: "U00015",
    action: "Book Appointment",
    details: "Booked appointment for eye checkup.",
    type: "info",
    ipAddress: "192.168.1.15",
  },
  {
    timestamp: "2026-03-28 10:25:48",
    userName: "Dr. Sarah Tan",
    userId: "S00001",
    action: "Update Patient Record",
    details: "Updated medication and follow-up notes.",
    type: "info",
    ipAddress: "10.0.0.12",
  },
  {
    timestamp: "2026-03-28 10:30:12",
    userName: "System",
    userId: "—",
    action: "Emergency SOS Triggered",
    details: "Fall detection event detected.",
    type: "security",
    ipAddress: "localhost",
  },
  {
    timestamp: "2026-03-28 10:35:55",
    userName: "Madeline Ong",
    userId: "U00876",
    action: "Failed Login",
    details: "Invalid password attempt.",
    type: "warning",
    ipAddress: "192.168.2.110",
  },
];

const tbodyEl = document.getElementById("logs-tbody");
const emptyEl = document.getElementById("logs-empty");
const searchEl = document.getElementById("logs-search");
const filterTabs = document.querySelectorAll(".logs-filter-tabs .filter-tab");
const exportBtn = document.getElementById("logs-export-btn");

let activeTypeFilter = "all";
let searchQuery = "";

function badgeLabel(type) {
  return type.charAt(0).toUpperCase() + type.slice(1);
}

function renderTypeBadge(type) {
  return `<span class="logs-type-badge logs-type-badge--${type}">${badgeLabel(type)}</span>`;
}

function filterLogs() {
  const q = searchQuery.toLowerCase();
  return logs.filter((log) => {
    const matchesType = activeTypeFilter === "all" || log.type === activeTypeFilter;
    const haystack = `${log.userName} ${log.userId} ${log.action} ${log.details} ${log.ipAddress}`.toLowerCase();
    const matchesSearch = !q || haystack.includes(q);
    return matchesType && matchesSearch;
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

function renderLogsTable() {
  const filtered = filterLogs();
  if (filtered.length === 0) {
    tbodyEl.innerHTML = "";
    emptyEl.hidden = false;
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

searchEl.addEventListener("input", () => {
  searchQuery = searchEl.value.trim();
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

renderLogsTable();
initStaffAuth();
