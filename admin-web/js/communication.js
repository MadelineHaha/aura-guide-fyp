import { initStaffAuth, getInitials } from "./staff-shell.js";
import { getStaffSession } from "./staff-auth.js";
import {
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
const activeNameEl = document.getElementById("active-chat-name");
const activeAvatarEl = document.getElementById("active-chat-avatar");
const searchEl = document.getElementById("chat-search");
const composeFormEl = document.getElementById("chat-compose-form");
const composeInputEl = document.getElementById("chat-compose-input");
const filterBtns = document.querySelectorAll(".communication-filter");

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
    threadListEl.innerHTML =
      '<li class="communication-thread-empty">Loading conversations…</li>';
    return;
  }

  const threads = filterThreads();
  if (threads.length === 0) {
    threadListEl.innerHTML =
      '<li class="communication-thread-empty">No active conversations yet.</li>';
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
  if (!thread) {
    messagesEl.innerHTML =
      '<p class="communication-messages-empty">No active conversations to display.</p>';
    return;
  }

  if (isLoadingMessages) {
    messagesEl.innerHTML =
      '<p class="communication-messages-empty">Loading messages…</p>';
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
      activeThreadId = chatThreads[0].id;
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
