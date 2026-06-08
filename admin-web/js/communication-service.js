import {
  arrayUnion,
  collection,
  doc,
  getDoc,
  getDocs,
  onSnapshot,
  query,
  runTransaction,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import {
  getDownloadURL,
  ref,
  uploadBytes,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-storage.js";
import { db, storage } from "./firebase.js";
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

export const MESSAGE_MEDIA_MAX_BYTES = 10 * 1024 * 1024;
export const MESSAGE_MEDIA_MAX_SIZE_MESSAGE =
  "Attachments must be 10 MB or smaller.";
/** Keeps base64 photo payloads within Firestore document size limits. */
export const INLINE_PHOTO_MAX_BYTES = 500 * 1024;

const PHOTO_MIME_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "image/gif",
]);
const VIDEO_MIME_TYPES = new Set([
  "video/mp4",
  "video/webm",
  "video/quicktime",
]);
const DOCUMENT_MIME_TYPES = new Set([
  "application/pdf",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "text/plain",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "application/vnd.ms-powerpoint",
  "application/vnd.openxmlformats-officedocument.presentationml.presentation",
]);
const DOCUMENT_EXTENSIONS = new Set([
  "pdf",
  "doc",
  "docx",
  "txt",
  "xls",
  "xlsx",
  "ppt",
  "pptx",
]);

const DISPLAYABLE_MESSAGE_TYPES = new Set([
  "text",
  "photo",
  "video",
  "document",
]);

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
  const hiddenFor = Array.isArray(data.hiddenFor)
    ? data.hiddenFor.map((id) => String(id || "").trim()).filter(Boolean)
    : [];
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
    deliveredAt: data.deliveredAt ?? null,
    readAt: data.readAt ?? null,
    senderId: pickParticipantId(data, ["senderId", "senderID", "SenderID"]),
    receiverId: pickParticipantId(data, ["receiverId", "receiverID", "ReceiverID"]),
    hiddenFor,
    deletedForEveryone: Boolean(data.deletedForEveryone),
    deletedAt: data.deletedAt ?? null,
    deletedBy: pickParticipantId(data, ["deletedBy", "deletedBY"]) || "",
    replyToMessageId: String(data.replyToMessageId || "").trim(),
    replyPreview: String(data.replyPreview || "").trim(),
    forwardedFromMessageId: String(data.forwardedFromMessageId || "").trim(),
    forwardedFromConversationId: String(data.forwardedFromConversationId || "").trim(),
    filePath: String(data.filePath || "").trim(),
  };
}

export function isMessageHiddenForUser(message, userId) {
  const viewerId = String(userId || "").trim();
  if (!viewerId) return false;
  return (message.hiddenFor || []).includes(viewerId);
}

export function formatMessageDateTimeFull(value) {
  const date = timestampToDate(value);
  if (!date) return "Not available";
  return date.toLocaleString("en-US", {
    weekday: "short",
    year: "numeric",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    second: "2-digit",
    hour12: true,
  });
}

export function buildMessageCopyText(message) {
  if (!message || message.deletedForEveryone) return "";
  const kind = resolveMessageKind(message);
  if (kind === "text") return String(message.content || "").trim();
  const media = parseMediaMessageContent(message.content);
  if (!media) {
    if (kind === "photo") return "Photo";
    if (kind === "video") return "Video";
    return media?.fileName || "Document";
  }
  if (kind === "document") return media.fileName || "Document";
  return media.url || media.fileName || "Attachment";
}

export function buildReplyPreview(message) {
  if (!message) return "";
  if (message.deletedForEveryone) return "Deleted message";
  const parsed = parseMessageForRender(message);
  if (parsed.kind === "text") {
    const text = String(parsed.text || "").trim();
    return text.length > 80 ? `${text.slice(0, 80)}…` : text || "Message";
  }
  if (parsed.kind === "photo") return "Photo";
  if (parsed.kind === "video") return "Video";
  return parsed.fileName || "Document";
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
    patientId: String(data.userId || data.userID || "").trim(),
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

function fileExtension(fileName) {
  const parts = String(fileName || "").split(".");
  return parts.length > 1 ? parts.pop().toLowerCase() : "";
}

function sanitizeStorageFileName(fileName) {
  const trimmed = String(fileName || "file").trim() || "file";
  return trimmed.replace(/[^a-zA-Z0-9._-]/g, "_").slice(0, 80);
}

function buildChatMediaStoragePath(conversationId, messageId, fileName) {
  return `chatmedia/${conversationId}/${messageId}/${sanitizeStorageFileName(fileName)}`;
}

function encodeMediaContent({ url, fileName, mimeType }) {
  return JSON.stringify({
    url,
    fileName: String(fileName || "Attachment").trim() || "Attachment",
    mimeType: String(mimeType || "").trim(),
  });
}

function encodeInlineMediaContent({ fileData, fileName, mimeType }) {
  return JSON.stringify({
    fileData: String(fileData || "").trim(),
    fileName: String(fileName || "Attachment").trim() || "Attachment",
    mimeType: String(mimeType || "").trim(),
  });
}

const INLINE_PHOTO_MAX_DIMENSION = 1280;

function loadImageElement(file) {
  const url = URL.createObjectURL(file);
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => {
      URL.revokeObjectURL(url);
      resolve(image);
    };
    image.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error("Could not read photo data."));
    };
    image.src = url;
  });
}

/** Shrinks camera/gallery photos so they can be stored inline in Firestore. */
async function compressPhotoForInlineStorage(file) {
  if (!(file instanceof Blob) || file.size <= INLINE_PHOTO_MAX_BYTES) {
    return file;
  }

  let image;
  try {
    image = await loadImageElement(file);
  } catch {
    return file;
  }

  let width = image.naturalWidth || image.width;
  let height = image.naturalHeight || image.height;
  if (!width || !height) return file;

  const scale = Math.min(1, INLINE_PHOTO_MAX_DIMENSION / Math.max(width, height));
  width = Math.max(1, Math.round(width * scale));
  height = Math.max(1, Math.round(height * scale));

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) return file;
  context.drawImage(image, 0, 0, width, height);

  const baseName =
    String(file.name || "photo.jpg").replace(/\.[^.]+$/, "") || "photo";
  let smallestBlob = null;

  for (const quality of [0.85, 0.75, 0.65, 0.55, 0.45, 0.35]) {
    const blob = await new Promise((resolve) => {
      canvas.toBlob(resolve, "image/jpeg", quality);
    });
    if (!blob) continue;
    smallestBlob = blob;
    if (blob.size <= INLINE_PHOTO_MAX_BYTES) {
      return new File([blob], `${baseName}.jpg`, { type: "image/jpeg" });
    }
  }

  if (smallestBlob) {
    return new File([smallestBlob], `${baseName}.jpg`, { type: "image/jpeg" });
  }
  return file;
}

function readFileAsDataUrl(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result || ""));
    reader.onerror = () => reject(new Error("Could not read photo data."));
    reader.readAsDataURL(file);
  });
}

export function parseMediaMessageContent(content) {
  const raw = String(content || "").trim();
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed.fileData === "string" && parsed.fileData.trim()) {
      return {
        url: parsed.fileData.trim(),
        fileName: String(parsed.fileName || "Attachment").trim() || "Attachment",
        mimeType: String(parsed.mimeType || "").trim(),
      };
    }
    if (parsed && typeof parsed.url === "string" && parsed.url.trim()) {
      return {
        url: parsed.url.trim(),
        fileName: String(parsed.fileName || "Attachment").trim() || "Attachment",
        mimeType: String(parsed.mimeType || "").trim(),
      };
    }
  } catch {
    /* plain URL fallback */
  }
  if (/^https?:\/\//i.test(raw) || raw.startsWith("data:")) {
    return { url: raw, fileName: "Attachment", mimeType: "" };
  }
  return null;
}

function resolveMessageKind(message) {
  const type = String(message.messageType || "Text").trim().toLowerCase();
  if (type === "photo" || type === "video" || type === "document") return type;
  return "text";
}

function parseMessageForRender(message) {
  const kind = resolveMessageKind(message);
  if (kind === "text") {
    return {
      kind: "text",
      text: String(message.content || "").trim() || "—",
    };
  }
  const media = parseMediaMessageContent(message.content);
  if (!media) {
    return {
      kind: "text",
      text: kind === "photo" ? "Photo" : kind === "video" ? "Video" : "Document",
    };
  }
  return {
    kind,
    url: media.url,
    fileName: media.fileName,
    mimeType: media.mimeType,
  };
}

export function inferMessageTypeForFile(file, intent = "media") {
  const mime = String(file?.type || "").trim().toLowerCase();
  const ext = fileExtension(file?.name);

  if (intent === "document") {
    if (DOCUMENT_MIME_TYPES.has(mime) || DOCUMENT_EXTENSIONS.has(ext)) {
      return "Document";
    }
    return null;
  }

  if (intent === "camera") {
    if (mime.startsWith("image/") || PHOTO_MIME_TYPES.has(mime)) return "Photo";
    return null;
  }

  if (mime.startsWith("image/") || PHOTO_MIME_TYPES.has(mime)) return "Photo";
  if (mime.startsWith("video/") || VIDEO_MIME_TYPES.has(mime)) return "Video";
  return null;
}

export function validateMediaMessageFile(file, messageType) {
  if (!file) return "Please choose a file to send.";
  if (file.size > MESSAGE_MEDIA_MAX_BYTES) return MESSAGE_MEDIA_MAX_SIZE_MESSAGE;

  const type = String(messageType || "").trim();
  const mime = String(file.type || "").trim().toLowerCase();
  const ext = fileExtension(file.name);

  if (type === "Photo") {
    if (mime.startsWith("image/") || PHOTO_MIME_TYPES.has(mime)) return null;
    return "Please choose a photo file (JPEG, PNG, WebP, or GIF).";
  }
  if (type === "Video") {
    if (mime.startsWith("video/") || VIDEO_MIME_TYPES.has(mime)) return null;
    return "Please choose a video file (MP4, WebM, or MOV).";
  }
  if (type === "Document") {
    if (DOCUMENT_MIME_TYPES.has(mime) || DOCUMENT_EXTENSIONS.has(ext)) return null;
    return "Please choose a document (PDF, Word, Excel, PowerPoint, or TXT).";
  }
  return "Unsupported attachment type.";
}

function formatMessagePreview(message) {
  const type = message.messageType.toLowerCase();
  if (type === "voice") return "Voice message";
  if (type === "call") {
    const duration = message.callDuration;
    return duration ? `Call · ${duration} min` : "Call";
  }
  if (type === "photo") return "Photo";
  if (type === "video") return "Video";
  if (type === "document") {
    const media = parseMediaMessageContent(message.content);
    return media?.fileName || "Document";
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

function conversationMessagesFromSnap(snap, staffId = "") {
  return snap.docs
    .map(mapMessageDoc)
    .filter((message) =>
      DISPLAYABLE_MESSAGE_TYPES.has(
        String(message.messageType || "Text").trim().toLowerCase(),
      ),
    )
    .filter((message) => !isMessageHiddenForUser(message, staffId))
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
  return buildMessageRenderList(conversationMessagesFromSnap(snap, staffId), staffId);
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
      onData(
        buildMessageRenderList(conversationMessagesFromSnap(snap, staffId), staffId),
      );
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
    const isDeleted = Boolean(message.deletedForEveryone);
    const parsed = isDeleted
      ? { kind: "deleted", text: "This message was deleted" }
      : parseMessageForRender(message);
    const base = {
      type: isStaffSender ? "out" : "in",
      time: formatMessageClock(message.timestamp),
      kind: parsed.kind,
      messageId: message.messageId,
      sentAt: formatMessageDateTimeFull(message.timestamp),
      deliveredAt: message.deliveredAt
        ? formatMessageDateTimeFull(message.deliveredAt)
        : "",
      readAt: message.readAt ? formatMessageDateTimeFull(message.readAt) : "",
      deliveryStatus: message.deliveryStatus || "Sent",
      copyText: buildMessageCopyText(message),
      replyPreview: message.replyPreview || "",
      forwardedFromMessageId: message.forwardedFromMessageId || "",
      isDeleted,
    };
    if (parsed.kind === "text" || parsed.kind === "deleted") {
      items.push({ ...base, text: parsed.text });
    } else {
      items.push({
        ...base,
        url: parsed.url,
        fileName: parsed.fileName,
        mimeType: parsed.mimeType,
      });
    }
  });

  return items;
}

export function buildOptimisticOutgoingItem({
  messageType,
  content,
  staffId,
  timestamp = new Date(),
  messageId = "",
  replyPreview = "",
}) {
  const parsed = parseMessageForRender({
    messageType,
    content,
    senderId: staffId,
    timestamp,
  });
  const base = {
    type: "out",
    time: formatMessageClock(timestamp),
    kind: parsed.kind,
    messageId: messageId || `temp-${Date.now()}`,
    sentAt: formatMessageDateTimeFull(timestamp),
    deliveredAt: "",
    readAt: "",
    deliveryStatus: "Sent",
    copyText: buildMessageCopyText({ messageType, content, deletedForEveryone: false }),
    replyPreview: String(replyPreview || "").trim(),
    forwardedFromMessageId: "",
    isDeleted: false,
  };
  if (parsed.kind === "text") {
    return { ...base, text: parsed.text };
  }
  return {
    ...base,
    url: parsed.url,
    fileName: parsed.fileName,
    mimeType: parsed.mimeType,
  };
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

async function appendReplyFields(payload, { replyToMessageId, replyPreview } = {}) {
  const replyId = String(replyToMessageId || "").trim();
  const preview = String(replyPreview || "").trim();
  if (replyId && MESSAGE_ID_PATTERN.test(replyId)) {
    payload.replyToMessageId = replyId;
    if (preview) payload.replyPreview = preview.slice(0, 120);
  }
}

export async function sendTextMessage({
  conversationId,
  staffId,
  patientId,
  content,
  replyToMessageId = "",
  replyPreview = "",
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

  const messagePayload = {
    messageId,
    conversationId,
    messageType: "Text",
    content: trimmedContent,
    callDuration: null,
    timestamp: now,
    deliveryStatus: "Sent",
    senderId: staffId,
    receiverId: patientId,
    hiddenFor: [],
    deletedForEveryone: false,
  };
  await appendReplyFields(messagePayload, { replyToMessageId, replyPreview });

  await setDoc(doc(db, MESSAGES_COLLECTION, messageId), messagePayload);

  return {
    messageId,
    preview: trimmedContent,
    time: formatChatListTime(new Date()),
    messageType: "Text",
    content: trimmedContent,
    replyPreview: messagePayload.replyPreview || "",
  };
}

async function assertConversationReady(conversationId) {
  if (!CONVERSATION_ID_PATTERN.test(conversationId)) {
    throw new Error("Invalid conversation ID.");
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
  return conversation;
}

export async function sendMediaMessage({
  conversationId,
  staffId,
  patientId,
  file,
  messageType,
  replyToMessageId = "",
  replyPreview = "",
}) {
  const trimmedType = String(messageType || "").trim();
  if (!["Photo", "Video", "Document"].includes(trimmedType)) {
    throw new Error("Unsupported attachment type.");
  }
  if (!PARTICIPANT_ID_PATTERN.test(staffId)) {
    throw new Error("Staff ID is missing or invalid.");
  }
  if (!/^U\d{5}$/.test(patientId)) {
    throw new Error("Patient ID is missing or invalid.");
  }

  const validationError = validateMediaMessageFile(file, trimmedType);
  if (validationError) {
    throw new Error(validationError);
  }

  await assertConversationReady(conversationId);

  const messageId = await reserveMessageId();
  const now = serverTimestamp();
  let content = "";
  let filePath = "";

  let uploadFile = file;
  if (trimmedType === "Photo") {
    uploadFile = await compressPhotoForInlineStorage(file);
  }

  const canStorePhotoInline =
    trimmedType === "Photo" && uploadFile.size <= INLINE_PHOTO_MAX_BYTES;

  if (canStorePhotoInline) {
    const fileData = await readFileAsDataUrl(uploadFile);
    if (!fileData.startsWith("data:")) {
      throw new Error("Could not prepare photo for sending.");
    }
    content = encodeInlineMediaContent({
      fileData,
      fileName: uploadFile.name,
      mimeType: uploadFile.type || "image/jpeg",
    });
  } else {
    filePath = buildChatMediaStoragePath(
      conversationId,
      messageId,
      uploadFile.name,
    );
    const storageRef = ref(storage, filePath);

    try {
      await uploadBytes(storageRef, uploadFile, {
        contentType: uploadFile.type || "application/octet-stream",
      });
    } catch (error) {
      const code = error?.code || "";
      if (code === "storage/unauthorized" || code === "storage/unauthenticated") {
        throw new Error(
          "Upload blocked. Enable Firebase Storage and deploy storage.rules.",
        );
      }
      throw error;
    }

    let downloadUrl = "";
    try {
      downloadUrl = await getDownloadURL(storageRef);
    } catch (error) {
      throw new Error(error?.message || "Could not get a download link for the file.");
    }

    content = encodeMediaContent({
      url: downloadUrl,
      fileName: uploadFile.name,
      mimeType: uploadFile.type || "",
    });
  }

  const messagePayload = {
    messageId,
    conversationId,
    messageType: trimmedType,
    content,
    callDuration: null,
    timestamp: now,
    deliveryStatus: "Sent",
    senderId: staffId,
    receiverId: patientId,
    hiddenFor: [],
    deletedForEveryone: false,
  };
  if (filePath) {
    messagePayload.filePath = filePath;
  }
  await appendReplyFields(messagePayload, { replyToMessageId, replyPreview });

  await setDoc(doc(db, MESSAGES_COLLECTION, messageId), messagePayload);

  const preview = formatMessagePreview({
    messageType: trimmedType,
    content,
  });

  return {
    messageId,
    preview,
    time: formatChatListTime(new Date()),
    messageType: trimmedType,
    content,
  };
}

export async function fetchMessageById(messageId) {
  const trimmedId = String(messageId || "").trim();
  if (!MESSAGE_ID_PATTERN.test(trimmedId)) {
    throw new Error("Invalid message ID.");
  }
  const snap = await getDoc(doc(db, MESSAGES_COLLECTION, trimmedId));
  if (!snap.exists()) {
    throw new Error("Message not found.");
  }
  return mapMessageDoc(snap);
}

export async function fetchForwardTargets(staffId) {
  const trimmedStaffId = String(staffId || "").trim();
  if (!PARTICIPANT_ID_PATTERN.test(trimmedStaffId)) {
    throw new Error("Staff ID is missing or invalid.");
  }
  const patients = await fetchUsersForConversation();
  return patients
    .filter(
      (patient) =>
        isPatientAccountActive(patient) && patient.patientId && patient.patientId !== "—",
    )
    .map((patient) => ({
      patientId: patient.patientId,
      name: patient.name || patient.patientId,
    }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

export async function hideMessageForUser(messageId, userId) {
  const trimmedId = String(messageId || "").trim();
  const viewerId = String(userId || "").trim();
  if (!MESSAGE_ID_PATTERN.test(trimmedId)) {
    throw new Error("Invalid message ID.");
  }
  if (!PARTICIPANT_ID_PATTERN.test(viewerId)) {
    throw new Error("User ID is missing or invalid.");
  }
  await updateDoc(doc(db, MESSAGES_COLLECTION, trimmedId), {
    hiddenFor: arrayUnion(viewerId),
  });
}

export async function deleteMessageForEveryone(messageId, staffId) {
  const trimmedId = String(messageId || "").trim();
  const actorId = String(staffId || "").trim();
  if (!MESSAGE_ID_PATTERN.test(trimmedId)) {
    throw new Error("Invalid message ID.");
  }
  if (!PARTICIPANT_ID_PATTERN.test(actorId)) {
    throw new Error("Staff ID is missing or invalid.");
  }
  await updateDoc(doc(db, MESSAGES_COLLECTION, trimmedId), {
    deletedForEveryone: true,
    deletedAt: serverTimestamp(),
    deletedBy: actorId,
  });
}

async function persistForwardedMessage({
  staffId,
  targetPatientId,
  sourceMessage,
}) {
  const thread = await createConversationForStaffPatient({
    staffId,
    patientId: targetPatientId,
  });
  const messageId = await reserveMessageId();
  const now = serverTimestamp();
  const payload = {
    messageId,
    conversationId: thread.conversationId,
    messageType: sourceMessage.messageType,
    content: sourceMessage.content,
    callDuration: sourceMessage.callDuration ?? null,
    timestamp: now,
    deliveryStatus: "Sent",
    senderId: staffId,
    receiverId: targetPatientId,
    hiddenFor: [],
    deletedForEveryone: false,
    forwardedFromMessageId: sourceMessage.messageId,
    forwardedFromConversationId: sourceMessage.conversationId,
  };
  if (sourceMessage.filePath) {
    payload.filePath = sourceMessage.filePath;
  }
  await setDoc(doc(db, MESSAGES_COLLECTION, messageId), payload);
  return {
    messageId,
    conversationId: thread.conversationId,
    patientName: thread.name,
  };
}

export async function forwardMessageToPatients({
  messageId,
  staffId,
  patientIds,
}) {
  const trimmedId = String(messageId || "").trim();
  const actorId = String(staffId || "").trim();
  const targets = [...new Set((patientIds || []).map((id) => String(id || "").trim()))].filter(
    (id) => /^U\d{5}$/.test(id),
  );
  if (!MESSAGE_ID_PATTERN.test(trimmedId)) {
    throw new Error("Invalid message ID.");
  }
  if (!PARTICIPANT_ID_PATTERN.test(actorId)) {
    throw new Error("Staff ID is missing or invalid.");
  }
  if (targets.length === 0) {
    throw new Error("Select at least one patient to forward to.");
  }

  const sourceMessage = await fetchMessageById(trimmedId);
  if (sourceMessage.deletedForEveryone) {
    throw new Error("Deleted messages cannot be forwarded.");
  }

  const results = [];
  for (const targetPatientId of targets) {
    results.push(
      await persistForwardedMessage({
        staffId: actorId,
        targetPatientId,
        sourceMessage,
      }),
    );
  }
  return results;
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
