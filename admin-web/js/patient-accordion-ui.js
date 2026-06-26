import { comparePrefixedIds } from "./id-sort.js";

export function escapeHtml(str) {
  if (!str) return "";
  return String(str).replace(/[&<>"']/g, (match) => {
    const map = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };
    return map[match];
  });
}

export function sortPatientsForAccordion(patients) {
  return [...patients].sort((a, b) =>
    comparePrefixedIds(a.patientId, b.patientId),
  );
}

/**
 * Renders a list of patient accordion shells. Details load when a row is expanded.
 */
export function renderPatientAccordionList({
  containerEl,
  patients,
  countSuffix,
  emptyMessage,
  getCountLabel,
}) {
  if (!containerEl) return;

  const sorted = sortPatientsForAccordion(patients);
  if (sorted.length === 0) {
    containerEl.innerHTML = "";
    return;
  }

  containerEl.innerHTML = sorted
    .map((patient) => {
      const countLabel = getCountLabel ? getCountLabel(patient) : countSuffix;
      return `
        <details class="patient-accordion" data-patient-id="${escapeHtml(patient.patientId)}">
          <summary class="patient-accordion-header">
            <span class="patient-accordion-header-id">${escapeHtml(patient.patientId)}</span>
            <span class="patient-accordion-header-name">${escapeHtml(patient.name)}</span>
            <span class="patient-accordion-header-count" data-accordion-count>${escapeHtml(countLabel)}</span>
            <svg class="patient-accordion-header-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
              <polyline points="6 9 12 15 18 9"></polyline>
            </svg>
          </summary>
          <div class="patient-accordion-body" data-accordion-panel>
            <p class="patient-accordion-loading">Expand to load ${escapeHtml(countSuffix)}…</p>
          </div>
        </details>
      `;
    })
    .join("");
}

function captureAccordionPanelState(containerEl) {
  const openPatientIds = [];
  const loadedPanels = new Map();

  if (!containerEl) {
    return { openPatientIds, loadedPanels };
  }

  containerEl.querySelectorAll("details.patient-accordion").forEach((details) => {
    const patientId = details.dataset.patientId || "";
    if (!patientId) return;

    if (details.open) {
      openPatientIds.push(patientId);
    }

    const panel = details.querySelector("[data-accordion-panel]");
    if (panel?.dataset.loaded === "true") {
      loadedPanels.set(patientId, panel.innerHTML);
    }
  });

  return { openPatientIds, loadedPanels };
}

async function loadAccordionPanel({
  details,
  onLoadPatient,
  countSuffix = "records",
}) {
  const patientId = details.dataset.patientId || "";
  const panel = details.querySelector("[data-accordion-panel]");
  if (!panel || !patientId || panel.dataset.loaded === "true" || panel.dataset.loading === "true") {
    return;
  }

  panel.dataset.loading = "true";
  panel.innerHTML = `<p class="patient-accordion-loading">Loading…</p>`;

  try {
    const result = await onLoadPatient(patientId, details);
    panel.innerHTML =
      result?.html ||
      `<div class="patient-accordion-empty">${escapeHtml(result?.emptyMessage || `No ${escapeHtml(countSuffix)} found.`)}</div>`;
    if (result?.countLabel) {
      const countEl = details.querySelector("[data-accordion-count]");
      if (countEl) countEl.textContent = result.countLabel;
    }
    panel.dataset.loaded = "true";
  } catch (error) {
    console.error("Patient accordion load failed:", error);
    panel.innerHTML = `<div class="patient-accordion-empty text-danger">${escapeHtml(error?.message || "Could not load data for this patient.")}</div>`;
    panel.dataset.loaded = "false";
  } finally {
    panel.dataset.loading = "false";
  }
}

export function bindPatientAccordionLoader({
  containerEl,
  onLoadPatient,
  singleOpen = true,
  countSuffix = "records",
}) {
  if (!containerEl) return;

  // <details> toggle events do not bubble; capture phase is required for delegation.
  containerEl.addEventListener(
    "toggle",
    async (event) => {
      const details = event.target;
      if (!(details instanceof HTMLDetailsElement)) return;
      if (!details.matches("details.patient-accordion")) return;
      if (!containerEl.contains(details)) return;

      if (singleOpen && details.open) {
        containerEl.querySelectorAll("details.patient-accordion[open]").forEach((openEl) => {
          if (openEl !== details) openEl.open = false;
        });
      }

      if (!details.open) return;

      await loadAccordionPanel({ details, onLoadPatient, countSuffix });
    },
    true,
  );
}

export function restorePatientAccordionState({
  containerEl,
  openPatientIds = [],
  loadedPanels = new Map(),
  onLoadPatient,
  countSuffix = "records",
}) {
  if (!containerEl) return;

  openPatientIds.forEach((patientId) => {
    const details = containerEl.querySelector(
      `details.patient-accordion[data-patient-id="${CSS.escape(patientId)}"]`,
    );
    if (!details) return;

    details.open = true;
    const panel = details.querySelector("[data-accordion-panel]");
    if (!panel) return;

    const cachedHtml = loadedPanels.get(patientId);
    if (cachedHtml) {
      panel.innerHTML = cachedHtml;
      panel.dataset.loaded = "true";
      panel.dataset.loading = "false";
      return;
    }

    if (typeof onLoadPatient === "function") {
      void loadAccordionPanel({ details, onLoadPatient, countSuffix });
    }
  });
}

export function capturePatientAccordionState(containerEl) {
  return captureAccordionPanelState(containerEl);
}

export function updatePatientAccordionCounts(containerEl, countByPatientId, formatCount) {
  if (!containerEl || typeof formatCount !== "function") return;

  containerEl.querySelectorAll("details.patient-accordion").forEach((details) => {
    const patientId = details.dataset.patientId || "";
    if (!countByPatientId.has(patientId)) return;

    const count = countByPatientId.get(patientId);
    if (typeof count !== "number") return;

    const countEl = details.querySelector("[data-accordion-count]");
    if (countEl) countEl.textContent = formatCount(count);
  });
}

export function refreshPatientAccordionPanel(containerEl, patientId, onLoadPatient) {
  if (!containerEl || !patientId) return null;
  const details = containerEl.querySelector(
    `details.patient-accordion[data-patient-id="${CSS.escape(patientId)}"]`,
  );
  if (!details) return null;

  const panel = details.querySelector("[data-accordion-panel]");
  if (!panel) return details;

  panel.dataset.loaded = "false";
  panel.dataset.loading = "false";

  if (details.open && typeof onLoadPatient === "function") {
    void loadAccordionPanel({ details, onLoadPatient });
  } else {
    panel.innerHTML = `<p class="patient-accordion-loading">Expand to load details…</p>`;
  }

  return details;
}
