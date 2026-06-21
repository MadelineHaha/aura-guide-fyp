import {
  addDoc,
  collection,
  limit,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  Timestamp,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { getStaffSession } from "./staff-auth.js";
import { trackFirestoreListener } from "./firestore-realtime.js";

export const ACTIVITY_LOGS_COLLECTION = "activityLogs";

const IP_CACHE_MS = 5 * 60 * 1000;
const IP_LOOKUP_TIMEOUT_MS = 2500;
let cachedClientIp = null;
let cachedClientIpAt = 0;

async function resolveClientIpAddress() {
  const now = Date.now();
  if (cachedClientIp && now - cachedClientIpAt < IP_CACHE_MS) {
    return cachedClientIp;
  }

  const endpoints = [
    "https://api.ipify.org?format=json",
    "https://api64.ipify.org?format=json",
    "https://ifconfig.me/ip",
    "https://icanhazip.com",
  ];

  for (const endpoint of endpoints) {
    try {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 5000);
      const response = await fetch(endpoint, { signal: controller.signal });
      clearTimeout(timeout);
      if (!response.ok) continue;

      const body = (await response.text()).trim();
      let ip = "";

      if (endpoint.includes("format=json")) {
        const data = JSON.parse(body);
        ip = String(data?.ip || "").trim();
      } else if (/^[\d.]+$/.test(body) || body.includes(":")) {
        ip = body;
      }

      if (!ip) continue;

      cachedClientIp = ip;
      cachedClientIpAt = now;
      return ip;
    } catch (error) {
      console.warn(`Could not resolve client IP from ${endpoint}:`, error);
    }
  }

  return cachedClientIp || "—";
}

async function resolveClientIpAddressQuick() {
  return Promise.race([
    resolveClientIpAddress(),
    new Promise((resolve) => {
      setTimeout(() => resolve(cachedClientIp || "—"), IP_LOOKUP_TIMEOUT_MS);
    }),
  ]);
}

export async function warmUpActivityLogIpCache() {
  await resolveClientIpAddress();
}

function staffActor() {
  const session = getStaffSession();
  return {
    userName:
      session?.name?.trim() ||
      session?.fullName?.trim() ||
      session?.email?.trim() ||
      "Staff",
    userId: session?.staffID?.trim() || session?.staffId?.trim() || session?.uid || "—",
  };
}

function timestampToDate(value) {
  const date =
    value instanceof Timestamp
      ? value.toDate()
      : value?.toDate?.()
        ? value.toDate()
        : value instanceof Date
          ? value
          : null;
  if (!date || Number.isNaN(date.getTime())) return null;
  return date;
}

function formatTimestamp(value) {
  const date = timestampToDate(value);
  if (!date) return "—";
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  const hh = String(date.getHours()).padStart(2, "0");
  const mm = String(date.getMinutes()).padStart(2, "0");
  const ss = String(date.getSeconds()).padStart(2, "0");
  return `${y}-${m}-${d} ${hh}:${mm}:${ss}`;
}

export function mapActivityLogDoc(docSnap) {
  const data = docSnap.data() || {};
  const timestampDate = timestampToDate(data.timestamp);
  return {
    id: docSnap.id,
    timestamp: formatTimestamp(timestampDate),
    timestampMs: timestampDate ? timestampDate.getTime() : 0,
    userName: data.userName || "—",
    userId: data.userId || "—",
    action: data.action || "—",
    details: data.details || "",
    type: data.type || "info",
    ipAddress: data.ipAddress || "—",
    source: data.source || "—",
  };
}

export async function logActivity({
  userName,
  userId,
  action,
  details,
  type = "info",
  ipAddress = "—",
  source = "admin",
}) {
  const actionText = String(action || "").trim();
  const detailsText = String(details || "").trim();
  if (!actionText) return;

  try {
    await addDoc(collection(db, ACTIVITY_LOGS_COLLECTION), {
      timestamp: Timestamp.now(),
      userName: String(userName || "—").trim() || "—",
      userId: String(userId || "—").trim() || "—",
      action: actionText,
      details: detailsText,
      type,
      ipAddress: String(ipAddress || "—").trim() || "—",
      source,
    });
  } catch (error) {
    const code = error?.code || "";
    if (code === "permission-denied") {
      console.error(
        "Activity log write denied. Deploy Firestore rules: firebase deploy --only firestore:rules",
        error,
      );
    } else {
      console.warn("Activity log write failed:", error);
    }
  }
}

export async function logStaffActivity({
  action,
  details,
  type = "info",
  ipAddress,
}) {
  const actor = staffActor();
  const resolvedIp =
    ipAddress && ipAddress !== "—" && ipAddress !== "Mobile app"
      ? ipAddress
      : await resolveClientIpAddressQuick();
  await logActivity({
    ...actor,
    action,
    details,
    type,
    ipAddress: resolvedIp,
    source: "admin",
  });
}

export async function logWarningActivity({ action, details, ipAddress, source = "admin", userName, userId }) {
  await logActivity({
    userName: userName || staffActor().userName,
    userId: userId || staffActor().userId,
    action,
    details,
    type: "warning",
    ipAddress:
      ipAddress && ipAddress !== "—" && ipAddress !== "Mobile app"
        ? ipAddress
        : await resolveClientIpAddressQuick(),
    source,
  });
}

/** Security events that may occur before authentication (failed login, lockout). */
export async function logSecurityAudit({
  action,
  details,
  userName = "Unknown",
  userId = "—",
  source = "admin",
}) {
  const ip = await resolveClientIpAddressQuick();
  await logActivity({
    userName,
    userId,
    action,
    details,
    type: "security",
    ipAddress: ip,
    source,
  });
}

export async function logSystemActivity({ action, details, type = "info" }) {
  await logActivity({
    userName: "System",
    userId: "—",
    action,
    details,
    type,
    ipAddress: "System",
    source: "system",
  });
}

export function subscribeActivityLogs(onChange, onError) {
  const q = query(
    collection(db, ACTIVITY_LOGS_COLLECTION),
    orderBy("timestamp", "desc"),
    limit(500),
  );

  const unsubscribe = onSnapshot(
    q,
    (snapshot) => {
      onChange(snapshot.docs.map(mapActivityLogDoc));
    },
    onError,
  );

  trackFirestoreListener(unsubscribe);
  return unsubscribe;
}
