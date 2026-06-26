import { initStaffAuth } from "./staff-shell.js";
import {
  fetchHealthRecordsByUserId,
  fetchHealthRecordCountsByUserId,
  createHealthRecord,
  getHealthRecordFileUrl,
  isHealthRecordImageMime,
  isHealthRecordPdfMime,
  isHealthRecordsAccessError,
  mimeTypeForHealthRecordFile,
} from "./health-records-service.js";
import { subscribePatients } from "./user-patients-service.js";
import { filterPatientsForClinicalPages, isAdmin, isDoctor } from "./staff-rbac.js";
import { formatFirestoreError } from "./staff-data-status.js";
import {
  bindPatientAccordionLoader,
  capturePatientAccordionState,
  escapeHtml,
  renderPatientAccordionList,
  refreshPatientAccordionPanel,
  restorePatientAccordionState,
  updatePatientAccordionCounts,
} from "./patient-accordion-ui.js";

const accordionListEl = document.getElementById("records-accordion-list");
const countEl = document.getElementById("records-count");
const emptyEl = document.getElementById("medical-records-empty");

const btnAddRecord = document.getElementById("btn-add-record");
const modalEl = document.getElementById("add-health-record-modal");
const closeBtn = document.getElementById("add-health-record-close");
const formEl = document.getElementById("add-health-record-form");
const patientSelectEl = document.getElementById("add-health-record-patient-select");
const typeEl = document.getElementById("add-health-record-type");
const typeOtherFieldEl = document.getElementById("add-health-record-type-other-field");
const typeOtherEl = document.getElementById("add-health-record-type-other");
const summaryEl = document.getElementById("add-health-record-summary");
const fileEl = document.getElementById("add-health-record-file");
const fileNameEl = document.getElementById("add-health-record-file-name");
const errorEl = document.getElementById("add-health-record-error");
const submitBtn = formEl?.querySelector('[type="submit"]');

const viewModalEl = document.getElementById("health-record-view-modal");
const viewCloseBtn = document.getElementById("health-record-view-close");
const viewTitleEl = document.getElementById("health-record-view-title");
const viewContentEl = document.getElementById("health-record-view-content");
const viewErrorEl = document.getElementById("health-record-view-error");
const viewLoadingEl = document.getElementById("health-record-view-loading");
const viewOpenTabBtn = document.getElementById("health-record-view-open-tab");

let loggedInUid = null;
let loggedInName = null;
let loggedInRole = null;
let currentAssignedPatients = [];
const recordCountByPatient = new Map();
let recordCountPrefetchToken = 0;

function formatRecordCountLabel(count) {
  return `${count} record${count === 1 ? "" : "s"}`;
}

function applyRecordCounts(counts, patients) {
  patients.forEach((patient) => {
    recordCountByPatient.set(patient.patientId, counts.get(patient.patientId) || 0);
  });
  updatePatientAccordionCounts(
    accordionListEl,
    recordCountByPatient,
    formatRecordCountLabel,
  );
}

async function prefetchRecordCounts(patients) {
  const token = ++recordCountPrefetchToken;
  try {
    const counts = await fetchHealthRecordCountsByUserId();
    if (token !== recordCountPrefetchToken) return;
    applyRecordCounts(counts, patients);
  } catch (error) {
    console.error("Health record count prefetch failed:", error);
  }
}

let currentViewUrl = null;

function formatRecordDate(value) {
  if (!value || value === "—") return "—";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return String(value);
  return parsed.toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  });
}

function renderFileCell(record) {
  if (!record.hasFile && !record.filePath && !record.hasInlineFile) {
    return `<span class="text-secondary">—</span>`;
  }

  const fileName = record.filePath
    ? escapeHtml(String(record.filePath).split("/").pop() || record.fileType || "File")
    : escapeHtml(record.fileType || "File");

  return `
    <div class="health-record-file-cell">
      <span class="text-secondary">${fileName}</span>
      <button
        type="button"
        class="btn-link btn-view-health-record"
        data-record-id="${escapeHtml(record.recordId)}"
        data-record-title="${escapeHtml(record.description || record.type || "Medical report")}"
        data-file-type="${escapeHtml(record.fileType || "")}"
      >
        View report
      </button>
    </div>
  `;
}

function closeHealthRecordViewModal() {
  if (viewModalEl) viewModalEl.hidden = true;
  if (viewContentEl) viewContentEl.innerHTML = "";
  if (viewErrorEl) {
    viewErrorEl.hidden = true;
    viewErrorEl.textContent = "";
  }
  if (viewLoadingEl) viewLoadingEl.hidden = true;
  currentViewUrl = null;
}

function renderHealthRecordPreview(url, fileType) {
  const mime = url.startsWith("data:")
    ? (url.match(/^data:([^;]+);/)?.[1] || mimeTypeForHealthRecordFile(fileType))
    : mimeTypeForHealthRecordFile(fileType);

  if (isHealthRecordImageMime(mime)) {
    return `<img class="health-record-view-image" src="${url}" alt="Medical report" />`;
  }

  if (isHealthRecordPdfMime(mime, fileType)) {
    return `<iframe class="health-record-view-frame" src="${url}" title="Medical report PDF"></iframe>`;
  }

  return `
    <p class="health-record-view-fallback">
      This file type cannot be previewed in the browser.
      <a href="${url}" target="_blank" rel="noopener noreferrer">Download or open file</a>
    </p>
  `;
}

async function openHealthRecordViewModal({ recordId, recordTitle, fileType }) {
  if (!viewModalEl || !viewContentEl) return;

  viewModalEl.hidden = false;
  if (viewTitleEl) viewTitleEl.textContent = recordTitle || "Medical report";
  viewContentEl.innerHTML = "";
  if (viewErrorEl) {
    viewErrorEl.hidden = true;
    viewErrorEl.textContent = "";
  }
  if (viewLoadingEl) viewLoadingEl.hidden = false;

  try {
    const url = await getHealthRecordFileUrl(recordId);
    if (!url) {
      throw new Error("No file is attached to this record, or it could not be loaded.");
    }

    currentViewUrl = url;
    viewContentEl.innerHTML = renderHealthRecordPreview(url, fileType);
    if (viewOpenTabBtn) viewOpenTabBtn.hidden = false;
  } catch (error) {
    console.error(error);
    if (viewErrorEl) {
      viewErrorEl.textContent = error?.message || "Could not load the medical report.";
      viewErrorEl.hidden = false;
    }
    if (viewOpenTabBtn) viewOpenTabBtn.hidden = true;
  } finally {
    if (viewLoadingEl) viewLoadingEl.hidden = true;
  }
}

function renderRecordsTable(records) {
  if (!records.length) {
    return {
      html: `<div class="patient-accordion-empty">No medical records for this patient.</div>`,
      countLabel: "0 records",
    };
  }

  const rows = records
    .map((record) => {
      const fileCell = renderFileCell(record);

      return `
        <tr>
          <td class="font-medium">${formatRecordDate(record.dateCreated)}</td>
          <td><span class="status-badge">${escapeHtml(record.type || "General")}</span></td>
          <td>
            <div class="truncate-text" style="max-width: 320px;">
              ${escapeHtml(record.description || "—")}
            </div>
          </td>
          <td><span class="text-secondary">${escapeHtml(record.doctor || "—")}</span></td>
          <td>${fileCell}</td>
        </tr>
      `;
    })
    .join("");

  return {
    html: `
      <table class="data-table">
        <thead>
          <tr>
            <th>Date</th>
            <th>Type</th>
            <th>Summary</th>
            <th>Provider</th>
            <th>File</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    `,
    countLabel: `${records.length} record${records.length === 1 ? "" : "s"}`,
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
  countEl.textContent = `${currentAssignedPatients.length} patient${currentAssignedPatients.length === 1 ? "" : "s"} — expand a row to view medical records`;

  renderPatientAccordionList({
    containerEl: accordionListEl,
    patients: currentAssignedPatients,
    countSuffix: "records",
    getCountLabel: (patient) => {
      const cached = recordCountByPatient.get(patient.patientId);
      return typeof cached === "number"
        ? formatRecordCountLabel(cached)
        : "…";
    },
  });

  restorePatientAccordionState({
    containerEl: accordionListEl,
    openPatientIds,
    loadedPanels,
    onLoadPatient: loadRecordsForPatient,
    countSuffix: "records",
  });
}

async function loadRecordsForPatient(patientId) {
  try {
    const records = await fetchHealthRecordsByUserId(patientId);
    recordCountByPatient.set(patientId, records.length);
    return renderRecordsTable(records);
  } catch (error) {
    if (isHealthRecordsAccessError(error)) {
      throw new Error(
        formatFirestoreError(error, "health records") ||
          "You do not have permission to view health records.",
      );
    }
    throw error;
  }
}

function populatePatientDropdown() {
  if (!patientSelectEl) return;
  patientSelectEl.innerHTML = '<option value="">Choose a patient...</option>';
  currentAssignedPatients.forEach((patient) => {
    const option = document.createElement("option");
    option.value = patient.patientId;
    option.textContent = `${patient.name} (${patient.patientId})`;
    patientSelectEl.appendChild(option);
  });
}

function closeAddRecordModal() {
  modalEl.hidden = true;
}

if (btnAddRecord) {
  btnAddRecord.addEventListener("click", () => {
    formEl.reset();
    errorEl.hidden = true;
    fileNameEl.textContent = "No file chosen";
    typeOtherFieldEl.hidden = true;
    typeOtherEl.required = false;
    populatePatientDropdown();
    modalEl.hidden = false;
  });
}

if (closeBtn) {
  closeBtn.addEventListener("click", closeAddRecordModal);
}

if (typeEl) {
  typeEl.addEventListener("change", () => {
    const isOther = typeEl.value === "Other";
    typeOtherFieldEl.hidden = !isOther;
    typeOtherEl.required = isOther;
    if (!isOther) typeOtherEl.value = "";
  });
}

if (fileEl) {
  fileEl.addEventListener("change", () => {
    const file = fileEl.files[0];
    fileNameEl.textContent = file ? file.name : "No file chosen";
  });
}

if (formEl) {
  formEl.addEventListener("submit", async (e) => {
    e.preventDefault();
    errorEl.hidden = true;

    const patientId = patientSelectEl.value;
    if (!patientId) {
      errorEl.textContent = "Please select a patient.";
      errorEl.hidden = false;
      return;
    }

    let recordType = typeEl.value;
    if (recordType === "Other") {
      recordType = typeOtherEl.value.trim();
    }

    const title = summaryEl.value.trim();
    const file = fileEl.files[0];

    submitBtn.disabled = true;
    const originalText = submitBtn.innerHTML;
    submitBtn.innerHTML = "Saving...";

    try {
      const errorMsg = await createHealthRecord({
        userId: patientId,
        staffId: loggedInUid,
        recordType,
        title,
        file,
        staffName: loggedInName,
        staffRole: loggedInRole,
        onPhase: (phase) => {
          if (phase === "uploading") submitBtn.innerHTML = "Uploading file...";
          else if (phase === "saving") submitBtn.innerHTML = "Saving record...";
        },
      });

      if (errorMsg) {
        errorEl.textContent = errorMsg;
        errorEl.hidden = false;
      } else {
        closeAddRecordModal();
        refreshPatientAccordionPanel(accordionListEl, patientId, loadRecordsForPatient);
        renderPatientList();
        void prefetchRecordCounts(currentAssignedPatients);
      }
    } catch (err) {
      console.error(err);
      errorEl.textContent = err.message || "Failed to add record.";
      errorEl.hidden = false;
    } finally {
      submitBtn.disabled = false;
      submitBtn.innerHTML = originalText;
    }
  });
}

bindPatientAccordionLoader({
  containerEl: accordionListEl,
  onLoadPatient: loadRecordsForPatient,
  countSuffix: "records",
});

if (accordionListEl) {
  accordionListEl.addEventListener("click", (event) => {
    const viewBtn = event.target.closest(".btn-view-health-record");
    if (!viewBtn) return;

    void openHealthRecordViewModal({
      recordId: viewBtn.dataset.recordId || "",
      recordTitle: viewBtn.dataset.recordTitle || "Medical report",
      fileType: viewBtn.dataset.fileType || "",
    });
  });
}

if (viewCloseBtn) {
  viewCloseBtn.addEventListener("click", closeHealthRecordViewModal);
}

if (viewModalEl) {
  viewModalEl.addEventListener("click", (event) => {
    if (event.target === viewModalEl) closeHealthRecordViewModal();
  });
}

if (viewOpenTabBtn) {
  viewOpenTabBtn.addEventListener("click", () => {
    if (currentViewUrl) {
      window.open(currentViewUrl, "_blank", "noopener,noreferrer");
    }
  });
}

initStaffAuth((profile) => {
  loggedInUid = profile.uid;
  loggedInName = profile.name;
  loggedInRole = profile.role;

  if (btnAddRecord && (isDoctor(profile.role) || isAdmin(profile.role))) {
    btnAddRecord.hidden = false;
  }

  subscribePatients(
    (allPatients) => {
      currentAssignedPatients = filterPatientsForClinicalPages(allPatients, profile);
      renderPatientList();
      void prefetchRecordCounts(currentAssignedPatients);
    },
    (error) => {
      console.error("Patient subscription error:", error);
      countEl.textContent = "Error loading patients.";
      accordionListEl.innerHTML = `<div class="patient-accordion-empty text-danger">${escapeHtml(formatFirestoreError(error, "patients"))}</div>`;
    },
  );
});
