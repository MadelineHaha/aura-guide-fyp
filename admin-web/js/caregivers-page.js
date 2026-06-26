import { initStaffAuth } from "./staff-shell.js";
import { isAdmin } from "./staff-rbac.js";
import { subscribePatients } from "./user-patients-service.js";
import {
  createCaregiver,
  deactivateCaregiver,
  subscribeCaregivers,
  updateCaregiver,
  updateCaregiverConnections,
} from "./caregiver-service.js";
import {
  fetchNextCaregiverIdPreview,
  subscribeNextCaregiverIdPreview,
} from "./caregiver-id-service.js";
import { releaseFirestoreListener } from "./firestore-realtime.js";

const PAGE_SIZE = 6;

export function initCaregiversPage() {
  const tbodyEl = document.getElementById("staff-tbody");
  const emptyEl = document.getElementById("staff-empty");
  const countEl = document.getElementById("staff-count");
  const paginationEl = document.getElementById("staff-pagination");
  const searchEl = document.getElementById("staff-search");
  const filterTabs = document.querySelectorAll(".filter-tab");
  const addBtn = document.getElementById("btn-add-staff");
  const modalEl = document.getElementById("staff-form-modal");
  const formEl = document.getElementById("staff-form");
  const modalTitleEl = document.getElementById("staff-form-title");
  const formCloseBtn = document.getElementById("staff-form-close");
  const formErrorEl = document.getElementById("staff-form-error");
  const nextCaregiverIdEl = document.getElementById("staff-form-next-id");
  const nameInput = document.getElementById("staff-form-name");
  const emailInput = document.getElementById("staff-form-email");
  const phoneInput = document.getElementById("staff-form-phone");
  const connectedPatientsListEl = document.getElementById("staff-form-connected-patients-list");
  const addConnectedPatientBtn = document.getElementById("btn-add-connected-patient");

  const profileModalEl = document.getElementById("staff-profile-modal");
  const profileCloseBtn = document.getElementById("staff-profile-close");
  const profileAvatarEl = document.getElementById("staff-profile-avatar");
  const profileNameEl = document.getElementById("staff-profile-name");
  const profileStaffIdEl = document.getElementById("staff-profile-staffid");
  const profileGridEl = document.getElementById("staff-profile-grid");
  const profileEmailEl = document.getElementById("staff-profile-email");
  const profilePhoneEl = document.getElementById("staff-profile-phone");
  const profileEmailInput = document.getElementById("staff-profile-email-input");
  const profilePhoneInput = document.getElementById("staff-profile-phone-input");
  const profileLinkedEl = document.getElementById("staff-profile-linked");
  const profileStatusEl = document.getElementById("staff-profile-status");
  const profileStatusInput = document.getElementById("staff-profile-status-input");
  const profileErrorEl = document.getElementById("staff-profile-error");
  const profileFooterViewEl = document.getElementById("staff-profile-footer-view");
  const profileFooterEditEl = document.getElementById("staff-profile-footer-edit");
  const profileUpdateBtn = document.getElementById("staff-profile-update");
  const profileSaveBtn = document.getElementById("staff-profile-save");
  const profileSaveLabelEl = document.getElementById("staff-profile-save-label");
  const profileCancelBtn = document.getElementById("staff-profile-cancel");
  const profileDeactivateBtn = document.getElementById("staff-profile-deactivate");
  const profileLinkBtn = document.getElementById("staff-profile-link");
  const profileViewFields = profileModalEl?.querySelectorAll(".profile-field-view") || [];
  const profileEditFields = profileModalEl?.querySelectorAll(".profile-field-edit") || [];

  const linkModalEl = document.getElementById("staff-link-modal");
  const linkPatientsListEl = document.getElementById("staff-link-patients-list");
  const addLinkPatientBtn = document.getElementById("btn-link-add-patient");
  const linkCloseBtn = document.getElementById("staff-link-close");
  const linkSaveBtn = document.getElementById("staff-link-save");
  const linkErrorEl = document.getElementById("staff-link-error");
  const linkStaffNameEl = document.getElementById("staff-link-name");

  let caregiverCache = [];
  let patientsCache = [];
  let searchQuery = "";
  let statusFilter = "all";
  let currentPage = 1;
  let isSaving = false;
  let isProfileEditing = false;
  let isSavingProfile = false;
  let activeCaregiverUid = null;
  let linkingUid = null;
  let unsubscribeCaregivers = null;
  let unsubscribePatients = null;
  let unsubscribeCaregiverCounter = null;
  let nextCaregiverIdPreview = "—";

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function getInitials(name) {
    const parts = String(name || "?").trim().split(/\s+/).filter(Boolean);
    if (parts.length === 0) return "?";
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
  }

  function isCaregiverActive(member) {
    return String(member?.status || "").trim().toLowerCase() === "active";
  }

  function normalizedStatus(member) {
    return isCaregiverActive(member) ? "Active" : "Inactive";
  }

  function statusBadgeHtml(status) {
    const active = String(status || "").toLowerCase() === "active";
    const cls = active ? "patient-status patient-status--stable" : "patient-status patient-status--monitoring";
    return `<span class="${cls}">${active ? "Active" : "Inactive"}</span>`;
  }

  function linkedPatientSummary(member) {
    const names = (member.connectedPatients || [])
      .map((entry) => entry.name || entry.userId)
      .filter(Boolean);
    return names.length ? names.join(", ") : "—";
  }

  function linkedPatientCount(member) {
    return (member.connectedUserIds || []).length;
  }

  function getCaregiverByUid(uid) {
    return caregiverCache.find((member) => member.uid === uid) || null;
  }

  function filteredCaregivers() {
    const q = searchQuery.toLowerCase();
    return caregiverCache.filter((member) => {
      const active = isCaregiverActive(member);
      const matchesStatus =
        statusFilter === "all" ||
        (statusFilter === "active" && active) ||
        (statusFilter === "inactive" && !active);

      const haystack = `${member.name} ${member.caregiverId} ${member.email} ${member.phone} ${linkedPatientSummary(member)}`.toLowerCase();
      const matchesSearch = !q || haystack.includes(q);
      return matchesStatus && matchesSearch;
    });
  }

  function setStatusFilter(status) {
    statusFilter = status;
    currentPage = 1;
    filterTabs.forEach((tab) => {
      tab.classList.toggle("is-active", tab.dataset.status === status);
    });
    renderTable();
  }

  function renderPagination(totalPages) {
    if (!paginationEl) return;
    if (totalPages <= 1) {
      paginationEl.innerHTML = "";
      return;
    }
    paginationEl.innerHTML = Array.from({ length: totalPages }, (_, i) => {
      const page = i + 1;
      const active = page === currentPage ? " is-active" : "";
      return `<button type="button" class="page-btn${active}" data-page="${page}">${page}</button>`;
    }).join("");
    paginationEl.querySelectorAll(".page-btn").forEach((btn) => {
      btn.addEventListener("click", () => {
        currentPage = Number(btn.dataset.page);
        renderTable();
      });
    });
  }

  function renderRow(member) {
    return `
      <tr data-uid="${member.uid}">
        <td>${escapeHtml(member.caregiverId || "—")}</td>
        <td><p class="cell-primary">${escapeHtml(member.name)}</p></td>
        <td>${escapeHtml(member.phone || "—")}</td>
        <td>${escapeHtml(member.email || "—")}</td>
        <td>${statusBadgeHtml(member.status)}</td>
        <td>${linkedPatientCount(member)}</td>
        <td>
          <button type="button" class="btn-profile-menu" data-staff-profile="${member.uid}" aria-label="View profile for ${escapeHtml(member.name)}">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <polyline points="6 9 12 15 18 9" />
            </svg>
          </button>
        </td>
      </tr>`;
  }

  function renderTable() {
    const filtered = filteredCaregivers();
    const total = filtered.length;
    const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
    if (currentPage > totalPages) currentPage = totalPages;

    if (countEl) {
      countEl.textContent = `${total} caregiver${total === 1 ? "" : "s"}`;
    }

    if (!tbodyEl) return;
    if (total === 0) {
      tbodyEl.innerHTML = "";
      if (emptyEl) emptyEl.hidden = false;
      renderPagination(0);
      return;
    }

    if (emptyEl) emptyEl.hidden = true;
    const start = (currentPage - 1) * PAGE_SIZE;
    const pageItems = filtered.slice(start, start + PAGE_SIZE);
    tbodyEl.innerHTML = pageItems.map(renderRow).join("");
    renderPagination(totalPages);
  }

  function activePatients() {
    return patientsCache.filter((patient) => patient.accountStatus !== "Inactive");
  }

  function patientSelectMarkup(selectedDocId = "", excludeDocIds = []) {
    const options = ['<option value="">Select patient</option>'];
    for (const patient of activePatients()) {
      if (excludeDocIds.includes(patient.id) && patient.id !== selectedDocId) {
        continue;
      }
      const selected = patient.id === selectedDocId ? " selected" : "";
      options.push(
        `<option value="${escapeHtml(patient.id)}"${selected}>${escapeHtml(patient.name)} (${escapeHtml(patient.patientId)})</option>`,
      );
    }
    return options.join("");
  }

  function updateRemoveButtons(container) {
    const rows = container.querySelectorAll(".connected-patient-row");
    rows.forEach((row) => {
      const removeBtn = row.querySelector(".connected-patient-remove");
      if (removeBtn) removeBtn.hidden = rows.length <= 1;
    });
  }

  function refreshPatientSelectOptions(container) {
    const selects = [...container.querySelectorAll(".connected-patient-select")];
    const selectedValues = selects.map((select) => select.value).filter(Boolean);
    selects.forEach((select, index) => {
      const currentValue = select.value;
      const exclude = selectedValues.filter((_, rowIndex) => rowIndex !== index);
      select.innerHTML = patientSelectMarkup(currentValue, exclude);
    });
    updateRemoveButtons(container);
  }

  function addPatientSelectRow(container, selectedDocId = "") {
    if (!container) return;

    const row = document.createElement("div");
    row.className = "connected-patient-row";
    row.innerHTML = `
      <select class="form-field-input form-field-select connected-patient-select" required>
        ${patientSelectMarkup(selectedDocId)}
      </select>
      <button type="button" class="connected-patient-remove" aria-label="Remove patient">Remove</button>
    `;

    row.querySelector(".connected-patient-select")?.addEventListener("change", () => {
      refreshPatientSelectOptions(container);
    });
    row.querySelector(".connected-patient-remove")?.addEventListener("click", () => {
      row.remove();
      if (container.querySelectorAll(".connected-patient-row").length === 0) {
        addPatientSelectRow(container);
      }
      refreshPatientSelectOptions(container);
    });

    container.appendChild(row);
    refreshPatientSelectOptions(container);
  }

  function resetPatientSelectList(container, selectedDocIds = []) {
    if (!container) return;
    container.innerHTML = "";
    const ids = selectedDocIds.length > 0 ? selectedDocIds : [""];
    ids.forEach((docId) => addPatientSelectRow(container, docId));
  }

  function collectConnectedPatientsFromContainer(container) {
    if (!container) return [];

    const selectedIds = [
      ...new Set(
        [...container.querySelectorAll(".connected-patient-select")]
          .map((select) => select.value)
          .filter(Boolean),
      ),
    ];

    return selectedIds
      .map((docId) => {
        const patient = patientsCache.find((entry) => entry.id === docId);
        if (!patient) return null;
        return {
          patientDocId: patient.id,
          userId: patient.patientId,
          name: patient.name,
        };
      })
      .filter(Boolean);
  }

  function refreshOpenPatientSelectLists() {
    if (modalEl && !modalEl.hidden && connectedPatientsListEl) {
      const selectedIds = collectConnectedPatientsFromContainer(connectedPatientsListEl).map(
        (entry) => entry.patientDocId,
      );
      resetPatientSelectList(connectedPatientsListEl, selectedIds.length ? selectedIds : [""]);
    }
    if (linkModalEl && !linkModalEl.hidden && linkPatientsListEl) {
      const selectedIds = collectConnectedPatientsFromContainer(linkPatientsListEl).map(
        (entry) => entry.patientDocId,
      );
      resetPatientSelectList(linkPatientsListEl, selectedIds.length ? selectedIds : [""]);
    }
  }

  function syncBodyModalLock() {
    const anyOpen =
      (modalEl && !modalEl.hidden) ||
      (profileModalEl && !profileModalEl.hidden) ||
      (linkModalEl && !linkModalEl.hidden);
    document.body.classList.toggle("modal-open", Boolean(anyOpen));
  }

  function renderNextCaregiverIdPreview() {
    if (!nextCaregiverIdEl) return;
    nextCaregiverIdEl.textContent = `New Caregiver ID: ${nextCaregiverIdPreview}`;
  }

  async function refreshNextCaregiverIdPreview() {
    try {
      nextCaregiverIdPreview = await fetchNextCaregiverIdPreview();
    } catch {
      nextCaregiverIdPreview = "—";
    }
    renderNextCaregiverIdPreview();
  }

  function startCaregiverCounterListener() {
    releaseFirestoreListener(unsubscribeCaregiverCounter);
    unsubscribeCaregiverCounter = subscribeNextCaregiverIdPreview(
      (caregiverId) => {
        nextCaregiverIdPreview = caregiverId;
        renderNextCaregiverIdPreview();
      },
      () => {
        nextCaregiverIdPreview = "—";
        renderNextCaregiverIdPreview();
      },
    );
  }

  function openAddModal() {
    formEl.reset();
    formErrorEl.hidden = true;
    modalTitleEl.textContent = "Add Caregiver";
    resetPatientSelectList(connectedPatientsListEl);
    void refreshNextCaregiverIdPreview();
    modalEl.hidden = false;
    syncBodyModalLock();
    nameInput.focus();
  }

  function closeAddModal() {
    modalEl.hidden = true;
    syncBodyModalLock();
  }

  function setProfileEditMode(editing) {
    isProfileEditing = editing;
    profileGridEl?.classList.toggle("is-editing", editing);
    profileViewFields.forEach((el) => {
      el.hidden = editing;
    });
    profileEditFields.forEach((el) => {
      el.hidden = !editing;
    });
    if (profileFooterViewEl) profileFooterViewEl.hidden = editing;
    if (profileFooterEditEl) profileFooterEditEl.hidden = !editing;
    if (profileErrorEl) profileErrorEl.hidden = true;
  }

  function renderProfileView(member) {
    profileEmailEl.textContent = member.email || "—";
    profilePhoneEl.textContent = member.phone || "—";
    profileLinkedEl.textContent = linkedPatientSummary(member);
    profileStatusEl.innerHTML = statusBadgeHtml(member.status);

    const inactive = !isCaregiverActive(member);
    if (profileDeactivateBtn) {
      profileDeactivateBtn.hidden = inactive;
      profileDeactivateBtn.disabled = inactive;
    }
    if (profileLinkBtn) {
      profileLinkBtn.hidden = inactive;
    }
  }

  function fillProfileEditInputs(member) {
    profileEmailInput.value = member.email || "";
    profilePhoneInput.value = member.phone || "";
    profileStatusInput.value = normalizedStatus(member);
  }

  function getProfileFormData() {
    return {
      email: profileEmailInput.value.trim().toLowerCase(),
      phone: profilePhoneInput.value.trim(),
      status: profileStatusInput.value,
    };
  }

  function getProfileBaseline(member) {
    return {
      email: (member.email || "").trim().toLowerCase(),
      phone: (member.phone || "").trim(),
      status: normalizedStatus(member),
    };
  }

  function getProfileChangedFields(member) {
    const baseline = getProfileBaseline(member);
    const current = getProfileFormData();
    const changes = {};
    if (baseline.email !== current.email) changes.email = current.email;
    if (baseline.phone !== current.phone) changes.phone = current.phone;
    if (baseline.status !== current.status) changes.status = current.status;
    return changes;
  }

  function openProfileModal(uid) {
    const member = getCaregiverByUid(uid);
    if (!member || !profileModalEl) return;

    activeCaregiverUid = uid;
    setProfileEditMode(false);
    profileAvatarEl.textContent = getInitials(member.name);
    profileNameEl.textContent = member.name || "—";
    profileStaffIdEl.textContent = `Caregiver ID: ${member.caregiverId || "—"}`;
    renderProfileView(member);
    fillProfileEditInputs(member);

    profileModalEl.hidden = false;
    syncBodyModalLock();
    profileCloseBtn?.focus();
  }

  function closeProfileModal() {
    if (!profileModalEl) return;
    profileModalEl.hidden = true;
    setProfileEditMode(false);
    activeCaregiverUid = null;
    syncBodyModalLock();
  }

  async function handleAddSubmit(event) {
    event.preventDefault();
    if (isSaving) return;
    formErrorEl.hidden = true;

    const name = nameInput.value.trim();
    const email = emailInput.value.trim();
    const phone = phoneInput.value.trim();
    const connectedPatients = collectConnectedPatientsFromContainer(connectedPatientsListEl);

    if (!name || !email) {
      formErrorEl.textContent = "Name and email are required.";
      formErrorEl.hidden = false;
      return;
    }
    if (!email.includes("@")) {
      formErrorEl.textContent = "Please enter a valid email address.";
      formErrorEl.hidden = false;
      return;
    }
    if (connectedPatients.length === 0) {
      formErrorEl.textContent = "Select at least one connected patient.";
      formErrorEl.hidden = false;
      return;
    }

    isSaving = true;
    const submitBtn = formEl.querySelector('[type="submit"]');
    const originalText = submitBtn ? submitBtn.textContent : "Add Caregiver";
    if (submitBtn) {
      submitBtn.disabled = true;
      submitBtn.textContent = "Saving…";
    }

    try {
      await createCaregiver({ name, email, phone, connectedPatients });
      closeAddModal();
      window.alert(
        `Caregiver invited. A password setup link has been sent to ${email}. Their account will be ready after they open the link and set a password.`,
      );
    } catch (error) {
      formErrorEl.textContent = error?.message || "Could not save caregiver account.";
      formErrorEl.hidden = false;
    } finally {
      isSaving = false;
      if (submitBtn) {
        submitBtn.disabled = false;
        submitBtn.textContent = originalText;
      }
    }
  }

  async function handleProfileSave() {
    const member = getCaregiverByUid(activeCaregiverUid);
    if (!member || isSavingProfile) return;

    profileErrorEl.hidden = true;
    const changes = getProfileChangedFields(member);
    if (Object.keys(changes).length === 0) {
      setProfileEditMode(false);
      return;
    }

    if (changes.email && !changes.email.includes("@")) {
      profileErrorEl.textContent = "Please enter a valid email address.";
      profileErrorEl.hidden = false;
      return;
    }

    isSavingProfile = true;
    profileSaveBtn.disabled = true;
    profileSaveLabelEl.textContent = "Saving…";

    try {
      await updateCaregiver(member.uid, changes);
      const updated = getCaregiverByUid(member.uid);
      if (updated) {
        renderProfileView(updated);
        fillProfileEditInputs(updated);
      }
      setProfileEditMode(false);
      renderTable();
    } catch (error) {
      profileErrorEl.textContent = error?.message || "Could not save profile.";
      profileErrorEl.hidden = false;
    } finally {
      isSavingProfile = false;
      profileSaveBtn.disabled = false;
      profileSaveLabelEl.textContent = "Save Changes";
    }
  }

  async function handleProfileDeactivate() {
    const member = getCaregiverByUid(activeCaregiverUid);
    if (!member || !isCaregiverActive(member)) return;

    if (!window.confirm(`Deactivate ${member.name}? Their account status will be set to Inactive.`)) {
      return;
    }

    profileErrorEl.hidden = true;
    profileDeactivateBtn.disabled = true;

    try {
      await deactivateCaregiver(member.uid);
      closeProfileModal();
      setStatusFilter("all");
    } catch (error) {
      profileErrorEl.textContent = error?.message || "Could not deactivate account.";
      profileErrorEl.hidden = false;
      profileDeactivateBtn.disabled = false;
    }
  }

  function openLinkModal(uid) {
    const member = getCaregiverByUid(uid);
    if (!member || !linkModalEl) return;
    linkingUid = uid;
    linkErrorEl.hidden = true;
    linkStaffNameEl.textContent = member.name;
    const selectedIds = (member.connectedPatients || [])
      .map((entry) => entry.patientDocId)
      .filter(Boolean);
    resetPatientSelectList(linkPatientsListEl, selectedIds);
    linkModalEl.hidden = false;
    syncBodyModalLock();
  }

  function closeLinkModal() {
    if (!linkModalEl) return;
    linkModalEl.hidden = true;
    linkingUid = null;
    syncBodyModalLock();
    if (activeCaregiverUid) {
      const member = getCaregiverByUid(activeCaregiverUid);
      if (member) renderProfileView(member);
    }
  }

  async function handleLinkSave() {
    if (!linkingUid) return;
    const caregiver = getCaregiverByUid(linkingUid);
    if (!caregiver) return;

    const connectedPatients = collectConnectedPatientsFromContainer(linkPatientsListEl);
    if (connectedPatients.length === 0) {
      linkErrorEl.textContent = "Select at least one patient to connect.";
      linkErrorEl.hidden = false;
      return;
    }

    linkSaveBtn.disabled = true;
    try {
      await updateCaregiverConnections({
        caregiverUid: caregiver.uid,
        caregiverName: caregiver.name,
        caregiverId: caregiver.caregiverId,
        connectedPatients,
      });
      closeLinkModal();
      renderTable();
    } catch (error) {
      linkErrorEl.textContent = error?.message || "Could not update connected patients.";
      linkErrorEl.hidden = false;
    } finally {
      linkSaveBtn.disabled = false;
    }
  }

  function handleTableClick(event) {
    const profileBtn = event.target.closest("[data-staff-profile]");
    if (profileBtn) {
      openProfileModal(profileBtn.dataset.staffProfile);
    }
  }

  function startRealtime() {
    releaseFirestoreListener(unsubscribeCaregivers);
    releaseFirestoreListener(unsubscribePatients);
    unsubscribeCaregivers = subscribeCaregivers((list) => {
      caregiverCache = list;
      renderTable();
      if (activeCaregiverUid) {
        const member = getCaregiverByUid(activeCaregiverUid);
        if (member && !isProfileEditing) {
          renderProfileView(member);
        }
      }
    });
    unsubscribePatients = subscribePatients((list) => {
      patientsCache = list;
      renderTable();
      refreshOpenPatientSelectLists();
      if (activeCaregiverUid) {
        const member = getCaregiverByUid(activeCaregiverUid);
        if (member && !isProfileEditing) {
          renderProfileView(member);
        }
      }
    });
  }

  addBtn?.addEventListener("click", openAddModal);
  addConnectedPatientBtn?.addEventListener("click", () => {
    addPatientSelectRow(connectedPatientsListEl);
  });
  addLinkPatientBtn?.addEventListener("click", () => {
    addPatientSelectRow(linkPatientsListEl);
  });
  formCloseBtn?.addEventListener("click", closeAddModal);
  formEl?.addEventListener("submit", handleAddSubmit);
  profileCloseBtn?.addEventListener("click", closeProfileModal);
  profileUpdateBtn?.addEventListener("click", () => setProfileEditMode(true));
  profileCancelBtn?.addEventListener("click", () => {
    const member = getCaregiverByUid(activeCaregiverUid);
    if (member) fillProfileEditInputs(member);
    setProfileEditMode(false);
  });
  profileSaveBtn?.addEventListener("click", handleProfileSave);
  profileDeactivateBtn?.addEventListener("click", handleProfileDeactivate);
  profileLinkBtn?.addEventListener("click", () => {
    if (activeCaregiverUid) openLinkModal(activeCaregiverUid);
  });
  linkCloseBtn?.addEventListener("click", closeLinkModal);
  linkSaveBtn?.addEventListener("click", handleLinkSave);
  tbodyEl?.addEventListener("click", handleTableClick);
  searchEl?.addEventListener("input", () => {
    searchQuery = searchEl.value.trim();
    currentPage = 1;
    renderTable();
  });
  filterTabs.forEach((tab) => {
    tab.addEventListener("click", () => setStatusFilter(tab.dataset.status));
  });

  modalEl?.addEventListener("click", (event) => {
    if (event.target === modalEl) closeAddModal();
  });
  profileModalEl?.addEventListener("click", (event) => {
    if (event.target === profileModalEl) closeProfileModal();
  });
  linkModalEl?.addEventListener("click", (event) => {
    if (event.target === linkModalEl) closeLinkModal();
  });

  initStaffAuth((profile) => {
    if (!isAdmin(profile?.role)) {
      window.location.replace("dashboard.html");
      return;
    }
    startCaregiverCounterListener();
    startRealtime();
  });
}
