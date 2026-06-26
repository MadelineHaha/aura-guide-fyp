import { initStaffAuth, getInitials } from "./staff-shell.js";
import { getStaffSession } from "./staff-auth.js";
import { isAdmin } from "./staff-rbac.js";
import {
  buildMessageCopyText,
  buildOptimisticOutgoingItem,
  buildReplyPreview,
  createConversationForStaffPatient,
  deleteMessageForEveryone,
  fetchAvailablePatientsForNewConversation,
  fetchForwardTargets,
  fetchMessageById,
  forwardMessageToPatients,
  hideMessageForUser,
  inferMessageTypeForFile,
  subscribeAvailableConversationsForStaff,
  subscribeMessagesForConversation,
  sendMediaMessage,
  sendTextMessage,
  sendCallMessage,
} from "./communication-service.js";
import { VoiceCallController, subscribeStaffIncomingCalls } from "./voice-call-service.js";
import { CallRingtone } from "./call-ringtone.js";
import { releaseFirestoreListener } from "./firestore-realtime.js";

let chatThreads = [];
let activeThreadId = null;
let chatFilter = "all";
let searchQuery = "";
let conversationSearchQuery = "";
let conversationSearchOpen = false;
let calendarViewYear = new Date().getFullYear();
let calendarViewMonth = new Date().getMonth();
let loggedInStaffId = "";
let isLoadingThreads = false;
let isLoadingMessages = false;
let unsubscribeConversations = null;
let unsubscribeMessages = null;
const OPEN_COMMUNICATION_PATIENT_KEY = "auraOpenCommunicationPatientId";
const pendingOpenPatientId = (() => {
  const fromUrl = new URLSearchParams(window.location.search).get("patient")?.trim() || "";
  if (fromUrl) return fromUrl;
  try {
    return sessionStorage.getItem(OPEN_COMMUNICATION_PATIENT_KEY)?.trim() || "";
  } catch {
    return "";
  }
})();
let pendingOpenResolved = !pendingOpenPatientId;
let pendingOpenInProgress = false;
let forcedActiveThreadId = null;

const threadListEl = document.getElementById("chat-thread-list");
const messagesEl = document.getElementById("chat-messages");
const scrollBottomBtnEl = document.getElementById("btn-chat-scroll-bottom");
const panelHeaderEl = document.querySelector(".communication-panel-header");
const activeNameEl = document.getElementById("active-chat-name");
const activeAvatarEl = document.getElementById("active-chat-avatar");
const searchEl = document.getElementById("chat-search");
const conversationSearchEl = document.getElementById("chat-conversation-search");
const conversationSearchInputEl = document.getElementById("chat-conversation-search-input");
const conversationSearchCloseBtn = document.getElementById("chat-conversation-search-close");
const conversationSearchBtnEl = document.getElementById("btn-chat-search");
const calendarModalEl = document.getElementById("chat-calendar-modal");
const calendarCloseBtn = document.getElementById("chat-calendar-close");
const calendarPrevBtn = document.getElementById("chat-calendar-prev");
const calendarNextBtn = document.getElementById("chat-calendar-next");
const calendarMonthLabelEl = document.getElementById("chat-calendar-month-label");
const calendarGridEl = document.getElementById("chat-calendar-grid");
const calendarBtnEl = document.getElementById("btn-chat-calendar");
const callModalEl = document.getElementById("chat-call-modal");
const callCloseBtn = document.getElementById("chat-call-close");
const callCancelBtn = document.getElementById("chat-call-cancel");
const callStartBtn = document.getElementById("chat-call-start");
const callAvatarEl = document.getElementById("chat-call-avatar");
const callNameEl = document.getElementById("chat-call-name");
const callPatientIdEl = document.getElementById("chat-call-patient-id");
const callErrorEl = document.getElementById("chat-call-error");
const voiceCallOverlayEl = document.getElementById("chat-voice-call-overlay");
const voiceCallAvatarEl = document.getElementById("chat-voice-call-avatar");
const voiceCallNameEl = document.getElementById("chat-voice-call-name");
const voiceCallStatusEl = document.getElementById("chat-voice-call-status");
const voiceCallTimerEl = document.getElementById("chat-voice-call-timer");
const voiceCallMuteBtn = document.getElementById("chat-voice-call-mute");
const voiceCallEndBtn = document.getElementById("chat-voice-call-end");
const voiceCallRemoteAudioEl = document.getElementById("chat-voice-call-remote-audio");
const incomingCallModalEl = document.getElementById("chat-incoming-call-modal");
const incomingCallAvatarEl = document.getElementById("chat-incoming-call-avatar");
const incomingCallTitleEl = document.getElementById("chat-incoming-call-title");
const incomingCallHintEl = document.getElementById("chat-incoming-call-hint");
const incomingCallAcceptBtn = document.getElementById("chat-incoming-call-accept");
const incomingCallDeclineBtn = document.getElementById("chat-incoming-call-decline");
const composeFormEl = document.getElementById("chat-compose-form");
const composeInputEl = document.getElementById("chat-compose-input");
const attachBtnEl = document.getElementById("btn-chat-attach");
const attachMenuEl = document.getElementById("chat-attach-menu");
const attachDocumentInputEl = document.getElementById("chat-attach-document");
const attachMediaInputEl = document.getElementById("chat-attach-media");
const cameraModalEl = document.getElementById("chat-camera-modal");
const cameraPreviewEl = document.getElementById("chat-camera-preview");
const cameraStillEl = document.getElementById("chat-camera-still");
const cameraCanvasEl = document.getElementById("chat-camera-canvas");
const cameraHintEl = document.getElementById("chat-camera-hint");
const cameraTitleEl = document.getElementById("chat-camera-title");
const cameraSubtitleEl = document.getElementById("chat-camera-subtitle");
const cameraCloseBtn = document.getElementById("chat-camera-close");
const cameraCancelBtn = document.getElementById("chat-camera-cancel");
const cameraCaptureBtn = document.getElementById("chat-camera-capture");
const cameraFooterCaptureEl = document.getElementById("chat-camera-footer-capture");
const cameraFooterPreviewEl = document.getElementById("chat-camera-footer-preview");
const cameraRetakeBtn = document.getElementById("chat-camera-retake");
const cameraSendBtn = document.getElementById("chat-camera-send");
const photoPreviewModalEl = document.getElementById("chat-photo-preview-modal");
const photoPreviewImageEl = document.getElementById("chat-photo-preview-image");
const photoPreviewCloseBtn = document.getElementById("chat-photo-preview-close");
const filterBtns = document.querySelectorAll(".communication-filter");
const addContactSidebarBtn = document.getElementById("btn-add-contact-sidebar");
const addContactModalEl = document.getElementById("add-contact-modal");
const addContactFormEl = document.getElementById("add-contact-form");
const addContactCloseBtn = document.getElementById("add-contact-close");
const addContactPatientListEl = document.getElementById("add-contact-patient-list");
const addContactErrorEl = document.getElementById("add-contact-error");
const addContactSubmitBtn = document.getElementById("add-contact-submit");
const replyStripEl = document.getElementById("chat-reply-strip");
const replyStripTextEl = document.getElementById("chat-reply-strip-text");
const replyCancelBtn = document.getElementById("chat-reply-cancel");
const selectionToolbarEl = document.getElementById("chat-selection-toolbar");
const selectionCountEl = document.getElementById("chat-selection-count");
const selectionCopyBtn = document.getElementById("btn-selection-copy");
const selectionForwardBtn = document.getElementById("btn-selection-forward");
const selectionDeleteBtn = document.getElementById("btn-selection-delete");
const selectionCancelBtn = document.getElementById("btn-selection-cancel");
const messageInfoModalEl = document.getElementById("message-info-modal");
const messageInfoBodyEl = document.getElementById("message-info-body");
const messageInfoCloseBtn = document.getElementById("message-info-close");
const forwardMessageModalEl = document.getElementById("forward-message-modal");
const forwardMessageListEl = document.getElementById("forward-message-list");
const forwardMessageErrorEl = document.getElementById("forward-message-error");
const forwardMessageCloseBtn = document.getElementById("forward-message-close");
const forwardMessageSubmitBtn = document.getElementById("forward-message-submit");
const deleteMessageModalEl = document.getElementById("delete-message-modal");
const deleteMessageCloseBtn = document.getElementById("delete-message-close");
const deleteMessageForMeBtn = document.getElementById("delete-message-for-me");
const deleteMessageForEveryoneBtn = document.getElementById("delete-message-for-everyone");
let selectedAddContactPatientId = "";
let isCreatingContact = false;
let isSendingAttachment = false;
let cameraStream = null;
let pendingCameraFile = null;
let pendingCameraPreviewUrl = null;
let openMessageMenuId = null;
let selectionMode = false;
let selectedMessageIds = new Set();
let replyTarget = null;
let pendingForwardMessageIds = [];
let pendingDeleteMessageIds = [];
let selectedForwardPatientIds = new Set();
let isMessageActionBusy = false;
let voiceCallController = null;
let voiceCallTimerInterval = null;
let activeVoiceCallThread = null;
let callRingtone = null;
let staffInitiatedCall = false;
let pendingIncomingCall = null;
let unsubscribeIncomingCalls = null;

function syncConversationPanelVisibility(thread) {
  const hasActiveThread = Boolean(thread);
  const inSelection = selectionMode && hasActiveThread;
  const isVirtual = thread && thread.id === "sys_ag_virtual";
  
  panelHeaderEl.hidden = !hasActiveThread;
  composeFormEl.hidden = !hasActiveThread || inSelection || isVirtual;
  selectionToolbarEl.hidden = !inSelection;
  replyStripEl.hidden = !replyTarget || inSelection;
  updateScrollToBottomButton();
  
  // Hide call buttons for virtual broadcast thread
  const callBtn = document.getElementById("btn-chat-call");
  const videoBtn = document.getElementById("btn-chat-video");
  if (callBtn) callBtn.hidden = isVirtual;
  if (videoBtn) videoBtn.hidden = isVirtual;
  
  // Search and calendar icons should always be visible, even for virtual threads
  const searchBtn = document.getElementById("btn-chat-search");
  const calendarBtn = document.getElementById("btn-chat-calendar");
  if (searchBtn) searchBtn.hidden = false;
  if (calendarBtn) calendarBtn.hidden = false;
}

function isNearMessagesBottom(element, threshold = 64) {
  if (!element) return true;
  const distance =
    element.scrollHeight - element.scrollTop - element.clientHeight;
  return distance <= threshold;
}

function conversationHasScrollableMessages() {
  return Boolean(messagesEl.querySelector("[data-message-row]"));
}

function updateScrollToBottomButton() {
  if (!scrollBottomBtnEl) return;
  const shouldShow =
    Boolean(activeThreadId) &&
    !selectionMode &&
    conversationHasScrollableMessages() &&
    !isNearMessagesBottom(messagesEl);
  scrollBottomBtnEl.hidden = !shouldShow;
}

function scrollMessagesToBottom({ smooth = true } = {}) {
  if (!messagesEl) return;
  messagesEl.scrollTo({
    top: messagesEl.scrollHeight,
    behavior: smooth ? "smooth" : "auto",
  });
}

function syncBodyModalLock() {
  const anyOpen =
    !addContactModalEl.hidden ||
    !cameraModalEl.hidden ||
    !photoPreviewModalEl.hidden ||
    !messageInfoModalEl.hidden ||
    !forwardMessageModalEl.hidden ||
    !deleteMessageModalEl.hidden ||
    (calendarModalEl && !calendarModalEl.hidden) ||
    (callModalEl && !callModalEl.hidden) ||
    (incomingCallModalEl && !incomingCallModalEl.hidden);
  document.body.classList.toggle("modal-open", anyOpen);
}

function getMessageItemById(messageId) {
  const thread = getThreadById(activeThreadId);
  if (!thread?.messages) return null;
  return thread.messages.find((item) => item.messageId === messageId) || null;
}

function sortMessageIdsByConversationOrder(messageIds) {
  const idSet = new Set((messageIds || []).filter(Boolean));
  if (idSet.size === 0) return [];

  const thread = getThreadById(activeThreadId);
  if (!thread?.messages?.length) return [...idSet];

  const ordered = [];
  for (const item of thread.messages) {
    if (item.type === "divider" || !item.messageId) continue;
    if (idSet.has(item.messageId)) ordered.push(item.messageId);
  }

  for (const id of idSet) {
    if (!ordered.includes(id)) ordered.push(id);
  }

  return ordered;
}

function closeAllMessageMenus() {
  openMessageMenuId = null;
  messagesEl.querySelectorAll(".chat-bubble-menu").forEach((menu) => {
    menu.hidden = true;
  });
  messagesEl.querySelectorAll(".chat-bubble-menu-btn").forEach((btn) => {
    btn.setAttribute("aria-expanded", "false");
  });
}

function toggleMessageMenu(messageId) {
  const isOpen = openMessageMenuId === messageId;
  closeAllMessageMenus();
  if (isOpen) return;
  const panel = messagesEl.querySelector(`[data-message-menu-panel="${messageId}"]`);
  const btn = messagesEl.querySelector(`[data-message-menu="${messageId}"]`);
  if (!panel || !btn) return;
  panel.hidden = false;
  btn.setAttribute("aria-expanded", "true");
  openMessageMenuId = messageId;
}

function updateSelectionToolbar() {
  const count = selectedMessageIds.size;
  selectionCountEl.textContent =
    count === 1 ? "1 message selected" : `${count} messages selected`;
  selectionCopyBtn.disabled = count === 0;
  selectionForwardBtn.disabled = count === 0;
  selectionDeleteBtn.disabled = count === 0;
}

function enterSelectionMode(messageId) {
  selectionMode = true;
  selectedMessageIds = new Set(messageId ? [messageId] : []);
  closeAllMessageMenus();
  updateSelectionToolbar();
  const thread = getThreadById(activeThreadId);
  syncConversationPanelVisibility(thread);
  renderMessages(thread, { preserveScroll: true });
}

function exitSelectionMode() {
  selectionMode = false;
  selectedMessageIds = new Set();
  const thread = getThreadById(activeThreadId);
  syncConversationPanelVisibility(thread);
  renderMessages(thread, { preserveScroll: true });
}

function toggleMessageSelection(messageId) {
  if (!messageId) return;
  if (selectedMessageIds.has(messageId)) {
    selectedMessageIds.delete(messageId);
  } else {
    selectedMessageIds.add(messageId);
  }
  if (selectedMessageIds.size === 0) {
    exitSelectionMode();
    return;
  }
  updateSelectionToolbar();
  const thread = getThreadById(activeThreadId);
  renderMessages(thread, { preserveScroll: true });
}

function setReplyTarget(item) {
  if (!item?.messageId || item.isDeleted) return;
  const preview =
    item.preview ||
    item.replyPreview ||
    item.copyText ||
    item.text ||
    "Message";
  replyTarget = {
    messageId: item.messageId,
    preview,
  };
  replyStripTextEl.textContent = preview;
  syncConversationPanelVisibility(getThreadById(activeThreadId));
  composeInputEl.focus();
}

function clearReplyTarget() {
  replyTarget = null;
  syncConversationPanelVisibility(getThreadById(activeThreadId));
}

function openMessageInfoModal(item) {
  if (!item) return;
  messageInfoBodyEl.innerHTML = `
    <div class="message-info-row">
      <span class="message-info-label">Sent</span>
      <span class="message-info-value">${escapeHtml(item.sentAt || "Not available")}</span>
    </div>
    <div class="message-info-row">
      <span class="message-info-label">Delivered</span>
      <span class="message-info-value">${escapeHtml(item.deliveredAt || "Not yet delivered")}</span>
    </div>
    <div class="message-info-row">
      <span class="message-info-label">Read by patient</span>
      <span class="message-info-value">${escapeHtml(item.readAt || "Not yet read")}</span>
    </div>
  `;
  messageInfoModalEl.hidden = false;
  syncBodyModalLock();
}

function closeMessageInfoModal() {
  messageInfoModalEl.hidden = true;
  syncBodyModalLock();
}

async function openForwardModal(messageIds) {
  const ids = sortMessageIdsByConversationOrder(messageIds);
  if (ids.length === 0) return;
  pendingForwardMessageIds = ids;
  selectedForwardPatientIds = new Set();
  forwardMessageErrorEl.hidden = true;
  forwardMessageErrorEl.textContent = "";
  forwardMessageSubmitBtn.disabled = true;
  forwardMessageListEl.innerHTML =
    '<p class="communication-messages-empty">Loading patients…</p>';
  forwardMessageModalEl.hidden = false;
  syncBodyModalLock();

  try {
    const targets = await fetchForwardTargets(loggedInStaffId);
    const thread = getThreadById(activeThreadId);
    const currentPatientId = thread?.patientId || "";
    const filtered = targets.filter((target) => target.patientId !== currentPatientId);
    if (filtered.length === 0) {
      forwardMessageListEl.innerHTML =
        '<p class="communication-messages-empty">No other patients available.</p>';
      return;
    }
    forwardMessageListEl.innerHTML = filtered
      .map(
        (target) => `
          <label class="message-forward-item" data-forward-patient-id="${escapeHtml(target.patientId)}">
            <input type="checkbox" value="${escapeHtml(target.patientId)}" />
            <span>${escapeHtml(target.name)} (${escapeHtml(target.patientId)})</span>
          </label>
        `,
      )
      .join("");
  } catch (error) {
    forwardMessageListEl.innerHTML = "";
    forwardMessageErrorEl.hidden = false;
    forwardMessageErrorEl.textContent =
      error?.message || "Could not load patients for forwarding.";
  }
}

function closeForwardModal() {
  forwardMessageModalEl.hidden = true;
  pendingForwardMessageIds = [];
  selectedForwardPatientIds = new Set();
  syncBodyModalLock();
}

function openDeleteModal(messageIds) {
  const ids = sortMessageIdsByConversationOrder(messageIds);
  if (ids.length === 0) return;
  pendingDeleteMessageIds = ids;
  deleteMessageModalEl.hidden = false;
  syncBodyModalLock();
}

function closeDeleteModal() {
  deleteMessageModalEl.hidden = true;
  pendingDeleteMessageIds = [];
  syncBodyModalLock();
}

async function copySelectedMessages() {
  const items = sortMessageIdsByConversationOrder([...selectedMessageIds])
    .map((id) => getMessageItemById(id))
    .filter((item) => item && !item.isDeleted);
  if (items.length === 0) return;
  const text = items.map((item) => item.copyText || item.text || "").filter(Boolean).join("\n\n");
  if (!text) {
    window.alert("Nothing to copy from the selected messages.");
    return;
  }
  try {
    await navigator.clipboard.writeText(text);
  } catch {
    window.alert("Could not copy to clipboard.");
  }
}

async function handleDeleteForMe() {
  if (isMessageActionBusy || pendingDeleteMessageIds.length === 0) return;
  isMessageActionBusy = true;
  try {
    for (const messageId of pendingDeleteMessageIds) {
      await hideMessageForUser(messageId, loggedInStaffId);
    }
    closeDeleteModal();
    exitSelectionMode();
  } catch (error) {
    window.alert(error?.message || "Could not delete message for you.");
  } finally {
    isMessageActionBusy = false;
  }
}

async function handleDeleteForEveryone() {
  if (isMessageActionBusy || pendingDeleteMessageIds.length === 0) return;
  isMessageActionBusy = true;
  try {
    for (const messageId of pendingDeleteMessageIds) {
      await deleteMessageForEveryone(messageId, loggedInStaffId);
    }
    closeDeleteModal();
    exitSelectionMode();
  } catch (error) {
    window.alert(error?.message || "Could not delete message for everyone.");
  } finally {
    isMessageActionBusy = false;
  }
}

async function handleForwardSubmit() {
  if (isMessageActionBusy || pendingForwardMessageIds.length === 0) return;
  const patientIds = [...selectedForwardPatientIds];
  if (patientIds.length === 0) {
    forwardMessageErrorEl.hidden = false;
    forwardMessageErrorEl.textContent = "Select at least one patient.";
    return;
  }

  isMessageActionBusy = true;
  forwardMessageSubmitBtn.disabled = true;
  try {
    for (const messageId of pendingForwardMessageIds) {
      await forwardMessageToPatients({
        messageId,
        staffId: loggedInStaffId,
        patientIds,
      });
    }
    closeForwardModal();
    exitSelectionMode();
    window.alert("Message forwarded successfully.");
  } catch (error) {
    forwardMessageErrorEl.hidden = false;
    forwardMessageErrorEl.textContent = error?.message || "Could not forward message.";
  } finally {
    isMessageActionBusy = false;
    forwardMessageSubmitBtn.disabled = selectedForwardPatientIds.size === 0;
  }
}

async function handleMessageAction(action, messageId) {
  const item = getMessageItemById(messageId);
  closeAllMessageMenus();
  if (!item) return;

  if (action === "info") {
    openMessageInfoModal(item);
    return;
  }
  if (action === "reply") {
    if (item.isDeleted) {
      window.alert("You cannot reply to a deleted message.");
      return;
    }
    try {
      const source = await fetchMessageById(messageId);
      setReplyTarget({
        messageId,
        preview: buildReplyPreview(source),
      });
    } catch {
      setReplyTarget(item);
    }
    return;
  }
  if (action === "forward") {
    if (item.isDeleted) {
      window.alert("Deleted messages cannot be forwarded.");
      return;
    }
    await openForwardModal([messageId]);
    return;
  }
  if (action === "select") {
    enterSelectionMode(messageId);
    return;
  }
  if (action === "delete") {
    openDeleteModal([messageId]);
  }
}

function renderMessageMenu(messageId) {
  if (activeThreadId === "sys_ag_virtual") return "";
  return `
    <div class="chat-bubble-menu-wrap">
      <button
        type="button"
        class="chat-bubble-menu-btn"
        data-message-menu="${escapeHtml(messageId)}"
        aria-label="Message options"
        aria-expanded="false"
        aria-haspopup="menu"
      >
        <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
          <circle cx="12" cy="5" r="2" />
          <circle cx="12" cy="12" r="2" />
          <circle cx="12" cy="19" r="2" />
        </svg>
      </button>
      <div class="chat-bubble-menu" data-message-menu-panel="${escapeHtml(messageId)}" role="menu" hidden>
        <button type="button" class="chat-bubble-menu-item" data-message-action="info" data-message-id="${escapeHtml(messageId)}" role="menuitem">Message info</button>
        <button type="button" class="chat-bubble-menu-item" data-message-action="reply" data-message-id="${escapeHtml(messageId)}" role="menuitem">Reply</button>
        <button type="button" class="chat-bubble-menu-item" data-message-action="forward" data-message-id="${escapeHtml(messageId)}" role="menuitem">Forward</button>
        <button type="button" class="chat-bubble-menu-item" data-message-action="select" data-message-id="${escapeHtml(messageId)}" role="menuitem">Select</button>
        <button type="button" class="chat-bubble-menu-item chat-bubble-menu-item--danger" data-message-action="delete" data-message-id="${escapeHtml(messageId)}" role="menuitem">Delete</button>
      </div>
    </div>
  `;
}

function openPhotoPreview(url, alt = "Photo") {
  if (!url) return;
  photoPreviewImageEl.src = url;
  photoPreviewImageEl.alt = alt;
  photoPreviewModalEl.hidden = false;
  syncBodyModalLock();
  photoPreviewCloseBtn.focus();
}

function closePhotoPreview() {
  photoPreviewModalEl.hidden = true;
  photoPreviewImageEl.removeAttribute("src");
  photoPreviewImageEl.alt = "";
  syncBodyModalLock();
}

function closeAddContactModal() {
  addContactModalEl.hidden = true;
  syncBodyModalLock();
}

async function openAddContactModal() {
  addContactErrorEl.hidden = true;
  addContactErrorEl.textContent = "";
  selectedAddContactPatientId = "";
  addContactPatientListEl.innerHTML = "";
  addContactSubmitBtn.disabled = true;

  addContactModalEl.hidden = false;
  syncBodyModalLock();

  try {
    const patients = await fetchAvailablePatientsForNewConversation(
      loggedInStaffId,
      loggedInStaffProfile,
    );
    if (patients.length === 0) {
      addContactErrorEl.textContent = "No available patient to add right now.";
      addContactErrorEl.hidden = false;
      return;
    }

    addContactPatientListEl.innerHTML = patients
      .map(
        (patient) => `
          <button
            type="button"
            class="add-contact-patient-item${patient.hasConversation ? " is-disabled" : ""}"
            data-patient-id="${escapeHtml(patient.patientId)}"
            data-disabled="${patient.hasConversation ? "true" : "false"}"
            role="option"
            aria-selected="false"
            aria-disabled="${patient.hasConversation ? "true" : "false"}"
            ${patient.hasConversation ? "disabled" : ""}
          >
            <span class="add-contact-patient-name">${escapeHtml(patient.name)}</span>
            <span class="add-contact-patient-id">${escapeHtml(patient.patientId)}${patient.hasConversation ? " · Already added" : ""}</span>
          </button>
        `,
      )
      .join("");

    const firstEnabled = addContactPatientListEl.querySelector(
      '.add-contact-patient-item[data-disabled="false"]',
    );
    if (firstEnabled) {
      selectedAddContactPatientId = firstEnabled.dataset.patientId || "";
      firstEnabled.classList.add("is-selected");
      firstEnabled.setAttribute("aria-selected", "true");
      addContactSubmitBtn.disabled = false;
      firstEnabled.focus();
    } else {
      selectedAddContactPatientId = "";
      addContactSubmitBtn.disabled = true;
      addContactErrorEl.textContent =
        "All listed patients already have an active conversation.";
      addContactErrorEl.hidden = false;
    }
  } catch (error) {
    addContactErrorEl.textContent =
      error?.message || "Could not load available patients.";
    addContactErrorEl.hidden = false;
  }
}

async function handleAddContactSubmit(event) {
  event.preventDefault();

  const patientId = selectedAddContactPatientId;
  if (!patientId) {
    addContactErrorEl.textContent = "Please select a patient.";
    addContactErrorEl.hidden = false;
    return;
  }

  await createConversationFromSelectedPatient(patientId);
}

async function createConversationFromSelectedPatient(patientId) {
  if (isCreatingContact) return;

  isCreatingContact = true;
  addContactErrorEl.hidden = true;
  addContactSubmitBtn.disabled = true;
  const originalLabel = addContactSubmitBtn.innerHTML;
  addContactSubmitBtn.textContent = "Adding…";

  addContactPatientListEl
    .querySelectorAll(".add-contact-patient-item")
    .forEach((btn) => {
      btn.disabled = true;
    });

  try {
    const newThread = await createConversationForStaffPatient({
      staffId: loggedInStaffId,
      patientId,
    });
    activeThreadId = newThread.id;
    closeAddContactModal();
    applyChatThreads([newThread, ...chatThreads.filter((t) => t.id !== newThread.id)]);
    await selectThread(activeThreadId);
  } catch (error) {
    addContactErrorEl.textContent =
      error?.message || "Could not add contact. Please try again.";
    addContactErrorEl.hidden = false;
  } finally {
    isCreatingContact = false;
    addContactSubmitBtn.disabled = false;
    addContactSubmitBtn.innerHTML = originalLabel;

    addContactPatientListEl
      .querySelectorAll(".add-contact-patient-item")
      .forEach((btn) => {
        btn.disabled = false;
      });
  }
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function escapeRegExp(text) {
  return String(text).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function getConversationSearchTerms(query) {
  return String(query || "")
    .trim()
    .split(/\s+/)
    .filter((term) => term.length > 0);
}

function highlightSearchText(text, query = conversationSearchQuery) {
  const raw = String(text ?? "");
  const terms = getConversationSearchTerms(query);
  if (terms.length === 0) return escapeHtml(raw);

  const pattern = new RegExp(`(${terms.map(escapeRegExp).join("|")})`, "gi");
  const parts = raw.split(pattern);
  return parts
    .map((part) => {
      if (!part) return "";
      const isMatch = terms.some(
        (term) => part.toLowerCase() === term.toLowerCase(),
      );
      const safe = escapeHtml(part);
      return isMatch
        ? `<mark class="chat-search-highlight">${safe}</mark>`
        : safe;
    })
    .join("");
}

function syncConversationSearchUi() {
  if (!conversationSearchEl || !conversationSearchBtnEl) return;
  conversationSearchEl.hidden = !conversationSearchOpen;
  conversationSearchBtnEl.classList.toggle("is-active", conversationSearchOpen);
  conversationSearchBtnEl.setAttribute(
    "aria-expanded",
    conversationSearchOpen ? "true" : "false",
  );
}

function openConversationSearch() {
  if (!activeThreadId) return;
  conversationSearchOpen = true;
  syncConversationSearchUi();
  conversationSearchInputEl?.focus();
}

function closeConversationSearch({ rerender = true } = {}) {
  conversationSearchOpen = false;
  conversationSearchQuery = "";
  if (conversationSearchInputEl) conversationSearchInputEl.value = "";
  syncConversationSearchUi();
  if (!rerender) return;
  const thread = getThreadById(activeThreadId);
  if (thread) renderMessages(thread, { preserveScroll: true });
}

function scrollToFirstSearchHighlight() {
  if (!conversationSearchQuery.trim()) return;
  const firstMatch = messagesEl.querySelector(".chat-search-highlight");
  if (!firstMatch) return;
  firstMatch.scrollIntoView({ block: "center", behavior: "smooth" });
}

function getConversationMessageDateKeys(thread = getThreadById(activeThreadId)) {
  const dates = new Set();
  for (const item of thread?.messages || []) {
    if (item.type === "divider" || !item.dateKey) continue;
    dates.add(item.dateKey);
  }
  return dates;
}

function getConversationDateBounds(thread = getThreadById(activeThreadId)) {
  const keys = [...getConversationMessageDateKeys(thread)].sort();
  if (keys.length === 0) return null;
  const [minYear, minMonth] = keys[0].split("-").map(Number);
  const [maxYear, maxMonth] = keys[keys.length - 1].split("-").map(Number);
  return {
    minYear,
    minMonth: minMonth - 1,
    maxYear,
    maxMonth: maxMonth - 1,
  };
}

function formatCalendarMonthLabel(year, month) {
  return new Date(year, month, 1).toLocaleDateString("en-US", {
    month: "long",
    year: "numeric",
  });
}

function buildDateKey(year, month, day) {
  return `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`;
}

function getTodayDateKey() {
  const now = new Date();
  return buildDateKey(now.getFullYear(), now.getMonth(), now.getDate());
}

function setCalendarViewMonth(year, month) {
  calendarViewYear = year;
  calendarViewMonth = month;
  renderConversationCalendar();
}

function renderConversationCalendar() {
  if (!calendarGridEl || !calendarMonthLabelEl) return;

  const thread = getThreadById(activeThreadId);
  const messageDates = getConversationMessageDateKeys(thread);
  const bounds = getConversationDateBounds(thread);
  const todayKey = getTodayDateKey();

  calendarMonthLabelEl.textContent = formatCalendarMonthLabel(
    calendarViewYear,
    calendarViewMonth,
  );

  if (calendarPrevBtn) {
    calendarPrevBtn.disabled = !bounds
      || (calendarViewYear === bounds.minYear && calendarViewMonth <= bounds.minMonth);
  }
  if (calendarNextBtn) {
    calendarNextBtn.disabled = !bounds
      || (calendarViewYear === bounds.maxYear && calendarViewMonth >= bounds.maxMonth);
  }

  const firstOfMonth = new Date(calendarViewYear, calendarViewMonth, 1);
  const startOffset = firstOfMonth.getDay();
  const daysInMonth = new Date(calendarViewYear, calendarViewMonth + 1, 0).getDate();
  const cells = [];

  for (let i = 0; i < startOffset; i += 1) {
    cells.push({ outside: true, day: 0, dateKey: "" });
  }
  for (let day = 1; day <= daysInMonth; day += 1) {
    const dateKey = buildDateKey(calendarViewYear, calendarViewMonth, day);
    cells.push({
      outside: false,
      day,
      dateKey,
      hasMessages: messageDates.has(dateKey),
      isToday: dateKey === todayKey,
    });
  }
  while (cells.length % 7 !== 0) {
    cells.push({ outside: true, day: 0, dateKey: "" });
  }

  calendarGridEl.innerHTML = cells
    .map((cell) => {
      if (cell.outside) {
        return '<span class="chat-calendar-day is-outside" aria-hidden="true"></span>';
      }
      const classes = ["chat-calendar-day"];
      if (cell.hasMessages) classes.push("has-messages");
      if (cell.isToday) classes.push("is-today");
      const disabled = cell.hasMessages ? "" : " disabled";
      const aria = cell.hasMessages
        ? ` aria-label="Jump to messages on ${cell.day}"`
        : ` aria-label="${cell.day}"`;
      return `<button type="button" class="${classes.join(" ")}" data-calendar-date="${escapeHtml(cell.dateKey)}"${disabled}${aria}>${cell.day}</button>`;
    })
    .join("");
}

function scrollToFirstMessageOnDate(dateKey) {
  if (!dateKey || !messagesEl) return false;

  const divider = messagesEl.querySelector(`[data-divider-date="${dateKey}"]`);
  if (divider) {
    divider.scrollIntoView({ block: "start", behavior: "smooth" });
    return true;
  }

  const row = messagesEl.querySelector(`[data-message-date="${dateKey}"]`);
  if (!row) return false;

  row.scrollIntoView({ block: "start", behavior: "smooth" });
  return true;
}

function openConversationCalendarModal() {
  if (!activeThreadId || !calendarModalEl) return;

  const thread = getThreadById(activeThreadId);
  if (getConversationMessageDateKeys(thread).size === 0) {
    window.alert("No messages in this conversation yet.");
    return;
  }

  const anchorKey = [...getConversationMessageDateKeys(thread)].sort().pop();
  if (anchorKey) {
    const [year, month] = anchorKey.split("-").map(Number);
    calendarViewYear = year;
    calendarViewMonth = month - 1;
  } else {
    const now = new Date();
    calendarViewYear = now.getFullYear();
    calendarViewMonth = now.getMonth();
  }

  renderConversationCalendar();
  calendarModalEl.hidden = false;
  calendarBtnEl?.classList.add("is-active");
  syncBodyModalLock();
}

function closeConversationCalendarModal() {
  if (!calendarModalEl) return;
  calendarModalEl.hidden = true;
  calendarBtnEl?.classList.remove("is-active");
  syncBodyModalLock();
}

function handleCalendarDateSelect(dateKey) {
  if (!dateKey) return;
  closeConversationCalendarModal();
  requestAnimationFrame(() => {
    if (!scrollToFirstMessageOnDate(dateKey)) {
      window.alert("No messages were found for the selected date.");
    }
  });
}

function formatCallTimer(totalSeconds) {
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
}

function stopCallRingtone() {
  if (callRingtone) {
    callRingtone.stop();
    callRingtone = null;
  }
}

function startOutgoingCallRingtone() {
  stopCallRingtone();
  callRingtone = new CallRingtone("outgoing");
  callRingtone.start();
}

function startIncomingCallRingtone() {
  stopCallRingtone();
  callRingtone = new CallRingtone("incoming");
  callRingtone.start();
}

function setVoiceCallTimerVisible(visible) {
  if (!voiceCallTimerEl) return;
  voiceCallTimerEl.hidden = !visible;
  if (!visible) voiceCallTimerEl.textContent = "00:00";
}

function setVoiceCallMuteVisible(visible) {
  if (!voiceCallMuteBtn) return;
  voiceCallMuteBtn.hidden = !visible;
  if (!visible) {
    voiceCallMuteBtn.classList.remove("is-muted");
    const label = voiceCallMuteBtn.querySelector("span");
    if (label) label.textContent = "Mute";
  }
}

function stopVoiceCallTimer() {
  if (voiceCallTimerInterval) {
    clearInterval(voiceCallTimerInterval);
    voiceCallTimerInterval = null;
  }
}

function startVoiceCallTimer(startedAtMs) {
  stopVoiceCallTimer();
  setVoiceCallTimerVisible(true);
  const update = () => {
    const elapsed = Math.max(0, Math.floor((Date.now() - startedAtMs) / 1000));
    if (voiceCallTimerEl) voiceCallTimerEl.textContent = formatCallTimer(elapsed);
  };
  update();
  voiceCallTimerInterval = setInterval(update, 1000);
}

function showVoiceCallOverlay(thread) {
  if (!voiceCallOverlayEl || !thread) return;
  activeVoiceCallThread = thread;
  voiceCallNameEl.textContent = thread.name || thread.patientId;
  voiceCallAvatarEl.textContent = getInitials(thread.name || thread.patientId);
  voiceCallAvatarEl.className = `chat-voice-call-avatar chat-avatar chat-avatar--${thread.avatarColor || "teal"}`;
  voiceCallStatusEl.textContent = "Connecting…";
  setVoiceCallTimerVisible(false);
  setVoiceCallMuteVisible(false);
  voiceCallMuteBtn?.classList.remove("is-muted");
  if (voiceCallMuteBtn) {
    voiceCallMuteBtn.querySelector("span").textContent = "Mute";
  }
  voiceCallOverlayEl.hidden = false;
}

function hideVoiceCallOverlay() {
  stopCallRingtone();
  stopVoiceCallTimer();
  setVoiceCallTimerVisible(false);
  setVoiceCallMuteVisible(false);
  if (voiceCallOverlayEl) voiceCallOverlayEl.hidden = true;
  activeVoiceCallThread = null;
}

function getVoiceCallController() {
  if (!voiceCallController) {
    voiceCallController = new VoiceCallController();
    voiceCallController.setRemoteAudioElement(voiceCallRemoteAudioEl);
    voiceCallController.onStateChange = (payload) => {
      void handleVoiceCallStateChange(payload);
    };
  }
  return voiceCallController;
}

async function handleVoiceCallStateChange({ state, reason, durationSeconds, wasConnected }) {
  if (state === "connecting") {
    stopCallRingtone();
    voiceCallStatusEl.textContent = "Connecting…";
    setVoiceCallTimerVisible(false);
    setVoiceCallMuteVisible(false);
    return;
  }
  if (state === "ringing") {
    voiceCallStatusEl.textContent = "Calling…";
    setVoiceCallTimerVisible(false);
    setVoiceCallMuteVisible(false);
    startOutgoingCallRingtone();
    return;
  }
  if (state === "connected") {
    stopCallRingtone();
    voiceCallStatusEl.textContent = "Connected";
    setVoiceCallMuteVisible(true);
    const startedAtMs = voiceCallController?.connectedAt || Date.now();
    startVoiceCallTimer(startedAtMs);
    return;
  }
  if (state === "ended") {
    stopCallRingtone();
    const thread = activeVoiceCallThread || getThreadById(activeThreadId);
    hideVoiceCallOverlay();
    hideIncomingCallModal();
    if (callStartBtn) callStartBtn.disabled = false;
    const shouldLogCall = staffInitiatedCall;
    staffInitiatedCall = false;
    pendingIncomingCall = null;
    if (thread && shouldLogCall) {
      try {
        let callStatus = "completed";
        if (reason === "unanswered") callStatus = "unanswered";
        else if (reason === "missed") callStatus = "missed";
        else if (reason === "declined") callStatus = "declined";
        else if (!wasConnected) callStatus = "unanswered";

        await sendCallMessage({
          conversationId: thread.conversationId,
          staffId: loggedInStaffId,
          patientId: thread.patientId,
          durationSeconds: wasConnected ? durationSeconds : 0,
          status: callStatus,
        });
      } catch {
        /* call log failure should not block UI reset */
      }
    }
  }
}

function resolveThreadForIncomingCall(call) {
  if (!call) return null;
  return (
    chatThreads.find(
      (thread) =>
        thread.conversationId === call.conversationId &&
        thread.patientId === call.patientId,
    ) ||
    chatThreads.find((thread) => thread.patientId === call.patientId) ||
    null
  );
}

function showIncomingCallModal(call) {
  if (!incomingCallModalEl || !call) return;
  if (pendingIncomingCall?.callId === call.callId && !incomingCallModalEl.hidden) {
    return;
  }
  pendingIncomingCall = call;
  const thread = resolveThreadForIncomingCall(call);
  const displayName = thread?.name || call.patientId || "Patient";
  incomingCallTitleEl.textContent = displayName;
  incomingCallAvatarEl.textContent = getInitials(displayName);
  incomingCallAvatarEl.className = `chat-call-avatar chat-avatar chat-avatar--${thread?.avatarColor || "teal"}`;
  incomingCallHintEl.textContent = `${displayName} is calling you.`;
  incomingCallModalEl.hidden = false;
  startIncomingCallRingtone();
  syncBodyModalLock();
}

function hideIncomingCallModal({ stopRingtone = true } = {}) {
  if (!incomingCallModalEl) return;
  incomingCallModalEl.hidden = true;
  if (stopRingtone) stopCallRingtone();
  syncBodyModalLock();
}

function stopIncomingCallWatcher() {
  releaseFirestoreListener(unsubscribeIncomingCalls);
  unsubscribeIncomingCalls = null;
}

function startIncomingCallWatcher() {
  stopIncomingCallWatcher();
  if (!loggedInStaffId) return;

  unsubscribeIncomingCalls = subscribeStaffIncomingCalls(loggedInStaffId, {
    onIncoming: (call) => {
      if (
        voiceCallController?.state &&
        !["idle", "ended"].includes(voiceCallController.state)
      ) {
        return;
      }
      showIncomingCallModal(call);
    },
    onCleared: () => {
      pendingIncomingCall = null;
      hideIncomingCallModal();
    },
  });
}

async function acceptIncomingCall() {
  const call = pendingIncomingCall;
  if (!call || incomingCallAcceptBtn?.disabled) return;

  if (incomingCallAcceptBtn) incomingCallAcceptBtn.disabled = true;
  if (incomingCallDeclineBtn) incomingCallDeclineBtn.disabled = true;

  try {
    const thread = resolveThreadForIncomingCall(call);
    if (thread && thread.id !== activeThreadId) {
      await selectThread(thread.id);
    }

    hideIncomingCallModal({ stopRingtone: true });
    staffInitiatedCall = false;
    pendingIncomingCall = null;

    if (thread) {
      showVoiceCallOverlay(thread);
    } else {
      activeVoiceCallThread = {
        conversationId: call.conversationId,
        patientId: call.patientId,
        name: call.patientId,
      };
      voiceCallNameEl.textContent = call.patientId;
      voiceCallAvatarEl.textContent = getInitials(call.patientId);
      voiceCallOverlayEl.hidden = false;
    }

    await getVoiceCallController().answerIncoming({
      callId: call.callId,
      conversationId: call.conversationId,
      staffId: loggedInStaffId,
      patientId: call.patientId,
      offer: call.offer,
    });
  } catch (error) {
    hideVoiceCallOverlay();
    window.alert(error?.message || "Could not answer the call.");
  } finally {
    if (incomingCallAcceptBtn) incomingCallAcceptBtn.disabled = false;
    if (incomingCallDeclineBtn) incomingCallDeclineBtn.disabled = false;
  }
}

async function declineIncomingCall() {
  const call = pendingIncomingCall;
  if (!call) {
    hideIncomingCallModal();
    return;
  }
  await getVoiceCallController().declineIncoming(call.callId);
  pendingIncomingCall = null;
  hideIncomingCallModal();
}

function closeCallModal() {
  if (!callModalEl) return;
  callModalEl.hidden = true;
  if (callErrorEl) {
    callErrorEl.hidden = true;
    callErrorEl.textContent = "";
  }
  if (callStartBtn) callStartBtn.disabled = false;
  syncBodyModalLock();
}

function openCallModal() {
  const thread = getThreadById(activeThreadId);
  if (!thread?.patientId || !callModalEl) return;

  callModalEl.hidden = false;
  callErrorEl.hidden = true;
  callErrorEl.textContent = "";
  callNameEl.textContent = thread.name || thread.patientId;
  callAvatarEl.textContent = getInitials(thread.name || thread.patientId);
  callAvatarEl.className = `chat-call-avatar chat-avatar chat-avatar--${thread.avatarColor || "teal"}`;
  if (callPatientIdEl) {
    callPatientIdEl.textContent = thread.patientId;
  }
  callStartBtn.disabled = false;
  syncBodyModalLock();
}

async function startVoiceCall() {
  const thread = getThreadById(activeThreadId);
  if (!thread?.patientId || callStartBtn?.disabled) return;
  if (voiceCallController?.state && !["idle", "ended"].includes(voiceCallController.state)) {
    window.alert("A call is already in progress.");
    return;
  }

  callStartBtn.disabled = true;
  staffInitiatedCall = true;
  try {
    closeCallModal();
    showVoiceCallOverlay(thread);
    await getVoiceCallController().startOutgoing({
      conversationId: thread.conversationId,
      staffId: loggedInStaffId,
      patientId: thread.patientId,
    });
  } catch (error) {
    staffInitiatedCall = false;
    hideVoiceCallOverlay();
    window.alert(error?.message || "Could not start the voice call.");
    callStartBtn.disabled = false;
  }
}

async function endActiveVoiceCall() {
  if (!voiceCallController || voiceCallController.state === "idle") {
    hideVoiceCallOverlay();
    return;
  }
  const wasConnected = Boolean(voiceCallController.connectedAt);
  await voiceCallController.hangUp({
    reason: wasConnected ? "ended" : "unanswered",
  });
}

function toggleVoiceCallMute() {
  if (!voiceCallController || voiceCallController.state !== "connected") return;
  const muted = voiceCallController.toggleMute();
  voiceCallMuteBtn?.classList.toggle("is-muted", muted);
  const label = voiceCallMuteBtn?.querySelector("span");
  if (label) label.textContent = muted ? "Unmute" : "Mute";
}

function getThreadById(id) {
  return chatThreads.find((thread) => thread.id === id);
}

function normalizeParticipantId(id) {
  return String(id || "").trim();
}

function clearPendingPatientNavigation() {
  const url = new URL(window.location.href);
  if (url.searchParams.has("patient")) {
    url.searchParams.delete("patient");
    const next = url.pathname + (url.search || "") + url.hash;
    window.history.replaceState({}, "", next);
  }
  try {
    sessionStorage.removeItem(OPEN_COMMUNICATION_PATIENT_KEY);
  } catch {
    /* ignore */
  }
}

function findThreadForPendingPatient() {
  const targetPatientId = normalizeParticipantId(pendingOpenPatientId);
  if (!targetPatientId) return null;
  return (
    chatThreads.find(
      (thread) => normalizeParticipantId(thread.patientId) === targetPatientId,
    ) || null
  );
}

function openPendingPatientThread(thread) {
  if (!thread || pendingOpenResolved) return false;
  pendingOpenResolved = true;
  forcedActiveThreadId = thread.id;
  clearPendingPatientNavigation();
  selectThread(thread.id);
  return true;
}

function trySelectPendingPatientFromThreads() {
  if (!pendingOpenPatientId || pendingOpenResolved || !loggedInStaffId) {
    return false;
  }
  return openPendingPatientThread(findThreadForPendingPatient());
}

function shouldDeferEmptyConversationState() {
  return Boolean(
    pendingOpenPatientId &&
      !pendingOpenResolved &&
      (pendingOpenInProgress || isLoadingThreads),
  );
}

async function resolveAndOpenPendingPatient() {
  if (!pendingOpenPatientId || pendingOpenResolved || !loggedInStaffId) {
    return;
  }

  const existing = findThreadForPendingPatient();
  if (existing) {
    openPendingPatientThread(existing);
    return;
  }

  pendingOpenInProgress = true;
  try {
    const thread = await createConversationForStaffPatient({
      staffId: loggedInStaffId,
      patientId: pendingOpenPatientId,
    });
    forcedActiveThreadId = thread.id;
    chatThreads = [
      thread,
      ...chatThreads.filter((item) => item.id !== thread.id),
    ];
    openPendingPatientThread(thread);
  } catch (error) {
    pendingOpenResolved = true;
    clearPendingPatientNavigation();
    window.alert(
      error?.message || "Could not open conversation with this patient.",
    );
  } finally {
    pendingOpenInProgress = false;
  }
}

async function tryOpenPendingPatientConversation() {
  if (!pendingOpenPatientId || pendingOpenResolved || !loggedInStaffId) {
    return;
  }
  if (trySelectPendingPatientFromThreads()) {
    return;
  }
  if (!pendingOpenInProgress) {
    await resolveAndOpenPendingPatient();
  }
}

function filterThreads() {
  const q = searchQuery.toLowerCase();
  return chatThreads.filter((thread) => {
    if (chatFilter === "unread" && !thread.unread) return false;
    if (!q) return true;
    const haystack = `${thread.name} ${thread.preview}`.toLowerCase();
    return haystack.includes(q);
  });
}

function renderThreadList() {
  if (isLoadingThreads) {
    threadListEl.innerHTML = "";
    return;
  }

  const threads = filterThreads();
  if (threads.length === 0) {
    const emptyMessage =
      chatFilter === "unread"
        ? "There is no unread message."
        : "No active conversations yet.";
    threadListEl.innerHTML = `<li class="communication-thread-empty">${emptyMessage}</li>`;
    return;
  }

  threadListEl.innerHTML = threads
    .map((thread) => {
      const isActive = thread.id === activeThreadId;
      const initials = getInitials(thread.name);
      return `
        <li>
          <button
            type="button"
            class="communication-thread${isActive ? " is-active" : ""}${thread.unread ? " is-unread" : ""}"
            data-thread-id="${thread.id}"
          >
            <span class="chat-avatar chat-avatar--${thread.avatarColor}" aria-hidden="true">${escapeHtml(initials)}</span>
            <span class="communication-thread-body">
              <span class="communication-thread-top">
                <span class="communication-thread-name">${escapeHtml(thread.name)}</span>
                <span class="communication-thread-time">${escapeHtml(thread.time)}</span>
              </span>
              <span class="communication-thread-preview">${escapeHtml(thread.preview)}</span>
            </span>
          </button>
        </li>
      `;
    })
    .join("");
}

function renderMessages(thread, options = {}) {
  const { scrollToBottom = false, preserveScroll = false } = options;
  const previousScrollTop = messagesEl.scrollTop;
  const wasNearBottom = isNearMessagesBottom(messagesEl);
  const shouldScrollToBottom =
    scrollToBottom || (!preserveScroll && thread && wasNearBottom);

  syncConversationPanelVisibility(thread);

  if (!thread) {
    messagesEl.innerHTML = `
      <div class="communication-empty-state">
        <span class="communication-empty-icon" aria-hidden="true">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h10" />
            <line x1="19" y1="8" x2="19" y2="14" />
            <line x1="16" y1="11" x2="22" y2="11" />
          </svg>
        </span>
        <p class="communication-empty-title">No chat selected</p>
        <p class="communication-empty-subtitle">Select a conversation or add a new contact to start chatting.</p>
        <button type="button" class="communication-empty-btn" id="btn-add-contact-empty">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
            <line x1="12" y1="5" x2="12" y2="19" />
            <line x1="5" y1="12" x2="19" y2="12" />
          </svg>
          Add Contact
        </button>
      </div>
    `;
    document
      .getElementById("btn-add-contact-empty")
      ?.addEventListener("click", () => {
        openAddContactModal();
      });
    return;
  }

  const items = thread.messages || [];
  messagesEl.classList.toggle("is-selection-mode", selectionMode);
  if (items.length === 0) {
    messagesEl.innerHTML =
      '<p class="communication-messages-empty">No messages in this conversation yet.</p>';
    return;
  }

  messagesEl.innerHTML = items
    .map((item) => {
      if (item.type === "divider") {
        const dividerDateAttr = item.dateKey
          ? ` data-divider-date="${escapeHtml(item.dateKey)}"`
          : "";
        return `<p class="chat-divider" role="separator"${dividerDateAttr}>${escapeHtml(item.label)}</p>`;
      }
      const bubbleClass =
        item.type === "out" ? "chat-bubble chat-bubble--out" : "chat-bubble chat-bubble--in";
      const rowClass =
        item.type === "out"
          ? "chat-message-row chat-message-row--out"
          : "chat-message-row chat-message-row--in";
      const isSelected = selectedMessageIds.has(item.messageId);
      const selectionClass = selectionMode ? " is-selectable" : "";
      const selectedClass = isSelected ? " is-selected" : "";
      const body = renderMessageBubbleBody(item);
      const selectionMarkup = selectionMode
        ? `<label class="chat-message-select">
            <input type="checkbox" data-message-select="${escapeHtml(item.messageId)}" ${isSelected ? "checked" : ""} aria-label="Select message" />
          </label>`
        : "";
      const menuMarkup = selectionMode ? "" : renderMessageMenu(item.messageId);
      return `
        <div class="${rowClass}${selectionClass}${selectedClass}" data-message-row="${escapeHtml(item.messageId)}"${item.dateKey ? ` data-message-date="${escapeHtml(item.dateKey)}"` : ""}>
          ${selectionMarkup}
          <div class="chat-bubble-shell">
            <div class="${bubbleClass}">
              ${body}
              <span class="chat-bubble-time">${escapeHtml(item.time)}</span>
            </div>
            ${menuMarkup}
          </div>
        </div>
      `;
    })
    .join("");

  if (openMessageMenuId) {
    const panel = messagesEl.querySelector(
      `[data-message-menu-panel="${openMessageMenuId}"]`,
    );
    const btn = messagesEl.querySelector(`[data-message-menu="${openMessageMenuId}"]`);
    if (panel && btn) {
      panel.hidden = false;
      btn.setAttribute("aria-expanded", "true");
    } else {
      openMessageMenuId = null;
    }
  }

  if (shouldScrollToBottom) {
    messagesEl.scrollTop = messagesEl.scrollHeight;
  } else {
    messagesEl.scrollTop = previousScrollTop;
  }

  requestAnimationFrame(() => updateScrollToBottomButton());
}

function renderMessageMetaBlocks(item) {
  const blocks = [];
  if (item.replyPreview) {
    blocks.push(`
      <div class="chat-bubble-reply">
        <span class="chat-bubble-reply-label">Replying to</span>
        <span class="chat-bubble-reply-text">${highlightSearchText(item.replyPreview)}</span>
      </div>
    `);
  }
  if (item.forwardedFromMessageId) {
    blocks.push(`
      <div class="chat-bubble-forwarded">
        <span class="chat-bubble-forwarded-label">Forwarded</span>
        <span class="chat-bubble-forwarded-text">Forwarded message</span>
      </div>
    `);
  }
  return blocks.join("");
}

function renderMessageBubbleBody(item) {
  const meta = renderMessageMetaBlocks(item);
  if (item.kind === "deleted" || item.isDeleted) {
    return `${meta}<p class="chat-bubble-deleted">${highlightSearchText(item.text || "This message was deleted")}</p>`;
  }
  if (item.kind === "photo" && item.url) {
    const photoAlt = escapeHtml(item.fileName || "Photo");
    return `${meta}
      <button
        type="button"
        class="chat-bubble-media-link chat-bubble-photo-btn"
        data-chat-photo-preview
        aria-label="View ${photoAlt}"
      >
        <img class="chat-bubble-image" src="${escapeHtml(item.url)}" alt="${photoAlt}" loading="lazy" />
      </button>
    `;
  }
  if (item.kind === "video" && item.url) {
    return `${meta}<video class="chat-bubble-video" src="${escapeHtml(item.url)}" controls preload="metadata"></video>`;
  }
  if (item.kind === "document" && item.url) {
    return `${meta}
      <a class="chat-bubble-document" href="${escapeHtml(item.url)}" target="_blank" rel="noopener noreferrer">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" />
          <polyline points="14 2 14 8 20 8" />
        </svg>
        <span class="chat-bubble-document-name">${highlightSearchText(item.fileName || "Document")}</span>
      </a>
    `;
  }
  if (item.kind === "voice" && item.url) {
    return `${meta}
      <div class="chat-bubble-voice">
        <audio class="chat-bubble-audio" src="${escapeHtml(item.url)}" controls preload="metadata"></audio>
        <span class="chat-bubble-voice-label">${highlightSearchText(item.text || "Voice message")}</span>
      </div>
    `;
  }
  if (item.kind === "call") {
    return `${meta}
      <p class="chat-bubble-call">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path d="M22 16.92v3a2 2 0 0 1-2.18 2 19.79 19.79 0 0 1-8.63-3.07 19.5 19.5 0 0 1-6-6 19.79 19.79 0 0 1-3.07-8.67A2 2 0 0 1 4.11 2h3a2 2 0 0 1 2 1.72c.127.96.361 1.903.7 2.81a2 2 0 0 1-.45 2.11L8.09 9.91a16 16 0 0 0 6 6l1.27-1.27a2 2 0 0 1 2.11-.45c.907.339 1.85.573 2.81.7A2 2 0 0 1 22 16.92z" />
        </svg>
        <span>${highlightSearchText(item.text || "Voice call")}</span>
      </p>
    `;
  }
  return `${meta}<p class="chat-bubble-text">${highlightSearchText(item.text || "—")}</p>`;
}

function closeAttachMenu() {
  attachMenuEl.hidden = true;
  attachBtnEl.setAttribute("aria-expanded", "false");
}

function openAttachmentPicker(inputEl) {
  closeAttachMenu();
  requestAnimationFrame(() => {
    inputEl.value = "";
    inputEl.click();
  });
}

function clearPendingCameraPreview() {
  if (pendingCameraPreviewUrl) {
    URL.revokeObjectURL(pendingCameraPreviewUrl);
    pendingCameraPreviewUrl = null;
  }
  pendingCameraFile = null;
  if (cameraStillEl) {
    cameraStillEl.removeAttribute("src");
    cameraStillEl.hidden = true;
  }
}

function setCameraModalMode(mode) {
  const isPreview = mode === "preview";
  cameraTitleEl.textContent = isPreview ? "Preview Photo" : "Take Photo";
  cameraSubtitleEl.hidden = !isPreview;
  cameraPreviewEl.hidden = isPreview;
  cameraFooterCaptureEl.hidden = isPreview;
  cameraFooterPreviewEl.hidden = !isPreview;
}

function stopCameraStream() {
  if (cameraStream) {
    for (const track of cameraStream.getTracks()) {
      track.stop();
    }
    cameraStream = null;
  }
  if (cameraPreviewEl) {
    cameraPreviewEl.srcObject = null;
  }
}

function closeCameraCapture() {
  stopCameraStream();
  clearPendingCameraPreview();
  setCameraModalMode("capture");
  cameraModalEl.hidden = true;
  cameraHintEl.hidden = true;
  cameraCaptureBtn.disabled = false;
  cameraSendBtn.disabled = false;
  syncBodyModalLock();
}

async function startCameraStream() {
  const constraints = [
    { video: { facingMode: { ideal: "environment" } }, audio: false },
    { video: { facingMode: "user" }, audio: false },
    { video: true, audio: false },
  ];

  let stream = null;
  let lastError = null;
  for (const constraint of constraints) {
    try {
      stream = await navigator.mediaDevices.getUserMedia(constraint);
      break;
    } catch (error) {
      lastError = error;
    }
  }

  if (!stream) {
    throw new Error(
      lastError?.message ||
        "Could not access the camera. Allow camera permission and try again.",
    );
  }

  cameraStream = stream;
  cameraPreviewEl.hidden = false;
  cameraPreviewEl.srcObject = stream;
  await cameraPreviewEl.play().catch(() => {});
  return stream;
}

async function openCameraCapture() {
  if (!activeThreadId || isSendingAttachment) return;
  closeAttachMenu();

  if (!navigator.mediaDevices?.getUserMedia) {
    window.alert("Camera is not supported in this browser.");
    return;
  }

  clearPendingCameraPreview();
  setCameraModalMode("capture");
  cameraModalEl.hidden = false;
  cameraHintEl.hidden = false;
  cameraHintEl.textContent = "Starting camera…";
  cameraCaptureBtn.disabled = true;
  syncBodyModalLock();

  try {
    await startCameraStream();
    cameraHintEl.hidden = true;
    cameraCaptureBtn.disabled = false;
    cameraCaptureBtn.focus();
  } catch (error) {
    closeCameraCapture();
    window.alert(error?.message || "Could not access the camera.");
  }
}

function showCameraPreview(file) {
  stopCameraStream();
  clearPendingCameraPreview();
  pendingCameraFile = file;
  pendingCameraPreviewUrl = URL.createObjectURL(file);
  cameraStillEl.src = pendingCameraPreviewUrl;
  cameraStillEl.hidden = false;
  setCameraModalMode("preview");
  cameraSendBtn.focus();
}

async function captureCameraPhoto() {
  if (!cameraStream || isSendingAttachment) return;

  const video = cameraPreviewEl;
  if (!video.videoWidth || !video.videoHeight) {
    window.alert("Camera is not ready yet. Please wait a moment.");
    return;
  }

  cameraCaptureBtn.disabled = true;
  const canvas = cameraCanvasEl;
  const maxDimension = 1280;
  let width = video.videoWidth;
  let height = video.videoHeight;
  const scale = Math.min(1, maxDimension / Math.max(width, height));
  width = Math.max(1, Math.round(width * scale));
  height = Math.max(1, Math.round(height * scale));
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext("2d");
  if (!context) {
    cameraCaptureBtn.disabled = false;
    window.alert("Could not capture photo.");
    return;
  }

  context.drawImage(video, 0, 0, width, height);
  const blob = await new Promise((resolve) => {
    canvas.toBlob(resolve, "image/jpeg", 0.82);
  });

  if (!blob) {
    cameraCaptureBtn.disabled = false;
    window.alert("Could not capture photo.");
    return;
  }

  const file = new File([blob], `photo-${Date.now()}.jpg`, {
    type: "image/jpeg",
  });
  cameraCaptureBtn.disabled = false;
  showCameraPreview(file);
}

async function retakeCameraPhoto() {
  clearPendingCameraPreview();
  setCameraModalMode("capture");
  cameraHintEl.hidden = false;
  cameraHintEl.textContent = "Starting camera…";
  cameraCaptureBtn.disabled = true;

  try {
    await startCameraStream();
    cameraHintEl.hidden = true;
    cameraCaptureBtn.disabled = false;
    cameraCaptureBtn.focus();
  } catch (error) {
    closeCameraCapture();
    window.alert(error?.message || "Could not access the camera.");
  }
}

async function sendCameraPhoto() {
  if (!pendingCameraFile || isSendingAttachment) return;
  const file = pendingCameraFile;
  closeCameraCapture();
  await handleAttachmentFileSelected(file, "camera");
}

function toggleAttachMenu() {
  const willOpen = attachMenuEl.hidden;
  attachMenuEl.hidden = !willOpen;
  attachBtnEl.setAttribute("aria-expanded", willOpen ? "true" : "false");
}

function setComposeBusy(isBusy) {
  composeInputEl.disabled = isBusy;
  attachBtnEl.disabled = isBusy;
}

async function handleAttachmentFileSelected(file, intent) {
  if (!file || !activeThreadId || isSendingAttachment) return;

  const thread = getThreadById(activeThreadId);
  if (!thread?.patientId) return;

  const messageType = inferMessageTypeForFile(file, intent);
  if (!messageType) {
    window.alert(
      intent === "document"
        ? "Please choose a supported document file."
        : intent === "camera"
          ? "Please capture or choose a photo."
          : "Please choose a photo or video file.",
    );
    return;
  }

  isSendingAttachment = true;
  setComposeBusy(true);
  closeAttachMenu();

  try {
    const result = await sendMediaMessage({
      conversationId: thread.conversationId,
      staffId: loggedInStaffId,
      patientId: thread.patientId,
      file,
      messageType,
      replyToMessageId: replyTarget?.messageId || "",
      replyPreview: replyTarget?.preview || "",
    });
    thread.preview = result.preview;
    thread.time = result.time;
    thread.unread = false;
    const optimisticItem = buildOptimisticOutgoingItem({
      messageType: result.messageType,
      content: result.content,
      staffId: loggedInStaffId,
      messageId: result.messageId,
      replyPreview: replyTarget?.preview || "",
    });
    thread.messages = [...(thread.messages || []), optimisticItem];
    clearReplyTarget();
    renderThreadList();
    renderMessages(thread, { scrollToBottom: true });
  } catch (error) {
    window.alert(error?.message || "Could not send attachment.");
  } finally {
    isSendingAttachment = false;
    setComposeBusy(false);
    composeInputEl.focus();
  }
}

function setActiveHeader(thread) {
  if (!thread) {
    activeAvatarEl.textContent = "—";
    activeAvatarEl.className = "chat-avatar chat-avatar--lg chat-avatar--teal";
    activeNameEl.textContent = "No active chats";
    return;
  }

  const initials = getInitials(thread.name);
  activeAvatarEl.textContent = initials;
  activeAvatarEl.className = `chat-avatar chat-avatar--lg chat-avatar--${thread.avatarColor}`;
  activeNameEl.textContent = thread.name;
}

function stopMessagesRealtime() {
  releaseFirestoreListener(unsubscribeMessages);
  unsubscribeMessages = null;
}

function selectThread(threadId) {
  const thread = getThreadById(threadId);
  if (!thread) return;

  selectionMode = false;
  selectedMessageIds = new Set();
  replyTarget = null;
  closeConversationSearch({ rerender: false });
  closeConversationCalendarModal();
  closeAllMessageMenus();
  activeThreadId = threadId;
  thread.unread = false;
  setActiveHeader(thread);
  renderThreadList();

  stopMessagesRealtime();
  isLoadingMessages = true;
  renderMessages(thread, { scrollToBottom: true });

  unsubscribeMessages = subscribeMessagesForConversation(
    thread.conversationId,
    loggedInStaffId,
    (items) => {
      thread.messages = items;
      isLoadingMessages = false;
      renderMessages(thread);
    },
    (error) => {
      thread.messages = [];
      isLoadingMessages = false;
      messagesEl.innerHTML = `<p class="communication-messages-empty">${escapeHtml(
        error?.message || "Could not load messages.",
      )}</p>`;
    },
  );
}

function applyChatThreads(threads) {
  const previousMessages = activeThreadId
    ? getThreadById(activeThreadId)?.messages
    : null;
  const preservedForcedThread = forcedActiveThreadId
    ? chatThreads.find((thread) => thread.id === forcedActiveThreadId)
    : null;

  if (isAdmin(loggedInStaffProfile?.role)) {
    threads = threads.filter(t => t.id !== "sys_ag_virtual");
  }

  chatThreads = threads;

  if (
    forcedActiveThreadId &&
    preservedForcedThread &&
    !chatThreads.some((thread) => thread.id === forcedActiveThreadId)
  ) {
    chatThreads = [preservedForcedThread, ...chatThreads];
  }

  if (forcedActiveThreadId) {
    const forcedThread = chatThreads.find((thread) => thread.id === forcedActiveThreadId);
    if (forcedThread) {
      if (activeThreadId !== forcedActiveThreadId || !unsubscribeMessages) {
        selectThread(forcedActiveThreadId);
      } else {
        if (previousMessages) forcedThread.messages = previousMessages;
        setActiveHeader(forcedThread);
        renderThreadList();
        renderMessages(forcedThread, { preserveScroll: true });
      }
      return;
    }
  }

  if (trySelectPendingPatientFromThreads()) {
    return;
  }

  if (chatThreads.length === 0) {
    if (shouldDeferEmptyConversationState()) {
      renderThreadList();
      return;
    }
    activeThreadId = null;
    stopMessagesRealtime();
    setActiveHeader(null);
    renderThreadList();
    renderMessages(null);
    return;
  }

  const stillExists = activeThreadId
    ? chatThreads.some((thread) => thread.id === activeThreadId)
    : false;
  if (!activeThreadId || !stillExists) {
    if (shouldDeferEmptyConversationState()) {
      renderThreadList();
      return;
    }
    activeThreadId = null;
    stopMessagesRealtime();
    setActiveHeader(null);
    renderThreadList();
    renderMessages(null);
    return;
  }

  const thread = getThreadById(activeThreadId);
  if (thread) {
    if (previousMessages) thread.messages = previousMessages;
    setActiveHeader(thread);
    renderThreadList();
    if (!unsubscribeMessages) {
      selectThread(activeThreadId);
    } else {
      renderMessages(thread, { preserveScroll: true });
    }
  }
}

function startConversationsRealtime() {
  releaseFirestoreListener(unsubscribeConversations);
  stopMessagesRealtime();

  if (!loggedInStaffId) {
    threadListEl.innerHTML =
      '<li class="communication-thread-empty">Staff ID is required to load conversations.</li>';
    setActiveHeader(null);
    renderMessages(null);
    return;
  }

  isLoadingThreads = true;
  renderThreadList();

  unsubscribeConversations = subscribeAvailableConversationsForStaff(
    loggedInStaffId,
    (threads) => {
      isLoadingThreads = false;
      applyChatThreads(threads);
      renderThreadList();
      void tryOpenPendingPatientConversation();
    },
    (error) => {
      isLoadingThreads = false;
      chatThreads = [];
      activeThreadId = null;
      stopMessagesRealtime();
      threadListEl.innerHTML = `<li class="communication-thread-empty">${escapeHtml(
        error?.message || "Could not load conversations.",
      )}</li>`;
      setActiveHeader(null);
      renderMessages(null);
    },
  );
}

async function handleComposeSubmit(event) {
  event.preventDefault();
  const text = composeInputEl.value.trim();
  if (!text || !activeThreadId) return;

  const thread = getThreadById(activeThreadId);
  if (!thread?.patientId) return;

  setComposeBusy(true);

  try {
    await sendTextMessage({
      conversationId: thread.conversationId,
      staffId: loggedInStaffId,
      patientId: thread.patientId,
      content: text,
      replyToMessageId: replyTarget?.messageId || "",
      replyPreview: replyTarget?.preview || "",
    });

    composeInputEl.value = "";
    clearReplyTarget();
    thread.preview = text;
    thread.time = new Date().toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
    });
    thread.unread = false;

    renderThreadList();
    renderMessages(thread, { scrollToBottom: true });
  } catch (error) {
    window.alert(error?.message || "Could not send message.");
  } finally {
    setComposeBusy(false);
    composeInputEl.focus();
  }
}

threadListEl.addEventListener("click", (event) => {
  const btn = event.target.closest("[data-thread-id]");
  if (!btn) return;
  selectThread(btn.dataset.threadId);
});

searchEl.addEventListener("input", () => {
  searchQuery = searchEl.value.trim();
  renderThreadList();
});

conversationSearchBtnEl?.addEventListener("click", () => {
  if (conversationSearchOpen) {
    closeConversationSearch();
    return;
  }
  openConversationSearch();
});

conversationSearchCloseBtn?.addEventListener("click", () => {
  closeConversationSearch();
});

conversationSearchInputEl?.addEventListener("input", () => {
  conversationSearchQuery = conversationSearchInputEl.value.trim();
  const thread = getThreadById(activeThreadId);
  if (thread) renderMessages(thread, { preserveScroll: true });
  requestAnimationFrame(() => scrollToFirstSearchHighlight());
});

conversationSearchInputEl?.addEventListener("keydown", (event) => {
  if (event.key === "Escape") {
    event.preventDefault();
    closeConversationSearch();
  }
});

calendarBtnEl?.addEventListener("click", () => {
  if (!calendarModalEl?.hidden) {
    closeConversationCalendarModal();
    return;
  }
  openConversationCalendarModal();
});

calendarCloseBtn?.addEventListener("click", closeConversationCalendarModal);
calendarModalEl?.addEventListener("click", (event) => {
  if (event.target === calendarModalEl) closeConversationCalendarModal();
});
calendarPrevBtn?.addEventListener("click", () => {
  if (calendarPrevBtn.disabled) return;
  const nextMonth = calendarViewMonth - 1;
  if (nextMonth < 0) {
    setCalendarViewMonth(calendarViewYear - 1, 11);
  } else {
    setCalendarViewMonth(calendarViewYear, nextMonth);
  }
});
calendarNextBtn?.addEventListener("click", () => {
  if (calendarNextBtn.disabled) return;
  const nextMonth = calendarViewMonth + 1;
  if (nextMonth > 11) {
    setCalendarViewMonth(calendarViewYear + 1, 0);
  } else {
    setCalendarViewMonth(calendarViewYear, nextMonth);
  }
});
calendarGridEl?.addEventListener("click", (event) => {
  const dayBtn = event.target.closest("[data-calendar-date]");
  if (!dayBtn || dayBtn.disabled) return;
  handleCalendarDateSelect(dayBtn.dataset.calendarDate);
});

filterBtns.forEach((btn) => {
  btn.addEventListener("click", () => {
    filterBtns.forEach((b) => b.classList.remove("is-active"));
    btn.classList.add("is-active");
    chatFilter = btn.dataset.filter;
    renderThreadList();
  });
});

composeFormEl.addEventListener("submit", handleComposeSubmit);
attachBtnEl.addEventListener("click", (event) => {
  event.stopPropagation();
  if (!activeThreadId || isSendingAttachment) return;
  toggleAttachMenu();
});
attachMenuEl.addEventListener("click", (event) => {
  const item = event.target.closest("[data-attach-kind]");
  if (!item) return;
  const kind = item.dataset.attachKind;
  if (kind === "document") {
    openAttachmentPicker(attachDocumentInputEl);
  } else if (kind === "media") {
    openAttachmentPicker(attachMediaInputEl);
  } else if (kind === "camera") {
    void openCameraCapture();
  }
});
attachDocumentInputEl.addEventListener("change", () => {
  const file = attachDocumentInputEl.files?.[0] || null;
  attachDocumentInputEl.value = "";
  void handleAttachmentFileSelected(file, "document");
});
attachMediaInputEl.addEventListener("change", () => {
  const file = attachMediaInputEl.files?.[0] || null;
  attachMediaInputEl.value = "";
  void handleAttachmentFileSelected(file, "media");
});
cameraCloseBtn.addEventListener("click", closeCameraCapture);
cameraCancelBtn.addEventListener("click", closeCameraCapture);
cameraCaptureBtn.addEventListener("click", () => {
  void captureCameraPhoto();
});
cameraRetakeBtn.addEventListener("click", () => {
  void retakeCameraPhoto();
});
cameraSendBtn.addEventListener("click", () => {
  cameraSendBtn.disabled = true;
  void sendCameraPhoto();
});
cameraModalEl.addEventListener("click", (event) => {
  if (event.target === cameraModalEl) closeCameraCapture();
});
messagesEl.addEventListener("scroll", () => {
  updateScrollToBottomButton();
}, { passive: true });

scrollBottomBtnEl?.addEventListener("click", () => {
  scrollMessagesToBottom({ smooth: true });
  requestAnimationFrame(() => updateScrollToBottomButton());
});

messagesEl.addEventListener("click", (event) => {
  const actionBtn = event.target.closest("[data-message-action]");
  if (actionBtn) {
    event.preventDefault();
    void handleMessageAction(actionBtn.dataset.messageAction, actionBtn.dataset.messageId);
    return;
  }

  const menuBtn = event.target.closest("[data-message-menu]");
  if (menuBtn) {
    event.preventDefault();
    event.stopPropagation();
    toggleMessageMenu(menuBtn.dataset.messageMenu);
    return;
  }

  const selectInput = event.target.closest("[data-message-select]");
  if (selectInput && selectionMode) {
    event.stopPropagation();
    toggleMessageSelection(selectInput.dataset.messageSelect);
    return;
  }

  const row = event.target.closest("[data-message-row]");
  if (row && selectionMode && !event.target.closest("[data-message-menu]")) {
    toggleMessageSelection(row.dataset.messageRow);
    return;
  }

  const previewBtn = event.target.closest("[data-chat-photo-preview]");
  if (!previewBtn || selectionMode) return;
  const img = previewBtn.querySelector(".chat-bubble-image");
  if (!img?.src) return;
  openPhotoPreview(img.src, img.alt || "Photo");
});
photoPreviewCloseBtn.addEventListener("click", closePhotoPreview);
photoPreviewModalEl.addEventListener("click", (event) => {
  if (event.target === photoPreviewModalEl) closePhotoPreview();
});
replyCancelBtn.addEventListener("click", clearReplyTarget);
selectionCopyBtn.addEventListener("click", () => {
  void copySelectedMessages();
});
selectionForwardBtn.addEventListener("click", () => {
  void openForwardModal([...selectedMessageIds]);
});
selectionDeleteBtn.addEventListener("click", () => {
  openDeleteModal([...selectedMessageIds]);
});
selectionCancelBtn.addEventListener("click", exitSelectionMode);
messageInfoCloseBtn.addEventListener("click", closeMessageInfoModal);
messageInfoModalEl.addEventListener("click", (event) => {
  if (event.target === messageInfoModalEl) closeMessageInfoModal();
});
forwardMessageCloseBtn.addEventListener("click", closeForwardModal);
forwardMessageModalEl.addEventListener("click", (event) => {
  if (event.target === forwardMessageModalEl) closeForwardModal();
});
forwardMessageListEl.addEventListener("change", (event) => {
  const checkbox = event.target.closest('input[type="checkbox"]');
  if (!checkbox) return;
  const patientId = checkbox.value;
  if (checkbox.checked) selectedForwardPatientIds.add(patientId);
  else selectedForwardPatientIds.delete(patientId);
  forwardMessageSubmitBtn.disabled = selectedForwardPatientIds.size === 0;
  const item = checkbox.closest(".message-forward-item");
  if (item) item.classList.toggle("is-selected", checkbox.checked);
});
forwardMessageSubmitBtn.addEventListener("click", () => {
  void handleForwardSubmit();
});
deleteMessageCloseBtn.addEventListener("click", closeDeleteModal);
deleteMessageModalEl.addEventListener("click", (event) => {
  if (event.target === deleteMessageModalEl) closeDeleteModal();
});
deleteMessageForMeBtn.addEventListener("click", () => {
  void handleDeleteForMe();
});
deleteMessageForEveryoneBtn.addEventListener("click", () => {
  void handleDeleteForEveryone();
});
document.addEventListener("click", (event) => {
  if (openMessageMenuId) {
    const insideMenu = event.target.closest(
      `[data-message-menu-panel="${openMessageMenuId}"], [data-message-menu="${openMessageMenuId}"]`,
    );
    if (!insideMenu) closeAllMessageMenus();
  }
  if (attachMenuEl.hidden) return;
  if (
    event.target === attachBtnEl ||
    attachBtnEl.contains(event.target) ||
    attachMenuEl.contains(event.target)
  ) {
    return;
  }
  closeAttachMenu();
});
addContactCloseBtn.addEventListener("click", closeAddContactModal);
addContactFormEl.addEventListener("submit", handleAddContactSubmit);
addContactSidebarBtn?.addEventListener("click", openAddContactModal);
addContactPatientListEl.addEventListener("click", (event) => {
  const item = event.target.closest(".add-contact-patient-item");
  if (!item?.dataset.patientId) return;
  if (item.dataset.disabled === "true") return;

  selectedAddContactPatientId = item.dataset.patientId;

  addContactPatientListEl
    .querySelectorAll(".add-contact-patient-item")
    .forEach((btn) => {
      const isSelected = btn === item;
      btn.classList.toggle("is-selected", isSelected);
      btn.setAttribute("aria-selected", isSelected ? "true" : "false");
    });

  createConversationFromSelectedPatient(selectedAddContactPatientId);
});
addContactModalEl.addEventListener("click", (event) => {
  if (event.target === addContactModalEl) closeAddContactModal();
});

document.addEventListener("keydown", (event) => {
  if (event.key !== "Escape") return;
  if (!attachMenuEl.hidden) {
    closeAttachMenu();
    return;
  }
  if (!cameraModalEl.hidden) {
    closeCameraCapture();
    return;
  }
  if (!photoPreviewModalEl.hidden) {
    closePhotoPreview();
    return;
  }
  if (!messageInfoModalEl.hidden) {
    closeMessageInfoModal();
    return;
  }
  if (!forwardMessageModalEl.hidden) {
    closeForwardModal();
    return;
  }
  if (!deleteMessageModalEl.hidden) {
    closeDeleteModal();
    return;
  }
  if (calendarModalEl && !calendarModalEl.hidden) {
    closeConversationCalendarModal();
    return;
  }
  if (callModalEl && !callModalEl.hidden) {
    closeCallModal();
    return;
  }
  if (incomingCallModalEl && !incomingCallModalEl.hidden) {
    void declineIncomingCall();
    return;
  }
  if (selectionMode) {
    exitSelectionMode();
    return;
  }
  if (!addContactModalEl.hidden) {
    closeAddContactModal();
  }
});

document.getElementById("btn-chat-call")?.addEventListener("click", () => {
  openCallModal();
});

callCloseBtn?.addEventListener("click", closeCallModal);
callCancelBtn?.addEventListener("click", closeCallModal);
callModalEl?.addEventListener("click", (event) => {
  if (event.target === callModalEl) closeCallModal();
});
callStartBtn?.addEventListener("click", () => {
  void startVoiceCall();
});
voiceCallEndBtn?.addEventListener("click", () => {
  void endActiveVoiceCall();
});
voiceCallMuteBtn?.addEventListener("click", toggleVoiceCallMute);
incomingCallAcceptBtn?.addEventListener("click", () => {
  void acceptIncomingCall();
});
incomingCallDeclineBtn?.addEventListener("click", () => {
  void declineIncomingCall();
});
incomingCallModalEl?.addEventListener("click", (event) => {
  if (event.target === incomingCallModalEl) {
    void declineIncomingCall();
  }
});

document.getElementById("btn-chat-video")?.addEventListener("click", () => {
  const thread = getThreadById(activeThreadId);
  if (thread) {
    window.alert(`Video call ${thread.name} — video calls will be available in a future update.`);
  }
});

let loggedInStaffProfile = null;

initStaffAuth(async (profile) => {
  loggedInStaffProfile = profile;
  loggedInStaffId =
    profile?.staffID?.trim() || profile?.staffId?.trim() || getStaffSession()?.staffID?.trim() || getStaffSession()?.staffId?.trim() || "";
  startConversationsRealtime();
  startIncomingCallWatcher();
  if (pendingOpenPatientId) {
    await resolveAndOpenPendingPatient();
  }
});
