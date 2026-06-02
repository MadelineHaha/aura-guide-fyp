import { initStaffAuth, getInitials } from "./staff-shell.js";
import { getStaffSession } from "./staff-auth.js";
import {
  createConversationForStaffPatient,
  fetchAvailablePatientsForNewConversation,
  fetchAvailableConversationsForStaff,
  fetchMessagesForConversation,
  sendTextMessage,
} from "./communication-service.js";

let chatThreads = [];
let activeThreadId = null;
let chatFilter = "all";
let searchQuery = "";
let loggedInStaffId = "";
let isLoadingThreads = false;
let isLoadingMessages = false;

const threadListEl = document.getElementById("chat-thread-list");
const messagesEl = document.getElementById("chat-messages");
const panelHeaderEl = document.querySelector(".communication-panel-header");
const activeNameEl = document.getElementById("active-chat-name");
const activeAvatarEl = document.getElementById("active-chat-avatar");
const searchEl = document.getElementById("chat-search");
const composeFormEl = document.getElementById("chat-compose-form");
const composeInputEl = document.getElementById("chat-compose-input");
const filterBtns = document.querySelectorAll(".communication-filter");
const addContactSidebarBtn = document.getElementById("btn-add-contact-sidebar");
const addContactModalEl = document.getElementById("add-contact-modal");
const addContactFormEl = document.getElementById("add-contact-form");
const addContactCloseBtn = document.getElementById("add-contact-close");
const addContactPatientListEl = document.getElementById("add-contact-patient-list");
const addContactErrorEl = document.getElementById("add-contact-error");
const addContactSubmitBtn = document.getElementById("add-contact-submit");
let selectedAddContactPatientId = "";
let isCreatingContact = false;

function syncConversationPanelVisibility(thread) {
  const hasActiveThread = Boolean(thread);
  panelHeaderEl.hidden = !hasActiveThread;
  composeFormEl.hidden = !hasActiveThread;
}

function syncBodyModalLock() {
  document.body.classList.toggle("modal-open", !addContactModalEl.hidden);
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
    const patients = await fetchAvailablePatientsForNewConversation(loggedInStaffId);
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
    await loadConversations();
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

function getThreadById(id) {
  return chatThreads.find((thread) => thread.id === id);
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

function renderMessages(thread) {
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
  if (items.length === 0) {
    messagesEl.innerHTML =
      '<p class="communication-messages-empty">No messages in this conversation yet.</p>';
    return;
  }

  messagesEl.innerHTML = items
    .map((item) => {
      if (item.type === "divider") {
        return `<p class="chat-divider" role="separator">${escapeHtml(item.label)}</p>`;
      }
      const bubbleClass =
        item.type === "out" ? "chat-bubble chat-bubble--out" : "chat-bubble chat-bubble--in";
      const rowClass =
        item.type === "out"
          ? "chat-message-row chat-message-row--out"
          : "chat-message-row chat-message-row--in";
      return `
        <div class="${rowClass}">
          <div class="${bubbleClass}">
            <p class="chat-bubble-text">${escapeHtml(item.text)}</p>
            <span class="chat-bubble-time">${escapeHtml(item.time)}</span>
          </div>
        </div>
      `;
    })
    .join("");

  messagesEl.scrollTop = messagesEl.scrollHeight;
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

async function selectThread(threadId) {
  const thread = getThreadById(threadId);
  if (!thread) return;

  activeThreadId = threadId;
  thread.unread = false;
  setActiveHeader(thread);
  renderThreadList();

  isLoadingMessages = true;
  renderMessages(thread);

  try {
    thread.messages = await fetchMessagesForConversation(
      thread.conversationId,
      loggedInStaffId,
    );
  } catch (error) {
    thread.messages = [];
    messagesEl.innerHTML = `<p class="communication-messages-empty">${escapeHtml(
      error?.message || "Could not load messages.",
    )}</p>`;
    return;
  } finally {
    isLoadingMessages = false;
  }

  renderMessages(thread);
}

async function loadConversations() {
  if (!loggedInStaffId) {
    threadListEl.innerHTML =
      '<li class="communication-thread-empty">Staff ID is required to load conversations.</li>';
    setActiveHeader(null);
    renderMessages(null);
    return;
  }

  isLoadingThreads = true;
  renderThreadList();

  try {
    chatThreads = await fetchAvailableConversationsForStaff(loggedInStaffId);

    if (chatThreads.length === 0) {
      activeThreadId = null;
      setActiveHeader(null);
      renderThreadList();
      renderMessages(null);
      return;
    }
    const stillExists = chatThreads.some((thread) => thread.id === activeThreadId);
    if (!stillExists) {
      activeThreadId = null;
      setActiveHeader(null);
      renderThreadList();
      renderMessages(null);
      return;
    }

    await selectThread(activeThreadId);
  } catch (error) {
    chatThreads = [];
    activeThreadId = null;
    threadListEl.innerHTML = `<li class="communication-thread-empty">${escapeHtml(
      error?.message || "Could not load conversations.",
    )}</li>`;
    setActiveHeader(null);
    renderMessages(null);
  } finally {
    isLoadingThreads = false;
    renderThreadList();
  }
}

async function handleComposeSubmit(event) {
  event.preventDefault();
  const text = composeInputEl.value.trim();
  if (!text || !activeThreadId) return;

  const thread = getThreadById(activeThreadId);
  if (!thread?.patientId) return;

  composeInputEl.disabled = true;

  try {
    await sendTextMessage({
      conversationId: thread.conversationId,
      staffId: loggedInStaffId,
      patientId: thread.patientId,
      content: text,
    });

    composeInputEl.value = "";
    thread.preview = text;
    thread.time = new Date().toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit",
      hour12: true,
    });
    thread.unread = false;

    thread.messages = await fetchMessagesForConversation(
      thread.conversationId,
      loggedInStaffId,
    );

    renderThreadList();
    renderMessages(thread);
  } catch (error) {
    window.alert(error?.message || "Could not send message.");
  } finally {
    composeInputEl.disabled = false;
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

filterBtns.forEach((btn) => {
  btn.addEventListener("click", () => {
    filterBtns.forEach((b) => b.classList.remove("is-active"));
    btn.classList.add("is-active");
    chatFilter = btn.dataset.filter;
    renderThreadList();
  });
});

composeFormEl.addEventListener("submit", handleComposeSubmit);
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
  if (event.key === "Escape" && !addContactModalEl.hidden) {
    closeAddContactModal();
  }
});

document.getElementById("btn-chat-call")?.addEventListener("click", () => {
  const thread = getThreadById(activeThreadId);
  if (thread) {
    window.alert(`Call ${thread.name} — voice calls will be available in a future update.`);
  }
});

initStaffAuth((profile) => {
  loggedInStaffId =
    profile?.staffID?.trim() || getStaffSession()?.staffID?.trim() || "";
  loadConversations();
});
