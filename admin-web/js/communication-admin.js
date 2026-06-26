import { initStaffAuth } from "./staff-shell.js";
import { isAdmin } from "./staff-rbac.js";
import {
  ANNOUNCEMENT_TYPES,
  createAnnouncement,
  updateAnnouncement,
  deleteAnnouncement,
  subscribeAnnouncements,
} from "./announcements-service.js";
import { releaseFirestoreListener } from "./firestore-realtime.js";

const panelEl = document.getElementById("admin-broadcast-panel");
const listEl = document.getElementById("announcements-list");
const emptyEl = document.getElementById("announcements-empty");
const formEl = document.getElementById("announcement-form");
const typeEl = document.getElementById("announcement-type");
const titleEl = document.getElementById("announcement-title");
const messageEl = document.getElementById("announcement-message");
const errorEl = document.getElementById("announcement-error");

let unsubscribe = null;
let staffName = "Admin";
let editingAnnouncementId = null;

function escapeHtml(value) {
  return String(value || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

const paginationEl = document.getElementById("announcements-pagination");

let allAnnouncements = [];
let currentPage = 1;
const ITEMS_PER_PAGE = 5;
let selectedMonthFilter = "all";

const filterEl = document.getElementById("announcements-month-filter");
if (filterEl) {
  filterEl.addEventListener("change", (e) => {
    selectedMonthFilter = e.target.value;
    currentPage = 1;
    renderAnnouncements();
  });
}

function renderAnnouncements() {
  if (!listEl || !emptyEl) return;
  if (!allAnnouncements.length) {
    listEl.innerHTML = "";
    emptyEl.hidden = false;
    if (paginationEl) paginationEl.hidden = true;
    return;
  }

  // Populate month filter dropdown if needed
  if (filterEl) {
    const uniqueMonths = new Set();
    allAnnouncements.forEach(item => {
      if (item.timestamp) {
        const d = item.timestamp.toDate ? item.timestamp.toDate() : new Date(item.timestamp);
        uniqueMonths.add(d.toLocaleDateString("en-GB", { month: "short", year: "numeric" }));
      }
    });
    
    // Check if we need to rebuild options (only if count changes to avoid resetting selection)
    if (filterEl.options.length !== uniqueMonths.size + 1) {
      const currentVal = filterEl.value;
      filterEl.innerHTML = '<option value="all">All Months</option>';
      Array.from(uniqueMonths).sort((a, b) => new Date("1 " + a) - new Date("1 " + b)).forEach(month => {
        filterEl.innerHTML += `<option value="${escapeHtml(month)}">${escapeHtml(month)}</option>`;
      });
      if (Array.from(uniqueMonths).includes(currentVal)) {
        filterEl.value = currentVal;
      }
    }
  }

  emptyEl.hidden = true;
  if (paginationEl) paginationEl.hidden = false;

  // Sort chronologically (oldest first) as requested
  const sorted = [...allAnnouncements].reverse();
  
  // Apply month filter
  const filtered = selectedMonthFilter === "all" ? sorted : sorted.filter(item => {
    if (!item.timestamp) return false;
    const d = item.timestamp.toDate ? item.timestamp.toDate() : new Date(item.timestamp);
    const m = d.toLocaleDateString("en-GB", { month: "short", year: "numeric" });
    return m === selectedMonthFilter;
  });

  if (filtered.length === 0) {
    listEl.innerHTML = "";
    emptyEl.hidden = false;
    if (paginationEl) paginationEl.hidden = true;
    return;
  }

  const totalPages = Math.ceil(filtered.length / ITEMS_PER_PAGE);
  if (currentPage > totalPages) currentPage = totalPages;
  if (currentPage < 1) currentPage = 1;

  const startIndex = (currentPage - 1) * ITEMS_PER_PAGE;
  const pageItems = filtered.slice(startIndex, startIndex + ITEMS_PER_PAGE);

  let html = "";
  let lastMonthYear = "";

  pageItems.forEach((item) => {
    let monthYear = "";
    if (item.timestamp) {
      const d = item.timestamp.toDate ? item.timestamp.toDate() : new Date(item.timestamp);
      monthYear = d.toLocaleDateString("en-GB", { month: "short", year: "numeric" });
    }

    if (monthYear && monthYear !== lastMonthYear) {
      html += `<h2 class="announcement-month-divider">${escapeHtml(monthYear)}</h2>`;
      lastMonthYear = monthYear;
    }

    html += `
      <article class="announcement-card" data-id="${escapeHtml(item.id)}">
        <header class="announcement-card-header">
          <span class="announcement-type">${escapeHtml(item.type)}</span>
          <div style="display: flex; gap: 8px; align-items: center;">
            <time class="announcement-time">${escapeHtml(item.createdAtLabel)}</time>
            <button type="button" class="btn-text" data-action="edit" style="font-size: 0.75rem; color: #007bff; background: none; border: none; cursor: pointer;">Edit</button>
            <button type="button" class="btn-text" data-action="delete" style="font-size: 0.75rem; color: #dc3545; background: none; border: none; cursor: pointer;">Delete</button>
          </div>
        </header>
        <h3 class="announcement-title">${escapeHtml(item.title)}</h3>
        <p class="announcement-message" style="white-space: pre-wrap;">${escapeHtml(item.message)}</p>
        <footer class="announcement-footer">Posted by ${escapeHtml(item.createdBy)}</footer>
      </article>`;
  });

  listEl.innerHTML = html;

  if (paginationEl) {
    const prevBtn = document.getElementById("announcements-prev");
    const nextBtn = document.getElementById("announcements-next");
    const labelEl = document.getElementById("announcements-page-label");
    
    if (labelEl) labelEl.textContent = `Page ${currentPage} of ${totalPages}`;
    if (prevBtn) prevBtn.disabled = currentPage === 1;
    if (nextBtn) nextBtn.disabled = currentPage === totalPages;
  }
}

if (listEl) {
  listEl.addEventListener("click", async (e) => {
    const btn = e.target.closest("button[data-action]");
    if (!btn) return;
    
    const card = btn.closest(".announcement-card");
    const id = card.dataset.id;
    const item = allAnnouncements.find(a => a.id === id);
    if (!item) return;

    if (btn.dataset.action === "edit") {
      editingAnnouncementId = id;
      
      const editModal = document.getElementById("edit-announcement-modal");
      const editTypeEl = document.getElementById("edit-announcement-type");
      const editTitleEl = document.getElementById("edit-announcement-title-input");
      const editMessageEl = document.getElementById("edit-announcement-message");

      if (editTypeEl) editTypeEl.value = item.type;
      if (editTitleEl) editTitleEl.value = item.title;
      if (editMessageEl) editMessageEl.value = item.message;
      
      if (editModal) editModal.hidden = false;
    } else if (btn.dataset.action === "delete") {
      if (confirm("Are you sure you want to delete this broadcast message?")) {
        try {
          await deleteAnnouncement(id);
        } catch (error) {
          alert("Failed to delete: " + error.message);
        }
      }
    }
  });
}

if (paginationEl) {
  paginationEl.addEventListener("click", (e) => {
    if (e.target.id === "announcements-prev") {
      currentPage--;
      renderAnnouncements();
    } else if (e.target.id === "announcements-next") {
      currentPage++;
      renderAnnouncements();
    }
  });
}

async function handleSubmit(event) {
  event.preventDefault();
  errorEl.hidden = true;
  const type = typeEl.value;
  const title = titleEl.value.trim();
  const message = messageEl.value.trim();
  if (!title || !message) {
    errorEl.textContent = "Title and message are required.";
    errorEl.hidden = false;
    return;
  }
  try {
    await createAnnouncement({ type, title, message, createdByName: staffName });
    formEl.reset();
    typeEl.value = ANNOUNCEMENT_TYPES[0];
  } catch (error) {
    errorEl.textContent = error?.message || "Could not save announcement.";
    errorEl.hidden = false;
  }
}

initStaffAuth((profile) => {
  if (!isAdmin(profile?.role)) {
    if (panelEl) panelEl.hidden = true;
    return;
  }
  staffName = profile.name || "Admin";
  if (panelEl) panelEl.hidden = false;
  
  const typeOptionsHTML = ANNOUNCEMENT_TYPES.map(
    (type) => `<option value="${type}">${type}</option>`
  ).join("");

  if (typeEl) {
    typeEl.innerHTML = typeOptionsHTML;
  }
  
  const editTypeEl = document.getElementById("edit-announcement-type");
  if (editTypeEl) {
    editTypeEl.innerHTML = typeOptionsHTML;
  }

  formEl?.addEventListener("submit", handleSubmit);
  
  const editForm = document.getElementById("edit-announcement-form");
  const editModal = document.getElementById("edit-announcement-modal");
  const editCloseBtn = document.getElementById("edit-announcement-close");
  const editTitleEl = document.getElementById("edit-announcement-title-input");
  const editMessageEl = document.getElementById("edit-announcement-message");
  const editErrorEl = document.getElementById("edit-announcement-error");

  if (editCloseBtn && editModal) {
    editCloseBtn.addEventListener("click", () => {
      editModal.hidden = true;
      editingAnnouncementId = null;
    });
  }

  if (editForm) {
    editForm.addEventListener("submit", async (e) => {
      e.preventDefault();
      if (editErrorEl) editErrorEl.hidden = true;
      
      const type = editTypeEl ? editTypeEl.value : "";
      const title = editTitleEl ? editTitleEl.value.trim() : "";
      const message = editMessageEl ? editMessageEl.value.trim() : "";
      
      if (!title || !message) {
        if (editErrorEl) {
          editErrorEl.textContent = "Title and message are required.";
          editErrorEl.hidden = false;
        }
        return;
      }
      
      try {
        if (editingAnnouncementId) {
          const submitBtn = editForm.querySelector("button[type='submit']");
          const originalText = submitBtn ? submitBtn.textContent : "";
          if (submitBtn) submitBtn.textContent = "Updating...";
          
          await updateAnnouncement(editingAnnouncementId, { type, title, message });
          
          if (submitBtn) submitBtn.textContent = originalText;
          editingAnnouncementId = null;
          if (editModal) editModal.hidden = true;
        }
      } catch (error) {
        if (editErrorEl) {
          editErrorEl.textContent = error?.message || "Could not update announcement.";
          editErrorEl.hidden = false;
        }
      }
    });
  }

  unsubscribe = subscribeAnnouncements((items) => {
    allAnnouncements = items;
    renderAnnouncements();
  }, (error) => {
    console.error("Announcements listener failed:", error);
  });
});

window.addEventListener("beforeunload", () => {
  releaseFirestoreListener(unsubscribe);
});
