import {
  EMERGENCIES_PAGE,
  formatPatientDisplayName,
  resolvePatientName,
  subscribeActiveEmergencyAlerts,
} from "./emergency-alerts-service.js";
import { releaseFirestoreListener } from "./firestore-realtime.js";

function ensurePopupRoot() {
  let root = document.getElementById("emergency-alert-popup-root");
  if (root) return root;

  root = document.createElement("div");
  root.id = "emergency-alert-popup-root";
  root.className = "emergency-alert-popup-root";
  document.body.appendChild(root);
  return root;
}

function playAlertTone() {
  try {
    const context = new (window.AudioContext || window.webkitAudioContext)();
    const playBeep = (frequency, startAt, duration) => {
      const oscillator = context.createOscillator();
      const gain = context.createGain();
      oscillator.type = "sine";
      oscillator.frequency.value = frequency;
      gain.gain.value = 0.12;
      oscillator.connect(gain);
      gain.connect(context.destination);
      oscillator.start(startAt);
      oscillator.stop(startAt + duration);
    };
    const now = context.currentTime;
    playBeep(880, now, 0.22);
    playBeep(1100, now + 0.28, 0.22);
  } catch {
    /* optional */
  }
}

function emergenciesUrl(alertId) {
  const id = String(alertId || "").trim();
  if (!id) return EMERGENCIES_PAGE;
  return `${EMERGENCIES_PAGE}?alert=${encodeURIComponent(id)}`;
}

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function formatPopupTitle(patientName, userId) {
  const name = String(patientName || "").trim() || "Unknown patient";
  const id = String(userId || "").trim();
  return id ? `SOS by ${name} (${id})` : `SOS by ${name}`;
}

function renderPopup(alert, patientName) {
  const root = ensurePopupRoot();
  const overlay = document.createElement("div");
  overlay.className = "emergency-alert-popup-overlay";
  overlay.setAttribute("role", "alertdialog");
  overlay.setAttribute("aria-modal", "true");
  overlay.setAttribute("aria-labelledby", "emergency-popup-title");

  const locationLine = alert.location
    ? `<p class="emergency-alert-popup-location">${escapeHtml(alert.location)}</p>`
    : "";
  const popupTitle = formatPopupTitle(patientName, alert.userId);

  overlay.innerHTML = `
    <div class="emergency-alert-popup emergency-alert-popup--compact">
      <div class="emergency-alert-popup-pulse" aria-hidden="true"></div>
      <div class="emergency-alert-popup-icon" aria-hidden="true">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          <path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
          <line x1="12" y1="9" x2="12" y2="13"/>
          <line x1="12" y1="17" x2="12.01" y2="17"/>
        </svg>
      </div>
      <h2 class="emergency-alert-popup-title" id="emergency-popup-title">
        ${escapeHtml(popupTitle)}
      </h2>
      <p class="emergency-alert-popup-meta">Alert ID: ${escapeHtml(alert.alertId)} · ${escapeHtml(alert.alertType)} · ${escapeHtml(alert.dateTimeLabel)}</p>
      ${locationLine}
      <div class="emergency-alert-popup-actions">
        <button type="button" class="emergency-alert-popup-dismiss">Dismiss</button>
        <button type="button" class="emergency-alert-popup-view">View</button>
      </div>
    </div>
  `;

  const dismiss = () => overlay.remove();
  overlay.querySelector(".emergency-alert-popup-dismiss")?.addEventListener("click", dismiss);
  overlay.querySelector(".emergency-alert-popup-view")?.addEventListener("click", () => {
    dismiss();
    window.location.href = emergenciesUrl(alert.alertId);
  });
  overlay.addEventListener("click", (event) => {
    if (event.target === overlay) dismiss();
  });

  root.appendChild(overlay);
  playAlertTone();
  overlay.querySelector(".emergency-alert-popup-view")?.focus();
}

function renderDashboardBanner(alert, patientName) {
  const banner = document.createElement("article");
  banner.className = "emergency-banner";
  banner.setAttribute("role", "alert");

  const locationLine = alert.location
    ? escapeHtml(alert.location)
    : "Location pending";

  banner.innerHTML = `
    <div class="emergency-banner-accent" aria-hidden="true"></div>
    <div class="emergency-banner-icon" aria-hidden="true">
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/>
        <line x1="12" y1="9" x2="12" y2="13"/>
        <line x1="12" y1="17" x2="12.01" y2="17"/>
      </svg>
    </div>
    <div class="emergency-banner-body">
      <p class="emergency-banner-kicker">Emergency SOS</p>
      <p class="emergency-banner-title">${escapeHtml(alert.userId || "Unknown")}</p>
      <p class="emergency-banner-patient-name">${escapeHtml(formatPatientDisplayName(alert.userId, patientName))}</p>
      <div class="emergency-banner-meta">
        <span class="emergency-banner-chip">${escapeHtml(alert.alertId)}</span>
        <span class="emergency-banner-chip">${escapeHtml(alert.alertType)}</span>
        <span class="emergency-banner-chip emergency-banner-chip--muted">${escapeHtml(alert.dateTimeLabel)}</span>
      </div>
      <p class="emergency-banner-location">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"/>
          <circle cx="12" cy="10" r="3"/>
        </svg>
        <span>${locationLine}</span>
      </p>
    </div>
    <button type="button" class="emergency-banner-action">
      <span>View alert</span>
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
        <line x1="5" y1="12" x2="19" y2="12"/>
        <polyline points="12 5 19 12 12 19"/>
      </svg>
    </button>
  `;

  banner.querySelector(".emergency-banner-action")?.addEventListener("click", () => {
    window.location.href = emergenciesUrl(alert.alertId);
  });

  return banner;
}

function updateDashboardBanner(alerts, patientNames) {
  const container = document.getElementById("emergency-banners");
  const countEl = document.getElementById("stat-active-emergencies");

  if (countEl) countEl.textContent = String(alerts.length);
  if (!container) return;

  container.replaceChildren();

  if (alerts.length === 0) {
    container.hidden = true;
    return;
  }

  const head = document.createElement("header");
  head.className = "emergency-banners-head";
  head.innerHTML = `
    <h2 class="emergency-banners-heading">
      Active emergencies
      <span class="emergency-banners-count">${alerts.length}</span>
    </h2>
  `;

  const list = document.createElement("div");
  list.className = "emergency-banners-list";

  for (const alert of alerts) {
    const patientName = patientNames.get(alert.userId) || alert.userId;
    list.appendChild(renderDashboardBanner(alert, patientName));
  }

  container.appendChild(head);
  container.appendChild(list);
  container.hidden = false;
}

async function refreshBanner(alerts) {
  const patientNames = new Map();
  await Promise.all(
    alerts.map(async (alert) => {
      patientNames.set(alert.userId, await resolvePatientName(alert.userId));
    }),
  );
  updateDashboardBanner(alerts, patientNames);
}

let unsubscribe = null;

export function initEmergencyAlertsWatcher() {
  sessionStorage.removeItem("emergencyAlertsSeenIds");

  releaseFirestoreListener(unsubscribe);
  unsubscribe = null;

  unsubscribe = subscribeActiveEmergencyAlerts(({ alerts, newAlerts }) => {
    void refreshBanner(alerts);

    for (const alert of newAlerts) {
      void resolvePatientName(alert.userId)
        .then((name) => renderPopup(alert, name))
        .catch(() => renderPopup(alert, alert.userId || "Unknown patient"));
    }
  }, (error) => {
    console.error("Emergency alerts watcher failed:", error);
  });
}

export function stopEmergencyAlertsWatcher() {
  releaseFirestoreListener(unsubscribe);
  unsubscribe = null;
}
