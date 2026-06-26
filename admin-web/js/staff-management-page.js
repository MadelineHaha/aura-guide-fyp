import { initStaffAuth } from "./staff-shell.js";
import { isAdmin } from "./staff-rbac.js";
import {
  createStaff,
  deactivateStaff,
  subscribePatients,
  updatePatient,
  updateStaff,
} from "./user-patients-service.js";
import { subscribeAllStaff } from "./staff-list-service.js";
import {
  fetchNextStaffIdPreview,
  subscribeNextStaffIdPreview,
} from "./staff-id-service.js";
import { releaseFirestoreListener } from "./firestore-realtime.js";

const PAGE_SIZE = 6;

/**
 * @param {{
 *   role: "doctor"|"therapist"|"caregiver",
 *   pageTitle: string,
 *   singularLabel: string,
 *   showSpecialty?: boolean,
 *   showPatientLinking?: boolean,
 * }} config
 */
export function initStaffManagementPage(config) {
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
  const nextStaffIdEl = document.getElementById("staff-form-next-id");
  const nameInput = document.getElementById("staff-form-name");
  const emailInput = document.getElementById("staff-form-email");
  const phoneInput = document.getElementById("staff-form-phone");
  const specialtyInput = document.getElementById("staff-form-specialty");
  const specialtyFieldEl = document.getElementById("staff-form-specialty-field");

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
  const profileSpecialtyEl = document.getElementById("staff-profile-specialty");
  const profileSpecialtyFieldEl = document.getElementById("staff-profile-specialty-field");
  const profileSpecialtyInput = document.getElementById("staff-profile-specialty-input");
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
  const linkPatientSelect = document.getElementById("staff-link-patient");
  const linkCloseBtn = document.getElementById("staff-link-close");
  const linkSaveBtn = document.getElementById("staff-link-save");
  const linkRemoveBtn = document.getElementById("staff-link-remove");
  const linkErrorEl = document.getElementById("staff-link-error");
  const linkStaffNameEl = document.getElementById("staff-link-name");

  let staffCache = [];
  let patientsCache = [];
  let searchQuery = "";
  let statusFilter = "all";
  let currentPage = 1;
  let isSaving = false;
  let isProfileEditing = false;
  let isSavingProfile = false;
  let activeStaffUid = null;
  let linkingUid = null;
  let unsubscribeStaff = null;
  let unsubscribePatients = null;
  let unsubscribeStaffCounter = null;
  let nextStaffIdPreview = "—";

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function getInitials(name) {
    const parts = String(name || "?")
      .trim()
      .split(/\s+/)
      .filter(Boolean);
    if (parts.length === 0) return "?";
    if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
    return `${parts[0][0]}${parts[parts.length - 1][0]}`.toUpperCase();
  }

  function isStaffActive(member) {
    return String(member?.status || "").trim().toLowerCase() === "active";
  }

  function normalizedStaffStatus(member) {
    return isStaffActive(member) ? "Active" : "Inactive";
  }

  function staffStatusBadgeHtml(status) {
    const active = String(status || "").toLowerCase() === "active";
    const cls = active ? "patient-status patient-status--stable" : "patient-status patient-status--monitoring";
    return `<span class="${cls}">${active ? "Active" : "Inactive"}</span>`;
  }

  function roleMatches(member) {
    return String(member.role || "").trim().toLowerCase() === config.role;
  }

  function linkedPatientCount(uid) {
    return patientsCache.filter(
      (patient) =>
        patient.accountStatus !== "Inactive" &&
        patient.assignedCaregiverId === uid,
    ).length;
  }

  function linkedPatientNames(uid) {
    const names = patientsCache
      .filter(
        (patient) =>
          patient.accountStatus !== "Inactive" &&
          patient.assignedCaregiverId === uid,
      )
      .map((patient) => patient.name);
    return names.length ? names.join(", ") : "—";
  }

  function getStaffByUid(uid) {
    return staffCache.find((member) => member.uid === uid) || null;
  }

  function filteredStaff() {
    const q = searchQuery.toLowerCase();
    return staffCache.filter((member) => {
      if (!roleMatches(member)) return false;

      const active = isStaffActive(member);
      const matchesStatus =
        statusFilter === "all" ||
        (statusFilter === "active" && active) ||
        (statusFilter === "inactive" && !active);

      const haystack = `${member.name} ${member.staffID} ${member.email} ${member.phone}`.toLowerCase();
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
    const linkCell = config.showPatientLinking
      ? `<td>${linkedPatientCount(member.uid)}</td>`
      : "";
    return `
      <tr data-uid="${member.uid}">
        <td>${escapeHtml(member.staffID || "—")}</td>
        <td><p class="cell-primary">${escapeHtml(member.name)}</p></td>
        <td>${escapeHtml(member.phone || "—")}</td>
        <td>${escapeHtml(member.email || "—")}</td>
        <td>${staffStatusBadgeHtml(member.status)}</td>
        ${linkCell}
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
    const filtered = filteredStaff();
    const total = filtered.length;
    const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
    if (currentPage > totalPages) currentPage = totalPages;

    const label = config.singularLabel.toLowerCase();
    if (countEl) {
      countEl.textContent = `${total} ${label}${total === 1 ? "" : "s"}`;
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

  function syncBodyModalLock() {
    const anyOpen =
      (modalEl && !modalEl.hidden) ||
      (profileModalEl && !profileModalEl.hidden) ||
      (linkModalEl && !linkModalEl.hidden);
    document.body.classList.toggle("modal-open", Boolean(anyOpen));
  }

  function renderNextStaffIdPreview() {
    if (!nextStaffIdEl) return;
    nextStaffIdEl.textContent = `New Staff ID: ${nextStaffIdPreview}`;
  }

  async function refreshNextStaffIdPreview() {
    try {
      nextStaffIdPreview = await fetchNextStaffIdPreview();
    } catch {
      nextStaffIdPreview = "—";
    }
    renderNextStaffIdPreview();
  }

  function startStaffCounterListener() {
    releaseFirestoreListener(unsubscribeStaffCounter);
    unsubscribeStaffCounter = subscribeNextStaffIdPreview(
      (staffId) => {
        nextStaffIdPreview = staffId;
        renderNextStaffIdPreview();
      },
      () => {
        nextStaffIdPreview = "—";
        renderNextStaffIdPreview();
      },
    );
  }

  function openAddModal() {
    formEl.reset();
    formErrorEl.hidden = true;
    modalTitleEl.textContent = `Add ${config.singularLabel}`;
    if (specialtyFieldEl) specialtyFieldEl.hidden = !config.showSpecialty;
    void refreshNextStaffIdPreview();
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
    if (profileSpecialtyEl) {
      profileSpecialtyEl.textContent = member.specialty || "—";
    }
    if (profileLinkedEl) {
      profileLinkedEl.textContent = linkedPatientNames(member.uid);
    }
    profileStatusEl.innerHTML = staffStatusBadgeHtml(member.status);

    const inactive = !isStaffActive(member);
    if (profileDeactivateBtn) {
      profileDeactivateBtn.hidden = inactive;
      profileDeactivateBtn.disabled = inactive;
    }
    if (profileLinkBtn) {
      profileLinkBtn.hidden = inactive || !config.showPatientLinking;
    }
  }

  function fillProfileEditInputs(member) {
    profileEmailInput.value = member.email || "";
    profilePhoneInput.value = member.phone || "";
    if (profileSpecialtyInput) {
      profileSpecialtyInput.value = member.specialty || "";
    }
    profileStatusInput.value = normalizedStaffStatus(member);
  }

  function getProfileFormData() {
    return {
      email: profileEmailInput.value.trim().toLowerCase(),
      phone: profilePhoneInput.value.trim(),
      specialty: profileSpecialtyInput?.value.trim() || "",
      status: profileStatusInput.value,
    };
  }

  function getProfileBaseline(member) {
    return {
      email: (member.email || "").trim().toLowerCase(),
      phone: (member.phone || "").trim(),
      specialty: (member.specialty || "").trim(),
      status: normalizedStaffStatus(member),
    };
  }

  function getProfileChangedFields(member) {
    const baseline = getProfileBaseline(member);
    const current = getProfileFormData();
    const changes = {};
    if (baseline.email !== current.email) changes.email = current.email;
    if (baseline.phone !== current.phone) changes.phone = current.phone;
    if (config.showSpecialty && baseline.specialty !== current.specialty) {
      changes.specialty = current.specialty;
    }
    if (baseline.status !== current.status) changes.status = current.status;
    return changes;
  }

  function openProfileModal(uid) {
    const member = getStaffByUid(uid);
    if (!member || !profileModalEl) return;

    activeStaffUid = uid;
    setProfileEditMode(false);

    if (profileSpecialtyFieldEl) {
      profileSpecialtyFieldEl.hidden = !config.showSpecialty;
    }

    profileAvatarEl.textContent = getInitials(member.name);
    profileNameEl.textContent = member.name || "—";
    profileStaffIdEl.textContent = `Staff ID: ${member.staffID || "—"}`;
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
    activeStaffUid = null;
    syncBodyModalLock();
  }

  async function handleAddSubmit(event) {
    event.preventDefault();
    if (isSaving) return;
    formErrorEl.hidden = true;

    const name = nameInput.value.trim();
    const email = emailInput.value.trim();
    const phone = phoneInput.value.trim();
    const specialty = specialtyInput?.value.trim() || "";

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

    isSaving = true;
    const submitBtn = formEl.querySelector('[type="submit"]');
    const originalText = submitBtn ? submitBtn.textContent : "Add Staff";
    if (submitBtn) {
      submitBtn.disabled = true;
      submitBtn.textContent = "Saving…";
    }

    try {
      await createStaff({
        name,
        email,
        role: config.role,
        specialty,
        phone,
      });
      closeAddModal();
      window.alert(
        `${config.singularLabel} invited. A password setup link has been sent to ${email}. Their account will be ready after they open the link and set a password.`,
      );
    } catch (error) {
      formErrorEl.textContent = error?.message || "Could not save staff account.";
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
    const member = getStaffByUid(activeStaffUid);
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
      await updateStaff(member.uid, changes);
      const updated = getStaffByUid(member.uid);
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
    const member = getStaffByUid(activeStaffUid);
    if (!member || !isStaffActive(member)) return;

    if (
      !window.confirm(
        `Deactivate ${member.name}? Their account status will be set to Inactive.`,
      )
    ) {
      return;
    }

    profileErrorEl.hidden = true;
    profileDeactivateBtn.disabled = true;

    try {
      await deactivateStaff(member.uid);
      closeProfileModal();
      setStatusFilter("all");
    } catch (error) {
      profileErrorEl.textContent = error?.message || "Could not deactivate account.";
      profileErrorEl.hidden = false;
      profileDeactivateBtn.disabled = false;
    }
  }

  function openLinkModal(uid) {
    const member = getStaffByUid(uid);
    if (!member || !linkModalEl) return;
    linkingUid = uid;
    linkErrorEl.hidden = true;
    linkStaffNameEl.textContent = member.name;
    const options = patientsCache
      .filter((patient) => patient.accountStatus !== "Inactive")
      .map(
        (patient) =>
          `<option value="${patient.id}" ${patient.assignedCaregiverId === uid ? "selected" : ""}>${escapeHtml(patient.name)} (${escapeHtml(patient.patientId)})</option>`,
      )
      .join("");
    linkPatientSelect.innerHTML = `<option value="">— Select patient —</option>${options}`;
    syncLinkRemoveButton();
    linkModalEl.hidden = false;
    syncBodyModalLock();
  }

  function closeLinkModal() {
    if (!linkModalEl) return;
    linkModalEl.hidden = true;
    linkingUid = null;
    syncBodyModalLock();
    if (activeStaffUid) {
      const member = getStaffByUid(activeStaffUid);
      if (member) renderProfileView(member);
    }
  }

  function syncLinkRemoveButton() {
    if (!linkRemoveBtn || !linkingUid) return;
    const patientDocId = linkPatientSelect?.value || "";
    const patient = patientsCache.find((entry) => entry.id === patientDocId);
    const canRemove = Boolean(patient) && patient.assignedCaregiverId === linkingUid;
    linkRemoveBtn.hidden = !canRemove;
    linkRemoveBtn.disabled = !canRemove;
  }

  async function handleLinkSave() {
    if (!linkingUid) return;
    const patientDocId = linkPatientSelect.value;
    if (!patientDocId) {
      linkErrorEl.textContent = "Select a patient to link.";
      linkErrorEl.hidden = false;
      return;
    }
    const caregiver = getStaffByUid(linkingUid);
    linkSaveBtn.disabled = true;
    try {
      await updatePatient(patientDocId, {
        assignedCaregiverId: linkingUid,
        assignedCaregiverName: caregiver?.name || "",
      });
      closeLinkModal();
      renderTable();
    } catch (error) {
      linkErrorEl.textContent = error?.message || "Could not link patient.";
      linkErrorEl.hidden = false;
    } finally {
      linkSaveBtn.disabled = false;
    }
  }

  async function handleLinkRemove() {
    if (!linkingUid) return;
    const patientDocId = linkPatientSelect.value;
    const patient = patientsCache.find((entry) => entry.id === patientDocId);
    if (!patient || patient.assignedCaregiverId !== linkingUid) {
      linkErrorEl.textContent = "Select a linked patient to remove access.";
      linkErrorEl.hidden = false;
      return;
    }
    if (
      !window.confirm(
        `Remove ${patient.name}'s caregiver access for this account?`,
      )
    ) {
      return;
    }
    linkRemoveBtn.disabled = true;
    try {
      await updatePatient(patientDocId, {
        assignedCaregiverId: "",
        assignedCaregiverName: "",
      });
      closeLinkModal();
      renderTable();
    } catch (error) {
      linkErrorEl.textContent = error?.message || "Could not remove access.";
      linkErrorEl.hidden = false;
    } finally {
      linkRemoveBtn.disabled = false;
    }
  }

  function handleTableClick(event) {
    const profileBtn = event.target.closest("[data-staff-profile]");
    if (profileBtn) {
      openProfileModal(profileBtn.dataset.staffProfile);
    }
  }

  function startRealtime() {
    releaseFirestoreListener(unsubscribeStaff);
    releaseFirestoreListener(unsubscribePatients);
    unsubscribeStaff = subscribeAllStaff((list) => {
      staffCache = list;
      renderTable();
      if (activeStaffUid) {
        const member = getStaffByUid(activeStaffUid);
        if (member && !isProfileEditing) {
          renderProfileView(member);
        }
      }
    });
    if (config.showPatientLinking) {
      unsubscribePatients = subscribePatients((list) => {
        patientsCache = list;
        renderTable();
        if (activeStaffUid) {
          const member = getStaffByUid(activeStaffUid);
          if (member && !isProfileEditing) {
            renderProfileView(member);
          }
        }
      });
    }
  }

  addBtn?.addEventListener("click", openAddModal);
  formCloseBtn?.addEventListener("click", closeAddModal);
  formEl?.addEventListener("submit", handleAddSubmit);
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

  profileCloseBtn?.addEventListener("click", closeProfileModal);
  profileUpdateBtn?.addEventListener("click", () => {
    setProfileEditMode(true);
    profileEmailInput?.focus();
  });
  profileSaveBtn?.addEventListener("click", handleProfileSave);
  profileCancelBtn?.addEventListener("click", () => {
    const member = getStaffByUid(activeStaffUid);
    if (member) {
      fillProfileEditInputs(member);
      renderProfileView(member);
    }
    setProfileEditMode(false);
  });
  profileDeactivateBtn?.addEventListener("click", handleProfileDeactivate);
  profileLinkBtn?.addEventListener("click", () => {
    if (activeStaffUid) openLinkModal(activeStaffUid);
  });
  profileModalEl?.addEventListener("click", (event) => {
    if (event.target === profileModalEl) closeProfileModal();
  });

  linkCloseBtn?.addEventListener("click", closeLinkModal);
  linkSaveBtn?.addEventListener("click", handleLinkSave);
  linkRemoveBtn?.addEventListener("click", handleLinkRemove);
  linkPatientSelect?.addEventListener("change", syncLinkRemoveButton);
  linkModalEl?.addEventListener("click", (event) => {
    if (event.target === linkModalEl) closeLinkModal();
  });

  initStaffAuth((profile) => {
    if (!isAdmin(profile?.role)) {
      window.location.replace("dashboard.html");
      return;
    }
    if (profileSpecialtyFieldEl) {
      profileSpecialtyFieldEl.hidden = !config.showSpecialty;
    }
    startRealtime();
    startStaffCounterListener();
  });

  window.addEventListener("beforeunload", () => {
    releaseFirestoreListener(unsubscribeStaff);
    releaseFirestoreListener(unsubscribePatients);
    releaseFirestoreListener(unsubscribeStaffCounter);
  });
}
