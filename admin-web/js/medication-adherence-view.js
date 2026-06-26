import {
  fetchReportsData,
  REPORT_RANGES,
  MED_ADHERENCE_STATUS,
} from "./reports-service.js";
import { escapeHtml } from "./patient-accordion-ui.js";

export function isActivePatient(patient) {
  const status = String(patient?.accountStatus || patient?.status || "Active")
    .trim()
    .toLowerCase();
  return status !== "inactive";
}

export function parseAdherenceRangeKey(raw) {
  if (raw === "today") return REPORT_RANGES.TODAY;
  if (raw === "month") return REPORT_RANGES.MONTH;
  return REPORT_RANGES.ALL;
}

export function hasActiveMedication(row) {
  return row.medAdherenceStatus !== MED_ADHERENCE_STATUS.NA;
}

export function isLowMedicationAdherence(row) {
  return (
    row.medAdherenceStatus === MED_ADHERENCE_STATUS.CALCULATED &&
    typeof row.medAdherence === "number" &&
    row.medAdherence < 100
  );
}

export function medAdherenceBadgeClass(percent) {
  const value = Number(percent ?? 0);
  if (value >= 90) return "reports-med-badge--good";
  if (value >= 60) return "reports-med-badge--medium";
  return "reports-med-badge--low";
}

export function medAdherenceBadgeHtml(row) {
  const status = row.medAdherenceStatus || MED_ADHERENCE_STATUS.CALCULATED;
  if (status === MED_ADHERENCE_STATUS.PENDING) {
    return '<span class="reports-med-badge reports-med-badge--pending">Pending</span>';
  }
  if (status === MED_ADHERENCE_STATUS.NA) {
    return '<span class="reports-med-badge reports-med-badge--na">No Medication</span>';
  }
  const badgeClass = medAdherenceBadgeClass(row.medAdherence);
  return `<span class="reports-med-badge ${badgeClass}">${escapeHtml(String(row.medAdherence))}%</span>`;
}

export function sortMedicationRows(rows) {
  return [...rows].sort((a, b) => {
    const aLow = isLowMedicationAdherence(a) ? 0 : 1;
    const bLow = isLowMedicationAdherence(b) ? 0 : 1;
    if (aLow !== bLow) return aLow - bLow;

    if (
      a.medAdherenceStatus === MED_ADHERENCE_STATUS.CALCULATED &&
      b.medAdherenceStatus === MED_ADHERENCE_STATUS.CALCULATED
    ) {
      const adherenceDiff = Number(a.medAdherence ?? 0) - Number(b.medAdherence ?? 0);
      if (adherenceDiff !== 0) return adherenceDiff;
    }

    return String(a.name || "").localeCompare(String(b.name || ""));
  });
}

export function medAdherenceLabelForExport(row) {
  const status = row.medAdherenceStatus || MED_ADHERENCE_STATUS.CALCULATED;
  if (status === MED_ADHERENCE_STATUS.PENDING) return "Pending";
  if (status === MED_ADHERENCE_STATUS.NA) return "N/A";
  return `${row.medAdherence}%`;
}

export async function loadMedicationAdherenceRows(activePatients, rangeKey) {
  const report = await fetchReportsData(rangeKey);
  const scopedIds = new Set(activePatients.map((patient) => patient.patientId));
  const allRows = sortMedicationRows(
    (report.userActivity || [])
      .filter((row) => scopedIds.has(row.patientId))
      .filter((row) => hasActiveMedication(row)),
  );
  const lowRows = allRows.filter((row) => isLowMedicationAdherence(row));
  return { allRows, lowRows };
}
