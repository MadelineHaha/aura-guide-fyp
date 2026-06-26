import { initStaffAuth } from "./staff-shell.js";
import { formatFirestoreError } from "./staff-data-status.js";
import { isTherapist as isTherapistRole } from "./staff-rbac.js";
import { getStaffSession } from "./staff-auth.js";
import { releaseFirestoreListener } from "./firestore-realtime.js";
import {
  ALERT_STATUS_ACTIVE,
  ALERT_STATUS_RESPONDED,
  ALERT_STATUS_RESOLVED,
  RESPONSE_ACTION_EMERGENCY,
  assignCaregiverToAlert,
  countActiveAlerts,
  formatPatientDisplayName,
  formatPatientLabel,
  getBusyCaregiverIds,
  resolveEmergencyAlert,
  resolvePatientName,
  respondEmergencyAlert,
  subscribeAllEmergencyAlerts,
} from "./emergency-alerts-service.js";
import { fetchActiveCaregivers } from "./staff-list-service.js";
import { formatStaffDisplayName } from "./staff-name-format.js";
import { formatTypedSentence } from "./text-format.js";
import { fetchPatients } from "./user-patients-service.js";

const listEl = document.getElementById("emergencies-list");
const emptyEl = document.getElementById("emergencies-empty");
const mapEl = document.getElementById("emergencies-map");
const mapLabelEl = document.getElementById("emergencies-map-label");
const activeBadgeEl = document.getElementById("emergencies-active-badge");
const activeLabelEl = document.getElementById("emergencies-active-label");
const filterTabsEl = document.getElementById("emergencies-filter-tabs");
const respondModalEl = document.getElementById("emergency-respond-modal");
const respondPatientEl = document.getElementById("emergency-respond-patient");
const respondCloseEl = document.getElementById("emergency-respond-close");
const caregiverModalEl = document.getElementById("emergency-caregiver-modal");
const caregiverPatientEl = document.getElementById("emergency-caregiver-patient");
const caregiverListEl = document.getElementById("emergency-caregiver-list");
const caregiverEmptyEl = document.getElementById("emergency-caregiver-empty");
const caregiverCloseEl = document.getElementById("emergency-caregiver-close");
const resolveModalEl = document.getElementById("emergency-resolve-modal");
const resolvePatientEl = document.getElementById("emergency-resolve-patient");
const resolveCloseEl = document.getElementById("emergency-resolve-close");
const resolveCancelEl = document.getElementById("emergency-resolve-cancel");
const resolveConfirmEl = document.getElementById("emergency-resolve-confirm");
const resolveNoteEl = document.getElementById("emergency-resolve-note");
const resolveNoteErrorEl = document.getElementById("emergency-resolve-note-error");

const MAP_DEFAULT_CENTER = [4.2105, 101.9758];
const MAP_DEFAULT_ZOOM = 6;

let emergencyMap = null;
let markerLayer = null;
const markersByAlertId = new Map();
let allAlertsCache = [];
let currentFilter = "all";
const patientNamesCache = new Map();
const caregiverNamesCache = new Map();
let pendingRespondAlertId = null;
let pendingRespondButton = null;
let pendingResolveAlertId = null;
let pendingResolveButton = null;
let pendingCurrentAlert = null;

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function staffIdFromSession() {
  const profile = getStaffSession();
  return String(profile?.staffID || profile?.staffId || "").trim();
}

function highlightAlertId() {
  return new URLSearchParams(window.location.search).get("alert")?.trim() || "";
}

function markerColor(status) {
  if (status === "responded") return "#fd7e14";
  if (status === "resolved") return "#2f9e44";
  return "#dc3545";
}

function parseCoords(location) {
  const match = String(location || "").match(
    /(-?\d+(?:\.\d+)?)\s*[,]\s*(-?\d+(?:\.\d+)?)/,
  );
  if (!match) return null;
  const lat = Number.parseFloat(match[1]);
  const lng = Number.parseFloat(match[2]);
  if (Number.isNaN(lat) || Number.isNaN(lng)) return null;
  return { lat, lng };
}

function statusKey(status) {
  const value = String(status || "").trim();
  if (value === ALERT_STATUS_RESPONDED) return "responded";
  if (value === ALERT_STATUS_RESOLVED) return "resolved";
  return "active";
}

function statusLabel(status) {
  const value = String(status || "").trim();
  if (value === ALERT_STATUS_RESPONDED) return "Responded";
  if (value === ALERT_STATUS_RESOLVED) return "Resolved";
  return "Active";
}

function activeAlertLabel(count) {
  return count === 1 ? "1 Active Alert" : `${count} Active Alerts`;
}

function filterAlertsByCategory(alerts, filter) {
  if (filter === "active") {
    return alerts.filter((alert) => statusKey(alert.status) === "active");
  }
  if (filter === "responded") {
    return alerts.filter((alert) => statusKey(alert.status) === "responded");
  }
  if (filter === "resolved") {
    return alerts.filter((alert) => statusKey(alert.status) === "resolved");
  }
  return alerts;
}

function filterLabel(filter) {
  if (filter === "active") return "Active";
  if (filter === "responded") return "Responded";
  if (filter === "resolved") return "Resolved";
  return "All";
}

function emptyMessageForFilter(filter) {
  if (filter === "active") return "No active alerts.";
  if (filter === "responded") return "No responded alerts.";
  if (filter === "resolved") return "No resolved alerts.";
  return "No emergency alerts yet.";
}

function updateFilterTabs(alerts) {
  if (!filterTabsEl) return;

  filterTabsEl.querySelectorAll("[data-filter]").forEach((button) => {
    const filter = button.getAttribute("data-filter") || "all";
    const count = filterAlertsByCategory(alerts, filter).length;
    const label = filterLabel(filter);
    button.textContent = `${label} (${count})`;
    const isActive = filter === currentFilter;
    button.classList.toggle("is-active", isActive);
    button.setAttribute("aria-selected", String(isActive));
  });
}

async function ensurePatientNames(alerts) {
  const missing = alerts.filter((alert) => !patientNamesCache.has(alert.userId));
  await Promise.all(
    missing.map(async (alert) => {
      try {
        patientNamesCache.set(
          alert.userId,
          await resolvePatientName(alert.userId),
        );
      } catch (error) {
        console.warn("Could not resolve patient name:", alert.userId, error);
        patientNamesCache.set(alert.userId, alert.userId);
      }
    }),
  );
}

function ensureEmergencyMap() {
  if (!mapEl || emergencyMap || !window.L) return emergencyMap;

  emergencyMap = window.L.map(mapEl, {
    zoomControl: true,
    scrollWheelZoom: true,
  }).setView(MAP_DEFAULT_CENTER, MAP_DEFAULT_ZOOM);

  window.L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
    attribution:
      '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>',
    maxZoom: 19,
  }).addTo(emergencyMap);

  markerLayer = window.L.layerGroup().addTo(emergencyMap);
  requestAnimationFrame(() => emergencyMap?.invalidateSize());
  return emergencyMap;
}

function createNumberedMarkerIcon(status, number) {
  const color = markerColor(status);
  return window.L.divIcon({
    className: "emergency-map-number-wrap",
    html: `<div class="emergency-map-number emergency-map-number--${status}" style="--marker-color:${color}"><span>${number}</span></div>`,
    iconSize: [36, 36],
    iconAnchor: [18, 18],
    popupAnchor: [0, -20],
  });
}

function clearEmergencyMapMarkers() {
  ensureEmergencyMap();
  markerLayer?.clearLayers();
  markersByAlertId.clear();
  emergencyMap?.setView(MAP_DEFAULT_CENTER, MAP_DEFAULT_ZOOM);
  if (mapLabelEl) mapLabelEl.textContent = "Live patient locations";
}

function updateMapLabel(filteredAlerts, mappableCount, filter) {
  if (!mapLabelEl) return;

  const totalCount = filteredAlerts.length;
  const missingLocationCount = totalCount - mappableCount;
  const scopeLabel =
    filter === "all" ? "" : `${filterLabel(filter).toLowerCase()} `;

  if (totalCount === 0) {
    mapLabelEl.textContent =
      filter === "all"
        ? "Live patient locations — waiting for GPS"
        : `No ${filterLabel(filter).toLowerCase()} alerts to show on map`;
    return;
  }

  if (mappableCount === 0) {
    mapLabelEl.textContent =
      totalCount === 1
        ? `1 ${scopeLabel}alert — location unavailable`
        : `${totalCount} ${scopeLabel}alerts — locations unavailable`;
    return;
  }

  if (missingLocationCount > 0) {
    mapLabelEl.textContent = `${mappableCount} of ${totalCount} ${scopeLabel}alert${totalCount === 1 ? "" : "s"} on map`;
    return;
  }

  mapLabelEl.textContent =
    mappableCount === 1
      ? "1 patient location on map"
      : `${mappableCount} patient locations on map`;
}

function renderMap(alerts, patientNames, filter = currentFilter) {
  if (!mapEl || !window.L) return;

  ensureEmergencyMap();
  markerLayer.clearLayers();

  const points = [];

  alerts.forEach((alert, index) => {
    const coords = parseCoords(alert.location);
    if (!coords) return;

    const number = index + 1;
    const patientName = patientNames.get(alert.userId) || alert.userId;
    const status = statusKey(alert.status);
    const latLng = [coords.lat, coords.lng];
    points.push(latLng);

    const marker = window.L.marker(latLng, {
      icon: createNumberedMarkerIcon(status, number),
      title: `${number}. ${patientName}`,
    });

    marker.bindPopup(`
      <div class="emergency-map-popup">
        <span class="emergency-map-popup-index emergency-map-popup-index--${status}">${number}</span>
        <strong>${escapeHtml(patientName)}</strong>
        <span class="emergency-map-popup-status emergency-map-popup-status--${status}">
          ${escapeHtml(statusLabel(alert.status))}
        </span>
        <p>${escapeHtml(alert.alertId)} · ${escapeHtml(alert.alertType)}</p>
        <p>${escapeHtml(alert.location || "Location pending")}</p>
      </div>
    `);

    marker.addTo(markerLayer);
    markersByAlertId.set(alert.alertId, marker);
  });

  if (points.length === 1) {
    emergencyMap.setView(points[0], 15);
  } else if (points.length > 1) {
    emergencyMap.fitBounds(window.L.latLngBounds(points), { padding: [48, 48] });
  } else {
    emergencyMap.setView(MAP_DEFAULT_CENTER, MAP_DEFAULT_ZOOM);
  }

  requestAnimationFrame(() => emergencyMap?.invalidateSize());

  updateMapLabel(alerts, points.length, filter);
  requestAnimationFrame(() => emergencyMap?.invalidateSize());
}

function focusMapMarker(alertId) {
  const marker = markersByAlertId.get(alertId);
  if (!marker || !emergencyMap) return;

  emergencyMap.flyTo(marker.getLatLng(), Math.max(emergencyMap.getZoom(), 15), {
    duration: 0.5,
  });
  marker.openPopup();
}

async function ensureCaregiverNames(alerts) {
  try {
    const caregivers = await fetchActiveCaregivers();
    for (const caregiver of caregivers) {
      caregiverNamesCache.set(
        caregiver.staffID,
        formatStaffDisplayName(caregiver),
      );
    }
  } catch (error) {
    console.warn("Could not load caregiver names for emergencies:", error);
  }

  for (const alert of alerts) {
    const id = String(alert.caregiverId || "").trim();
    if (id && !caregiverNamesCache.has(id)) {
      caregiverNamesCache.set(id, id);
    }
  }
}

function caregiverLabel(alert) {
  const id = String(alert.caregiverId || "").trim();
  if (!id) return "";
  const name = caregiverNamesCache.get(id) || id;
  return `${name} (${id})`;
}

function syncModalBodyLock() {
  const anyOpen =
    (respondModalEl && !respondModalEl.hidden) ||
    (caregiverModalEl && !caregiverModalEl.hidden) ||
    (resolveModalEl && !resolveModalEl.hidden);
  document.body.classList.toggle("modal-open", Boolean(anyOpen));
}

function renderAlertCard(alert, patientName, highlightId, number) {
  const status = statusKey(alert.status);
  const isHighlight = highlightId && highlightId === alert.alertId;
  const location = alert.location || "Location pending";
  const therapistReadOnly = isTherapistRole(loggedInRole);
  const showRespond = !therapistReadOnly && alert.status === ALERT_STATUS_ACTIVE;
  const showResolve = !therapistReadOnly && alert.status !== ALERT_STATUS_RESOLVED;
  const hasCoords = Boolean(parseCoords(alert.location));
  const caregiverLine = caregiverLabel(alert);
  const mapLinkAttrs = hasCoords
    ? `type="button" data-map-link="${escapeHtml(alert.alertId)}" aria-label="Show alert ${number} on map"`
    : `type="button" disabled aria-label="Alert ${number} — location unavailable"`;

  return `
    <article
      class="emergency-alert-card emergency-alert-card--${status}${isHighlight ? " is-highlight" : ""}"
      data-alert-id="${escapeHtml(alert.alertId)}"
      data-alert-number="${number}"
    >
      <button
        class="emergency-alert-card-number emergency-alert-card-number--${status}"
        ${mapLinkAttrs}
      >
        ${number}
      </button>
      <div class="emergency-alert-card-body">
        <div class="emergency-alert-card-top">
          <div class="emergency-alert-card-identity">
            <h3 class="emergency-alert-card-user-id">${escapeHtml(alert.userId || "Unknown")}</h3>
            <p class="emergency-alert-card-user-name">${escapeHtml(formatPatientDisplayName(alert.userId, patientName))}</p>
          </div>
          <span class="emergency-alert-status emergency-alert-status--${status}">
            ${escapeHtml(statusLabel(alert.status))}
          </span>
        </div>
        <p class="emergency-alert-card-location">${escapeHtml(location)}</p>
        <p class="emergency-alert-card-time">${escapeHtml(alert.dateTimeLabel)}</p>
        ${caregiverLine
          ? `<p class="emergency-alert-card-caregiver">Caregiver: ${escapeHtml(caregiverLine)}</p>`
          : ""}
        <div class="emergency-alert-card-details" hidden>
          <p><strong>Alert ID:</strong> ${escapeHtml(alert.alertId)}</p>
          <p><strong>Type:</strong> ${escapeHtml(alert.alertType)}</p>
          ${alert.resolutionNotes
            ? `<p><strong>Notes:</strong> ${escapeHtml(alert.resolutionNotes)}</p>`
            : ""}
        </div>
      </div>
      <div class="emergency-alert-card-actions">
        ${showRespond
          ? `<button type="button" class="emergency-alert-btn emergency-alert-btn--respond" data-respond="${escapeHtml(alert.alertId)}">Respond</button>`
          : ""}
        <button type="button" class="emergency-alert-btn emergency-alert-btn--details" data-details="${escapeHtml(alert.alertId)}">
          Details
        </button>
        ${showResolve
          ? `<button type="button" class="emergency-alert-btn emergency-alert-btn--resolve" data-resolve="${escapeHtml(alert.alertId)}" aria-label="Mark resolved">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" aria-hidden="true">
                <polyline points="20 6 9 17 4 12"/>
              </svg>
            </button>`
          : ""}
      </div>
    </article>
  `;
}

function updateActiveBadge(alerts) {
  const activeCount = countActiveAlerts(alerts);
  if (!activeBadgeEl || !activeLabelEl) return;

  if (activeCount === 0) {
    activeBadgeEl.hidden = true;
    return;
  }

  activeLabelEl.textContent = activeAlertLabel(activeCount);
  activeBadgeEl.hidden = false;
}

function bindFilterTabs() {
  if (!filterTabsEl || filterTabsEl.dataset.bound) return;
  filterTabsEl.dataset.bound = "true";

  filterTabsEl.addEventListener("click", (event) => {
    const button = event.target.closest("[data-filter]");
    if (!button) return;

    const filter = button.getAttribute("data-filter");
    if (!filter || filter === currentFilter) return;

    currentFilter = filter;
    void renderAlerts(allAlertsCache);
  });
}

function closeRespondModal({ keepPending = false } = {}) {
  if (!respondModalEl) return;

  respondModalEl.hidden = true;
  if (!keepPending) {
    pendingRespondAlertId = null;
    pendingRespondButton = null;
    pendingCurrentAlert = null;
  }
  syncModalBodyLock();
}

function openRespondModal(alertId, patientName, button) {
  if (!respondModalEl) return;

  pendingRespondAlertId = alertId;
  pendingRespondButton = button;
  pendingCurrentAlert =
    allAlertsCache.find((alert) => alert.alertId === alertId) || null;
  if (respondPatientEl) {
    respondPatientEl.textContent = patientName || alertId;
  }

  respondModalEl.hidden = false;
  syncModalBodyLock();
  respondModalEl
    .querySelector('[data-response-action="caregiver"]')
    ?.focus();
}

function closeCaregiverModal({ clearPending = true } = {}) {
  if (!caregiverModalEl) return;

  caregiverModalEl.hidden = true;
  if (caregiverListEl) caregiverListEl.innerHTML = "";
  if (caregiverEmptyEl) caregiverEmptyEl.hidden = true;
  if (clearPending) {
    pendingRespondAlertId = null;
    pendingRespondButton = null;
    pendingCurrentAlert = null;
  }
  syncModalBodyLock();
}

function caregiverAvailability(caregiverId, alert) {
  const id = String(caregiverId || "").trim();
  const currentCaregiver = String(alert?.caregiverId || "").trim();

  if (currentCaregiver && currentCaregiver === id) {
    return {
      disabled: true,
      reason: "Already assigned to this alert",
    };
  }

  const busyIds = getBusyCaregiverIds(allAlertsCache);
  if (busyIds.has(id)) {
    return {
      disabled: true,
      reason: "Assigned to another open alert",
    };
  }

  return { disabled: false, reason: "" };
}

function renderCaregiverOptions(caregivers, alert) {
  if (!caregiverListEl) return;

  if (caregivers.length === 0) {
    caregiverListEl.innerHTML = "";
    if (caregiverEmptyEl) caregiverEmptyEl.hidden = false;
    return;
  }

  if (caregiverEmptyEl) caregiverEmptyEl.hidden = true;

  caregiverListEl.innerHTML = caregivers
    .map((caregiver) => {
      const availability = caregiverAvailability(caregiver.staffID, alert);
      const disabledAttr = availability.disabled ? "disabled" : "";
      const note = availability.reason
        ? `<span class="emergency-caregiver-option-note">${escapeHtml(availability.reason)}</span>`
        : "";

      return `
        <button
          type="button"
          class="emergency-caregiver-option${availability.disabled ? " is-disabled" : ""}"
          data-caregiver-id="${escapeHtml(caregiver.staffID)}"
          data-caregiver-name="${escapeHtml(formatStaffDisplayName(caregiver))}"
          ${disabledAttr}
        >
          <span class="emergency-caregiver-option-main">
            <strong>${escapeHtml(formatStaffDisplayName(caregiver))}</strong>
            <span>${escapeHtml(caregiver.staffID)}</span>
          </span>
          ${note}
        </button>
      `;
    })
    .join("");

  caregiverListEl.querySelectorAll("[data-caregiver-id]:not([disabled])").forEach((button) => {
    button.addEventListener("click", () => {
      const caregiverId = button.getAttribute("data-caregiver-id");
      const caregiverName = button.getAttribute("data-caregiver-name");
      void confirmAssignCaregiver(caregiverId, caregiverName);
    });
  });
}

async function openCaregiverPickerModal() {
  const alertId = pendingRespondAlertId;
  const alert =
    pendingCurrentAlert ||
    allAlertsCache.find((item) => item.alertId === alertId) ||
    null;

  if (!alertId || !caregiverModalEl) return;

  closeRespondModal({ keepPending: true });

  if (caregiverPatientEl) {
    caregiverPatientEl.textContent =
      respondPatientEl?.textContent?.trim() || alertId;
  }

  caregiverModalEl.hidden = false;
  syncModalBodyLock();

  if (caregiverListEl) {
    caregiverListEl.innerHTML =
      '<p class="emergency-caregiver-loading">Loading caregivers…</p>';
  }

  try {
    const caregivers = await fetchActiveCaregivers();
    renderCaregiverOptions(caregivers, alert);
  } catch (error) {
    console.error("Failed to load caregivers:", error);
    if (caregiverListEl) caregiverListEl.innerHTML = "";
    if (caregiverEmptyEl) {
      caregiverEmptyEl.textContent = "Could not load caregivers.";
      caregiverEmptyEl.hidden = false;
    }
  }
}

async function confirmAssignCaregiver(caregiverId, caregiverName) {
  const alertId = pendingRespondAlertId;
  const button = pendingRespondButton;
  const staffId = staffIdFromSession();

  closeCaregiverModal();

  if (!alertId || !staffId || !caregiverId) return;
  if (button) button.disabled = true;

  try {
    await assignCaregiverToAlert(alertId, {
      staffId,
      caregiverId,
      caregiverName,
    });
  } catch (error) {
    console.error("Assign caregiver failed:", error);
    if (button) button.disabled = false;
  }
}

function closeResolveModal({ keepPending = false } = {}) {
  if (!resolveModalEl) return;

  resolveModalEl.hidden = true;
  if (resolveNoteEl) resolveNoteEl.value = "";
  if (resolveNoteErrorEl) resolveNoteErrorEl.hidden = true;
  if (!keepPending) {
    pendingResolveAlertId = null;
    pendingResolveButton = null;
  }
  syncModalBodyLock();
}

function openResolveModal(alertId, patientName, button) {
  if (!resolveModalEl) return;

  pendingResolveAlertId = alertId;
  pendingResolveButton = button;
  if (resolvePatientEl) {
    resolvePatientEl.textContent = patientName || alertId;
  }
  if (resolveNoteEl) resolveNoteEl.value = "";
  if (resolveNoteErrorEl) resolveNoteErrorEl.hidden = true;

  resolveModalEl.hidden = false;
  syncModalBodyLock();
  resolveNoteEl?.focus();
}

async function confirmResolveAlert() {
  const alertId = pendingResolveAlertId;
  const button = pendingResolveButton;
  const staffId = staffIdFromSession();
  const resolutionNotes = formatTypedSentence(resolveNoteEl?.value || "");

  if (!resolutionNotes) {
    if (resolveNoteErrorEl) resolveNoteErrorEl.hidden = false;
    resolveNoteEl?.focus();
    return;
  }

  if (resolveNoteErrorEl) resolveNoteErrorEl.hidden = true;
  closeResolveModal();

  if (!alertId || !staffId) return;
  if (button) button.disabled = true;

  try {
    await resolveEmergencyAlert(alertId, { staffId, resolutionNotes });
  } catch (error) {
    console.error("Resolve emergency alert failed:", error);
    if (button) button.disabled = false;
  }
}

async function confirmRespond(responseAction) {
  const alertId = pendingRespondAlertId;
  const button = pendingRespondButton;
  const staffId = staffIdFromSession();

  closeRespondModal();

  if (!alertId || !staffId) return;
  if (button) button.disabled = true;

  try {
    await respondEmergencyAlert(alertId, { staffId, responseAction });

    if (responseAction === RESPONSE_ACTION_EMERGENCY) {
      window.open("tel:999", "_self");
    }
  } catch (error) {
    console.error("Respond to emergency alert failed:", error);
    if (button) button.disabled = false;
  }
}

function bindRespondModal() {
  if (!respondModalEl || respondModalEl.dataset.bound) return;
  respondModalEl.dataset.bound = "true";

  respondCloseEl?.addEventListener("click", () => closeRespondModal());
  respondModalEl.addEventListener("click", (event) => {
    if (event.target === respondModalEl) closeRespondModal();
  });

  respondModalEl.querySelectorAll("[data-response-action]").forEach((button) => {
    button.addEventListener("click", () => {
      const action = button.getAttribute("data-response-action");
      if (action === RESPONSE_ACTION_EMERGENCY) {
        void confirmRespond(RESPONSE_ACTION_EMERGENCY);
        return;
      }
      void openCaregiverPickerModal();
    });
  });
}

function bindCaregiverModal() {
  if (!caregiverModalEl || caregiverModalEl.dataset.bound) return;
  caregiverModalEl.dataset.bound = "true";

  caregiverCloseEl?.addEventListener("click", () => closeCaregiverModal());
  caregiverModalEl.addEventListener("click", (event) => {
    if (event.target === caregiverModalEl) closeCaregiverModal();
  });
}

function bindResolveModal() {
  if (!resolveModalEl || resolveModalEl.dataset.bound) return;
  resolveModalEl.dataset.bound = "true";

  resolveCloseEl?.addEventListener("click", () => closeResolveModal());
  resolveCancelEl?.addEventListener("click", () => closeResolveModal());
  resolveModalEl.addEventListener("click", (event) => {
    if (event.target === resolveModalEl) closeResolveModal();
  });
  resolveConfirmEl?.addEventListener("click", () => {
    void confirmResolveAlert();
  });
}

function bindModalEscape() {
  if (document.body.dataset.emergencyModalEscapeBound) return;
  document.body.dataset.emergencyModalEscapeBound = "true";

  document.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;

    if (resolveModalEl && !resolveModalEl.hidden) {
      closeResolveModal();
      return;
    }
    if (caregiverModalEl && !caregiverModalEl.hidden) {
      closeCaregiverModal();
      return;
    }
    if (respondModalEl && !respondModalEl.hidden) {
      closeRespondModal();
    }
  });
}

function bindCardMapLinks() {
  listEl?.querySelectorAll("[data-map-link]").forEach((button) => {
    button.addEventListener("click", () => {
      const alertId = button.getAttribute("data-map-link");
      if (!alertId) return;
      focusMapMarker(alertId);
    });
  });
}

function bindAlertActions() {
  listEl?.querySelectorAll("[data-respond]").forEach((button) => {
    button.addEventListener("click", () => {
      const alertId = button.getAttribute("data-respond");
      if (!alertId) return;

      const card = listEl?.querySelector(`[data-alert-id="${alertId}"]`);
      const userId =
        card?.querySelector(".emergency-alert-card-user-id")?.textContent?.trim() ||
        alertId;
      const resolvedName =
        card?.querySelector(".emergency-alert-card-user-name")?.textContent?.trim() ||
        "";

      openRespondModal(alertId, formatPatientLabel(userId, resolvedName), button);
    });
  });

  listEl?.querySelectorAll("[data-resolve]").forEach((button) => {
    button.addEventListener("click", () => {
      const alertId = button.getAttribute("data-resolve");
      if (!alertId) return;

      const card = listEl?.querySelector(`[data-alert-id="${alertId}"]`);
      const userId =
        card?.querySelector(".emergency-alert-card-user-id")?.textContent?.trim() ||
        alertId;
      const resolvedName =
        card?.querySelector(".emergency-alert-card-user-name")?.textContent?.trim() ||
        "";

      openResolveModal(alertId, formatPatientLabel(userId, resolvedName), button);
    });
  });

  listEl?.querySelectorAll("[data-details]").forEach((button) => {
    button.addEventListener("click", () => {
      const alertId = button.getAttribute("data-details");
      const card = listEl?.querySelector(`[data-alert-id="${alertId}"]`);
      const details = card?.querySelector(".emergency-alert-card-details");
      if (!details) return;
      const isHidden = details.hidden;
      details.hidden = !isHidden;
      button.textContent = isHidden ? "Hide details" : "Details";
      button.setAttribute("aria-expanded", String(isHidden));
    });
  });
}

function renderAlertList(filtered) {
  if (!listEl || !emptyEl) return;

  if (filtered.length === 0) {
    listEl.innerHTML = "";
    emptyEl.textContent = emptyMessageForFilter(currentFilter);
    emptyEl.hidden = false;
    return;
  }

  emptyEl.hidden = true;
  const highlightId = highlightAlertId();

  listEl.innerHTML = filtered
    .map((alert, index) =>
      renderAlertCard(
        alert,
        patientNamesCache.get(alert.userId) || alert.userId,
        highlightId,
        index + 1,
      ),
    )
    .join("");

  bindCardMapLinks();
  bindAlertActions();

  if (highlightId) {
    listEl.querySelector(".emergency-alert-card.is-highlight")?.scrollIntoView({
      behavior: "smooth",
      block: "center",
    });
  }
}

async function renderAlerts(alerts) {
  if (!listEl || !emptyEl) return;

  try {
    let roleFilteredAlerts = alerts;
    if (loggedInRole.toLowerCase() === "therapist") {
      roleFilteredAlerts = alerts.filter((alert) =>
        assignedPatientIds.has(alert.userId),
      );
    }

    allAlertsCache = roleFilteredAlerts;
    updateActiveBadge(roleFilteredAlerts);
    updateFilterTabs(roleFilteredAlerts);

    const filtered = filterAlertsByCategory(roleFilteredAlerts, currentFilter);

    if (roleFilteredAlerts.length === 0) {
      listEl.innerHTML = "";
      emptyEl.textContent = emptyMessageForFilter("all");
      emptyEl.hidden = false;
      clearEmergencyMapMarkers();
      return;
    }

    renderAlertList(filtered);
    renderMap(filtered, patientNamesCache, currentFilter);

    await ensurePatientNames(roleFilteredAlerts);
    await ensureCaregiverNames(roleFilteredAlerts);

    renderAlertList(filtered);
    renderMap(filtered, patientNamesCache, currentFilter);
    requestAnimationFrame(() => emergencyMap?.invalidateSize());
  } catch (error) {
    console.error("Could not render emergency alerts:", error);
    if (listEl) listEl.innerHTML = "";
    if (emptyEl) {
      emptyEl.textContent = formatFirestoreError(error, "emergency alerts");
      emptyEl.hidden = false;
    }
  }
}

let loggedInRole = "";
let loggedInUid = "";
let assignedPatientIds = new Set();

let unsubscribeAlerts = null;

function startEmergenciesRealtime() {
  releaseFirestoreListener(unsubscribeAlerts);
  unsubscribeAlerts = subscribeAllEmergencyAlerts((alerts) => {
    void renderAlerts(alerts);
  }, (error) => {
    console.error("Emergencies page listener failed:", error);
    if (listEl) listEl.innerHTML = "";
    clearEmergencyMapMarkers();
    if (emptyEl) {
      emptyEl.textContent = formatFirestoreError(error, "emergency alerts");
      emptyEl.hidden = false;
    }
    if (activeBadgeEl) activeBadgeEl.hidden = true;
  });
}

initStaffAuth(async (profile) => {
  loggedInRole = profile.role || "";
  loggedInUid = profile.uid || "";

  if (loggedInRole.toLowerCase() === "therapist") {
    try {
      const allPatients = await fetchPatients();
      const assigned = allPatients.filter(p => p.assignedTherapistId === loggedInUid);
      assignedPatientIds = new Set(assigned.map(p => p.patientId));
    } catch (e) {
      console.error("Failed to load assigned patients for therapist:", e);
    }
  }

  ensureEmergencyMap();
  bindFilterTabs();
  bindRespondModal();
  bindCaregiverModal();
  bindResolveModal();
  bindModalEscape();
  window.addEventListener("resize", () => emergencyMap?.invalidateSize());
  startEmergenciesRealtime();
});
