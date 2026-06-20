import {
  collection,
  doc,
  getDocs,
  onSnapshot,
  query,
  updateDoc,
  where,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { trackFirestoreListener } from "./firestore-realtime.js";
import { USERS_COLLECTION } from "./user-patients-service.js";

export const EMERGENCY_ALERTS_COLLECTION = "emergencyalerts";
export const ALERT_STATUS_ACTIVE = "Active";
export const ALERT_STATUS_RESPONDED = "Responded";
export const ALERT_STATUS_RESOLVED = "Resolved";
export const RESPONSE_ACTION_CAREGIVER = "caregiver";
export const RESPONSE_ACTION_EMERGENCY = "emergency";
export const EMERGENCIES_PAGE = "emergencies.html";

const ALERT_ID_PATTERN = /^E\d{5}$/;

function readField(data, pascal, camel) {
  const value = data[pascal] ?? data[camel];
  if (value == null) return "";
  return String(value).trim();
}

function timestampToDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

function parseErdDateTime(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(trimmed)) return null;
  const [datePart, timePart] = trimmed.split(" ");
  const parsed = new Date(`${datePart}T${timePart}`);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function formatAlertTime(data) {
  const erdDateTime = readField(data, "DateTime", "dateTime");
  if (erdDateTime) return erdDateTime;

  const legacyLabel = readField(data, "", "dateTimeLabel");
  if (legacyLabel) return legacyLabel;

  const date = timestampToDate(data.dateTime);
  if (!date) return "—";
  return date.toLocaleString("en-GB", {
    day: "2-digit",
    month: "short",
    year: "numeric",
    hour: "2-digit",
    minute: "2-digit",
  });
}

function alertSortTime(alert) {
  return (
    parseErdDateTime(alert.dateTime)?.getTime() ||
    timestampToDate(alert.dateTime)?.getTime() ||
    0
  );
}

function isActiveAlert(alert) {
  return normalizeAlertStatus(alert?.status) === ALERT_STATUS_ACTIVE;
}

function normalizeAlertStatus(status) {
  const value = String(status || "").trim();
  if (/^active$/i.test(value)) return ALERT_STATUS_ACTIVE;
  if (/^responded$/i.test(value)) return ALERT_STATUS_RESPONDED;
  if (/^resolved$/i.test(value)) return ALERT_STATUS_RESOLVED;
  return value || ALERT_STATUS_ACTIVE;
}

function isOpenAlert(alert) {
  const status = String(alert?.status || "").trim();
  return status === ALERT_STATUS_ACTIVE || status === ALERT_STATUS_RESPONDED;
}

export function getBusyCaregiverIds(alerts, { excludeAlertId = null } = {}) {
  const busy = new Set();
  for (const alert of alerts) {
    if (!isOpenAlert(alert)) continue;
    if (excludeAlertId && alert.alertId === excludeAlertId) continue;
    const caregiverId = String(alert.caregiverId || "").trim();
    if (caregiverId) busy.add(caregiverId);
  }
  return busy;
}

export function mapEmergencyAlertDoc(docSnap) {
  const data = docSnap.data() || {};
  const alertId =
    readField(data, "AlertID", "alertId") || String(docSnap.id || "").trim();
  if (!ALERT_ID_PATTERN.test(alertId)) return null;

  const userId =
    readField(data, "UserID", "userId") ||
    readField(data, "UserID", "userID") ||
    readField(data, "", "patientId") ||
    "Unknown";

  const dateTime =
    readField(data, "DateTime", "dateTime") || data.dateTime || null;

  const status = normalizeAlertStatus(
    readField(data, "Status", "status") || ALERT_STATUS_ACTIVE,
  );

  return {
    id: docSnap.id,
    alertId,
    userId,
    alertType: readField(data, "AlertType", "alertType") || "Manual SOS",
    status,
    location: readField(data, "Location", "location"),
    dateTime,
    dateTimeLabel: formatAlertTime(data),
    resolutionNotes: readField(data, "ResolutionNotes", "resolutionNotes"),
    staffId:
      readField(data, "StaffID", "staffId") ||
      readField(data, "StaffID", "staffID"),
    caregiverId:
      readField(data, "CaregiverID", "caregiverId") ||
      readField(data, "CaregiverID", "caregiverID"),
  };
}

function sortAlertsByTime(alerts) {
  return [...alerts].sort((a, b) => alertSortTime(b) - alertSortTime(a));
}

function sortActiveAlerts(alerts) {
  return sortAlertsByTime(alerts).filter(isActiveAlert);
}

let patientNameCache = null;
let patientNameCachePromise = null;

async function loadPatientNameMap() {
  if (patientNameCache) return patientNameCache;
  if (patientNameCachePromise) return patientNameCachePromise;

  patientNameCachePromise = (async () => {
    const snap = await getDocs(collection(db, USERS_COLLECTION));
    const map = new Map();
    for (const docSnap of snap.docs) {
      const data = docSnap.data();
      const patientId = String(data.userId || data.userID || "").trim();
      if (!patientId) continue;
      map.set(patientId, data.name || patientId);
    }
    patientNameCache = map;
    return map;
  })();

  return patientNameCachePromise;
}

export async function resolvePatientName(userId) {
  const id = String(userId || "").trim();
  if (!id || id === "Unknown") return "Unknown patient";
  const map = await loadPatientNameMap();
  return map.get(id) || id;
}

export function invalidatePatientNameCache() {
  patientNameCache = null;
  patientNameCachePromise = null;
}

/**
 * Real-time emergency alerts — same pattern as `subscribePatients`.
 * Fires on every Firestore change with the current active alert list.
 */
export function subscribeActiveEmergencyAlerts(onData, onError) {
  let listenerReady = false;
  let previousActiveIds = new Set();

  const unsub = onSnapshot(
    collection(db, EMERGENCY_ALERTS_COLLECTION),
    (snap) => {
      const alerts = sortActiveAlerts(
        snap.docs.map(mapEmergencyAlertDoc).filter(Boolean),
      );
      const currentIds = new Set(alerts.map((alert) => alert.alertId));

      const newAlerts = [];
      if (listenerReady) {
        for (const alert of alerts) {
          if (!previousActiveIds.has(alert.alertId)) {
            newAlerts.push(alert);
          }
        }
      }

      previousActiveIds = currentIds;
      listenerReady = true;

      onData({ alerts, newAlerts });
    },
    onError,
  );

  return trackFirestoreListener(unsub);
}

/** Indexed query for active alerts (`Status` field). */
export function subscribeActiveEmergencyAlertsQuery(onData, onError) {
  let listenerReady = false;
  let previousActiveIds = new Set();

  const q = query(
    collection(db, EMERGENCY_ALERTS_COLLECTION),
    where("Status", "==", ALERT_STATUS_ACTIVE),
  );

  const unsub = onSnapshot(
    q,
    (snap) => {
      const alerts = snap.docs
        .map(mapEmergencyAlertDoc)
        .filter(Boolean)
        .sort((a, b) => alertSortTime(b) - alertSortTime(a));

      const currentIds = new Set(alerts.map((alert) => alert.alertId));
      const newAlerts = [];

      if (listenerReady) {
        for (const alert of alerts) {
          if (!previousActiveIds.has(alert.alertId)) {
            newAlerts.push(alert);
          }
        }
      }

      previousActiveIds = currentIds;
      listenerReady = true;
      onData({ alerts, newAlerts });
    },
    onError,
  );

  return trackFirestoreListener(unsub);
}

/** Real-time list of every emergency alert (all statuses). */
export function subscribeAllEmergencyAlerts(onData, onError) {
  const unsub = onSnapshot(
    collection(db, EMERGENCY_ALERTS_COLLECTION),
    (snap) => {
      const alerts = sortAlertsByTime(
        snap.docs.map(mapEmergencyAlertDoc).filter(Boolean),
      );
      onData(alerts);
    },
    onError,
  );

  return trackFirestoreListener(unsub);
}

export function formatPatientDisplayName(userId, resolvedName) {
  const id = String(userId || "").trim();
  const name = String(resolvedName || "").trim();
  if (name && name !== id) return name;
  return "Unknown patient";
}

export function formatPatientLabel(userId, resolvedName) {
  const id = String(userId || "").trim();
  const name = formatPatientDisplayName(userId, resolvedName);
  return id ? `${name} (${id})` : name;
}

export function countActiveAlerts(alerts) {
  return alerts.filter(isActiveAlert).length;
}

export async function respondEmergencyAlert(
  alertId,
  { staffId, responseAction } = {},
) {
  const id = String(alertId || "").trim();
  const staff = String(staffId || "").trim();
  if (!id) throw new Error("Alert ID is required.");
  if (!staff) throw new Error("Staff ID is required.");

  const resolutionNotes =
    responseAction === RESPONSE_ACTION_EMERGENCY
      ? "Emergency services contacted"
      : "Caregiver assigned to patient location";

  await updateDoc(doc(db, EMERGENCY_ALERTS_COLLECTION, id), {
    Status: ALERT_STATUS_RESPONDED,
    StaffID: staff,
    ResolutionNotes: resolutionNotes,
  });
}

export async function assignCaregiverToAlert(
  alertId,
  { staffId, caregiverId, caregiverName } = {},
) {
  const id = String(alertId || "").trim();
  const staff = String(staffId || "").trim();
  const caregiver = String(caregiverId || "").trim();
  const name = String(caregiverName || "").trim() || caregiver;
  if (!id) throw new Error("Alert ID is required.");
  if (!staff) throw new Error("Staff ID is required.");
  if (!caregiver) throw new Error("Caregiver ID is required.");

  await updateDoc(doc(db, EMERGENCY_ALERTS_COLLECTION, id), {
    Status: ALERT_STATUS_RESPONDED,
    StaffID: staff,
    CaregiverID: caregiver,
    ResolutionNotes: `Caregiver assigned: ${name} (${caregiver})`,
  });
}

export async function resolveEmergencyAlert(
  alertId,
  { staffId, resolutionNotes } = {},
) {
  const id = String(alertId || "").trim();
  const staff = String(staffId || "").trim();
  const notes = String(resolutionNotes || "").trim();
  if (!id) throw new Error("Alert ID is required.");
  if (!staff) throw new Error("Staff ID is required.");
  if (!notes) throw new Error("Resolution note is required.");

  await updateDoc(doc(db, EMERGENCY_ALERTS_COLLECTION, id), {
    Status: ALERT_STATUS_RESOLVED,
    StaffID: staff,
    ResolutionNotes: notes,
  });
}
