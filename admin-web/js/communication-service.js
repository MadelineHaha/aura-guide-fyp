import {
  collection,
  doc,
  getDoc,
  getDocs,
  onSnapshot,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  where,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { trackFirestoreListener } from "./firestore-realtime.js";
import {
  fetchPatients,
  mapUserDoc,
  USERS_COLLECTION,
} from "./user-patients-service.js";

export const CONVERSATIONS_COLLECTION = "conversations";
export const MESSAGES_COLLECTION = "messages";
export const MESSAGE_COUNTER_PATH = ["system", "messageCounter"];
export const CONVERSATION_COUNTER_PATH = ["system", "conversationCounter"];

const CONVERSATION_ID_PATTERN = /^C\d{5}$/;
const MESSAGE_ID_PATTERN = /^G\d{5}$/;
const PARTICIPANT_ID_PATTERN = /^(U|S)\d{5}$/;

const AVATAR_COLORS = ["teal", "purple", "green", "pink", "orange"];

function timestampToDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function normalizeStatus(value) {
  return String(value || "").trim();
}

function isActiveConversationStatus(status) {
  return normalizeStatus(status).toLowerCase() === "active";
}

function pickParticipantId(data, keys) {
  for (const key of keys) {
    const value = data[key];
    if (value) return String(value).trim();
  }
  return "";
}

export function mapConversationDoc(docSnap) {
  const data = docSnap.data();
  return {
    conversationId: data.conversationId || docSnap.id,
    createdDate: data.createdDate ?? data.createdAt ?? null,
    status: normalizeStatus(data.status) || "Active",
    participant1Id: pickParticipantId(data, [
      "participant1Id",
      "participant1ID",
      "Participant1ID",
    ]),
    participant2Id: pickParticipantId(data, [
      "participant2Id",
      "participant2ID",
      "Participant2ID",
    ]),
  };
}

export function mapMessageDoc(docSnap) {
  const data = docSnap.data();
  return {
    messageId: data.messageId || docSnap.id,
    conversationId:
      data.conversationId ||
      data.conversationID ||
      data["Conversation ID"] ||
      "",
    messageType: normalizeStatus(data.messageType) || "Text",
    content: data.content || "",
    callDuration: data.callDuration ?? null,
    timestamp: data.timestamp ?? data.Timestamp ?? null,
    deliveryStatus: normalizeStatus(data.deliveryStatus) || "Sent",
    senderId: pickParticipantId(data, ["senderId", "senderID", "SenderID"]),
    receiverId: pickParticipantId(data, ["receiverId", "receiverID", "ReceiverID"]),
  };
}

function avatarColorForId(id) {
  let hash = 0;
  const text = String(id || "");
  for (let i = 0; i < text.length; i += 1) {
    hash = (hash + text.charCodeAt(i)) % AVATAR_COLORS.length;
  }
  return AVATAR_COLORS[hash] || "teal";
}

function getOtherParticipantId(conversation, staffId) {
  const staff = String(staffId || "").trim();
  if (conversation.participant1Id === staff) return conversation.participant2Id;
  if (conversation.participant2Id === staff) return conversation.participant1Id;
  return "";
}

export function formatChatListTime(value) {
  const date = timestampToDate(value);
  if (!date) return "—";

  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startOfDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const diffDays = Math.round((startOfToday - startOfDate) / 86400000);

  if (diffDays === 0) {
    return date.toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
    });
  }
  if (diffDays === 1) return "Yesterday";
  if (diffDays < 7) {
    return date.toLocaleDateString("en-US", { weekday: "long" });
  }
  return date.toLocaleDateString("en-GB", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

function formatDividerLabel(value) {
  const date = timestampToDate(value);
  if (!date) return "Earlier";

  const now = new Date();
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startOfDate = new Date(date.getFullYear(), date.getMonth(), date.getDate());
  const diffDays = Math.round((startOfToday - startOfDate) / 86400000);

  if (diffDays === 0) {
    return date.toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
    });
  }
  if (diffDays === 1) return "Yesterday";
  return date.toLocaleDateString("en-GB", {
    weekday: "long",
    day: "numeric",
    month: "short",
  });
}

function formatMessageClock(value) {
  const date = timestampToDate(value);
  if (!date) return "—";
  return date.toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  });
}

function buildPatientNameMap(patients) {
  const map = new Map();
  patients.forEach((patient) => {
    if (patient.patientId && patient.patientId !== "—") {
      map.set(patient.patientId, patient.name || patient.patientId);
    }
  });
  return map;
}

function isPatientAccountActive(patient) {
  return (patient?.accountStatus || "Active").toLowerCase() !== "inactive";
}

function isPermissionDenied(error) {
  const code = error?.code || "";
  const message = String(error?.message || "").toLowerCase();
  return (
    code === "permission-denied" ||
    message.includes("missing or insufficient permissions") ||
    message.includes("insufficient permissions")
  );
}

function mapUserForConversation(docSnap) {
  const data = docSnap.data();
  return {
    id: docSnap.id,
    patientId: String(data.userId || "").trim(),
    name: String(data.name || "").trim() || "—",
    accountStatus: String(data.status || "Active").trim() || "Active",
  };
}

async function fetchUsersForConversation() {
  const patients = await fetchPatients();
  return patients.map((patient) => ({
    id: patient.id,
    patientId: String(patient.patientId || "").trim(),
    name: String(patient.name || "").trim() || "—",
    accountStatus: String(patient.accountStatus || "Active").trim() || "Active",
  }));
}

function formatCreatedDateString(date = new Date()) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  const hour = String(date.getHours()).padStart(2, "0");
  const minute = String(date.getMinutes()).padStart(2, "0");
  const second = String(date.getSeconds()).padStart(2, "0");
  return `${year}-${month}-${day} ${hour}:${minute}:${second}`;
}

async function fetchAllActiveConversationsForStaff(staffId) {
  const trimmedStaffId = String(staffId || "").trim();
  if (!PARTICIPANT_ID_PATTERN.test(trimmedStaffId)) {
    throw new Error("Your staff profile is missing a valid Staff ID (e.g. S00001).");
  }

  const q = query(
    collection(db, CONVERSATIONS_COLLECTION),
    where("status", "==", "Active"),
  );
  const snap = await getDocs(q);

  return snap.docs
    .map(mapConversationDoc)
    .filter(
      (conversation) =>
        isActiveConversationStatus(conversation.status) &&
        CONVERSATION_ID_PATTERN.test(conversation.conversationId) &&
        (conversation.participant1Id === trimmedStaffId ||
          conversation.participant2Id === trimmedStaffId),
    );
}

async function reserveConversationId() {
  const counterRef = doc(db, ...CONVERSATION_COUNTER_PATH);
  return runTransaction(db, async (transaction) => {
    const counterSnap = await transaction.get(counterRef);
    const next = counterSnap.exists() ? Number(counterSnap.data().next) || 1 : 1;
    const conversationId = `C${String(next).padStart(5, "0")}`;
    transaction.set(counterRef, { next: next + 1 }, { merge: true });
    return conversationId;
  });
}

async function fetchLatestMessageByConversationIds(conversationIds) {
  const latestByConversation = new Map();
  if (conversationIds.length === 0) return latestByConversation;

  await Promise.all(
    conversationIds.map(async (conversationId) => {
      const q = query(
        collection(db, MESSAGES_COLLECTION),
        where("conversationId", "==", conversationId),
      );
      const snap = await getDocs(q);
      const messages = snap.docs
        .map(mapMessageDoc)
        .filter((message) => MESSAGE_ID_PATTERN.test(message.messageId))
        .sort(
          (a, b) =>
            (timestampToDate(b.timestamp)?.getTime() || 0) -
            (timestampToDate(a.timestamp)?.getTime() || 0),
        );
      if (messages.length > 0) {
        latestByConversation.set(conversationId, messages[0]);
      }
    }),
  );

  return latestByConversation;
}

function buildStaffConversationThreads(
  staffId,
  patients,
  conversations,
  latestByConversation,
) {
  const activePatients = patients.filter(isPatientAccountActive);
  const patientNameById = buildPatientNameMap(activePatients);
  const activePatientIds = new Set(patientNameById.keys());

  const available = conversations.filter((conversation) => {
    const otherId = getOtherParticipantId(conversation, staffId);
    if (!otherId.startsWith("U")) return true;
    return activePatientIds.has(otherId);
  });

  const threads = available.map((conversation) => {
    const patientId = getOtherParticipantId(conversation, staffId);
    const lastMessage = latestByConversation.get(conversation.conversationId);
    const preview = lastMessage
      ? formatMessagePreview(lastMessage)
      : "No messages yet";
    const timeSource = lastMessage?.timestamp || conversation.createdDate;

    return {
      id: conversation.conversationId,
      conversationId: conversation.conversationId,
      patientId,
      name: patientNameById.get(patientId) || patientId || "Unknown",
      avatarColor: avatarColorForId(conversation.conversationId),
      preview,
      time: formatChatListTime(timeSource),
      unread: isUnreadForStaff(lastMessage, staffId),
      lastMessageAt: timestampToDate(timeSource)?.getTime() || 0,
    };
  });

  threads.sort((a, b) => b.lastMessageAt - a.lastMessageAt);
  return threads;
}

function filterConversationsForStaff(staffId, docs) {
  const trimmedStaffId = String(staffId || "").trim();
  return docs
    .map(mapConversationDoc)
    .filter(
      (conversation) =>
        isActiveConversationStatus(conversation.status) &&
        CONVERSATION_ID_PATTERN.test(conversation.conversationId) &&
        (conversation.participant1Id === trimmedStaffId ||
          conversation.participant2Id === trimmedStaffId),
    );
}

function latestMessageFromSnap(snap) {
  const messages = snap.docs
    .map(mapMessageDoc)
    .filter((message) => MESSAGE_ID_PATTERN.test(message.messageId))
    .sort(
      (a, b) =>
        (timestampToDate(b.timestamp)?.getTime() || 0) -
        (timestampToDate(a.timestamp)?.getTime() || 0),
    );
  return messages.length > 0 ? messages[0] : null;
}

export async function fetchAvailableConversationsForStaff(staffId) {
  const patients = await fetchUsersForConversation();
  const conversations = await fetchAllActiveConversationsForStaff(staffId);
  const activePatientIds = new Set(
    patients.filter(isPatientAccountActive).map((p) => p.patientId),
  );
  const available = conversations.filter((conversation) => {
    const otherId = getOtherParticipantId(conversation, staffId);
    if (!otherId.startsWith("U")) return true;
    return activePatientIds.has(otherId);
  });
  const latestByConversation = await fetchLatestMessageByConversationIds(
    available.map((c) => c.conversationId),
  );
  return buildStaffConversationThreads(
    staffId,
    patients,
    conversations,
    latestByConversation,
  );
}

/** Real-time conversation list with previews (no polling). */
export function subscribeAvailableConversationsForStaff(staffId, onData, onError) {
  const trimmedStaffId = String(staffId || "").trim();
  let patients = [];
  let conversations = [];
  const latestByConversation = new Map();
  const messageUnsubs = new Map();

  function clearMessageListeners() {
    for (const unsub of messageUnsubs.values()) {
      unsub();
    }
    messageUnsubs.clear();
  }

  function syncMessageListeners(conversationIds) {
    const ids = new Set(conversationIds);
    for (const [id, unsub] of messageUnsubs) {
      if (!ids.has(id)) {
        unsub();
        messageUnsubs.delete(id);
        latestByConversation.delete(id);
      }
    }
    for (const id of ids) {
      if (messageUnsubs.has(id)) continue;
      const q = query(
        collection(db, MESSAGES_COLLECTION),
        where("conversationId", "==", id),
      );
      const unsub = onSnapshot(
        q,
        (snap) => {
          const latest = latestMessageFromSnap(snap);
          if (latest) latestByConversation.set(id, latest);
          else latestByConversation.delete(id);
          emit();
        },
        onError,
      );
      messageUnsubs.set(id, unsub);
    }
  }

  function emit() {
    const available = conversations.filter((conversation) => {
      const otherId = getOtherParticipantId(conversation, trimmedStaffId);
      if (!otherId.startsWith("U")) return true;
      const activePatientIds = new Set(
        patients.filter(isPatientAccountActive).map((p) => p.patientId),
      );
      return activePatientIds.has(otherId);
    });
    syncMessageListeners(available.map((c) => c.conversationId));
    onData(
      buildStaffConversationThreads(
        trimmedStaffId,
        patients,
        conversations,
        latestByConversation,
      ),
    );
  }

  const conversationsQuery = query(
    collection(db, CONVERSATIONS_COLLECTION),
    where("status", "==", "Active"),
  );

  const unsubs = [
    onSnapshot(
      collection(db, USERS_COLLECTION),
      (snap) => {
        patients = snap.docs.map((docSnap) => {
          const mapped = mapUserDoc(docSnap);
          return {
            id: mapped.id,
            patientId: String(mapped.patientId || "").trim(),
            name: String(mapped.name || "").trim() || "—",
            accountStatus:
              String(mapped.accountStatus || "Active").trim() || "Active",
          };
        });
        emit();
      },
      onError,
    ),
    onSnapshot(
      conversationsQuery,
      (snap) => {
        conversations = filterConversationsForStaff(trimmedStaffId, snap.docs);
        emit();
      },
      onError,
    ),
  ];

  const stopAll = () => {
    clearMessageListeners();
    for (const unsub of unsubs) {
      if (typeof unsub === "function") unsub();
    }
  };
  trackFirestoreListener(stopAll);
  return stopAll;
}

export async function fetchAvailablePatientsForNewConversation(staffId) {
  const trimmedStaffId = String(staffId || "").trim();
  if (!PARTICIPANT_ID_PATTERN.test(trimmedStaffId)) {
    throw new Error("Your staff profile is missing a valid Staff ID (e.g. S00001).");
  }

  const patients = await fetchUsersForConversation();
  const activePatients = patients.filter(
    (patient) =>
      isPatientAccountActive(patient) && patient.patientId && patient.patientId !== "—",
  );

  let linkedPatientIds = new Set();
  try {
    const existingConversations = await fetchAllActiveConversationsForStaff(
      trimmedStaffId,
    );
    linkedPatientIds = new Set(
      existingConversations
        .map((conversation) => getOtherParticipantId(conversation, trimmedStaffId))
        .filter((id) => id.startsWith("U")),
    );
  } catch (error) {
    if (!isPermissionDenied(error)) {
      throw error;
    }
    linkedPatientIds = new Set();
  }

  return activePatients
    .map((patient) => ({
      patientId: patient.patientId,
      name: patient.name || patient.patientId,
      hasConversation: linkedPatientIds.has(patient.patientId),
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

function formatMessagePreview(message) {
  const type = message.messageType.toLowerCase();
  if (type === "voice") return "Voice message";
  if (type === "call") {
    const duration = message.callDuration;
    return duration ? `Call · ${duration} min` : "Call";
  }
  return message.content || "—";
}

function isUnreadForStaff(message, staffId) {
  if (!message) return false;
  return (
    message.receiverId === staffId &&
    message.deliveryStatus.toLowerCase() !== "read"
  );
}

function textMessagesFromSnap(snap) {
  return snap.docs
    .map(mapMessageDoc)
    .filter((message) => message.messageType.toLowerCase() === "text")
    .sort(
      (a, b) =>
        (timestampToDate(a.timestamp)?.getTime() || 0) -
        (timestampToDate(b.timestamp)?.getTime() || 0),
    );
}

export async function fetchMessagesForConversation(conversationId, staffId) {
  if (!CONVERSATION_ID_PATTERN.test(conversationId)) {
    throw new Error("Invalid conversation ID.");
  }

  const q = query(
    collection(db, MESSAGES_COLLECTION),
    where("conversationId", "==", conversationId),
  );
  const snap = await getDocs(q);
  return buildMessageRenderList(textMessagesFromSnap(snap), staffId);
}

/** Real-time messages for the open conversation. */
export function subscribeMessagesForConversation(
  conversationId,
  staffId,
  onData,
  onError,
) {
  if (!CONVERSATION_ID_PATTERN.test(conversationId)) {
    onError?.(new Error("Invalid conversation ID."));
    return () => {};
  }

  const q = query(
    collection(db, MESSAGES_COLLECTION),
    where("conversationId", "==", conversationId),
  );

  const unsub = onSnapshot(
    q,
    (snap) => {
      onData(buildMessageRenderList(textMessagesFromSnap(snap), staffId));
    },
    onError,
  );
  trackFirestoreListener(unsub);
  return unsub;
}

export function buildMessageRenderList(messages, staffId) {
  const items = [];
  let lastDivider = null;

  messages.forEach((message) => {
    const divider = formatDividerLabel(message.timestamp);
    if (divider !== lastDivider) {
      items.push({ type: "divider", label: divider });
      lastDivider = divider;
    }

    const isStaffSender = message.senderId === staffId;
    items.push({
      type: isStaffSender ? "out" : "in",
      text: message.content || "—",
      time: formatMessageClock(message.timestamp),
    });
  });

  return items;
}

async function reserveMessageId() {
  const counterRef = doc(db, ...MESSAGE_COUNTER_PATH);
  return runTransaction(db, async (transaction) => {
    const counterSnap = await transaction.get(counterRef);
    const next = counterSnap.exists() ? Number(counterSnap.data().next) || 1 : 1;
    const messageId = `G${String(next).padStart(5, "0")}`;
    transaction.set(counterRef, { next: next + 1 }, { merge: true });
    return messageId;
  });
}

export async function sendTextMessage({
  conversationId,
  staffId,
  patientId,
  content,
}) {
  const trimmedContent = String(content || "").trim();
  if (!trimmedContent) {
    throw new Error("Message cannot be empty.");
  }
  if (trimmedContent.length > 255) {
    throw new Error("Message must be 255 characters or less.");
  }
  if (!CONVERSATION_ID_PATTERN.test(conversationId)) {
    throw new Error("Invalid conversation ID.");
  }
  if (!PARTICIPANT_ID_PATTERN.test(staffId)) {
    throw new Error("Staff ID is missing or invalid.");
  }
  if (!/^U\d{5}$/.test(patientId)) {
    throw new Error("Patient ID is missing or invalid.");
  }

  const conversationSnap = await getDoc(
    doc(db, CONVERSATIONS_COLLECTION, conversationId),
  );
  if (!conversationSnap.exists()) {
    throw new Error("Conversation not found.");
  }
  const conversation = mapConversationDoc(conversationSnap);
  if (!isActiveConversationStatus(conversation.status)) {
    throw new Error("This conversation is no longer available.");
  }

  const messageId = await reserveMessageId();
  const now = serverTimestamp();

  // Table 4.9 Message entity — document id = messageId (G00001).
  await setDoc(doc(db, MESSAGES_COLLECTION, messageId), {
    messageId,
    conversationId,
    messageType: "Text",
    content: trimmedContent,
    callDuration: null,
    timestamp: now,
    deliveryStatus: "Sent",
    senderId: staffId,
    receiverId: patientId,
  });

  return {
    messageId,
    preview: trimmedContent,
    time: formatChatListTime(new Date()),
    messages: [{ type: "out", text: trimmedContent, time: formatMessageClock(new Date()) }],
  };
}

export async function createConversationForStaffPatient({ staffId, patientId }) {
  const trimmedStaffId = String(staffId || "").trim();
  const trimmedPatientId = String(patientId || "").trim();

  if (!/^S\d{5}$/.test(trimmedStaffId)) {
    throw new Error("Staff ID is missing or invalid.");
  }
  if (!/^U\d{5}$/.test(trimmedPatientId)) {
    throw new Error("Please select a valid patient.");
  }

  const patients = await fetchUsersForConversation();
  const selectedPatient = patients.find((p) => p.patientId === trimmedPatientId);
  if (!selectedPatient || !isPatientAccountActive(selectedPatient)) {
    throw new Error("Selected patient is not available for messaging.");
  }

  const existingConversations = await fetchAllActiveConversationsForStaff(
    trimmedStaffId,
  );
  const existing = existingConversations.find(
    (conversation) =>
      getOtherParticipantId(conversation, trimmedStaffId) === trimmedPatientId,
  );
  if (existing) {
    return {
      id: existing.conversationId,
      conversationId: existing.conversationId,
      patientId: trimmedPatientId,
      name: selectedPatient.name || trimmedPatientId,
      avatarColor: avatarColorForId(existing.conversationId),
      preview: "No messages yet",
      time: formatChatListTime(existing.createdDate),
      unread: false,
      lastMessageAt: timestampToDate(existing.createdDate)?.getTime() || Date.now(),
    };
  }

  const conversationId = await reserveConversationId();
  const now = new Date();

  await setDoc(doc(db, CONVERSATIONS_COLLECTION, conversationId), {
    conversationId,
    createdDate: formatCreatedDateString(now),
    createdAt: serverTimestamp(),
    status: "Active",
    participant1Id: trimmedStaffId,
    participant2Id: trimmedPatientId,
  });

  return {
    id: conversationId,
    conversationId,
    patientId: trimmedPatientId,
    name: selectedPatient.name || trimmedPatientId,
    avatarColor: avatarColorForId(conversationId),
    preview: "No messages yet",
    time: formatChatListTime(now),
    unread: false,
    lastMessageAt: now.getTime(),
  };
}
