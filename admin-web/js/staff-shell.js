import { onAuthStateChanged } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-auth.js";
import { auth } from "./firebase.js";
import {
  verifyActiveStaff,
  saveStaffSession,
  signOutStaff,
} from "./staff-auth.js";
import { LOG_ACTIONS } from "./activity-log-actions.js";
import { logSecurityAudit } from "./activity-logs-service.js";
import { initEmergencyAlertsWatcher } from "./emergency-alerts-watcher.js";
import { formatStaffDisplayName } from "./staff-name-format.js";

const NAV_SCROLL_STORAGE_KEY = "staffNavScrollLeft";

export function getInitials(name) {
  if (!name) return "?";
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function isActiveLinkVisible(nav, active) {
  const navRect = nav.getBoundingClientRect();
  const linkRect = active.getBoundingClientRect();
  return (
    linkRect.left >= navRect.left - 2 && linkRect.right <= navRect.right + 2
  );
}

function initStaffNavScroll(nav) {
  if (nav.dataset.scrollReady) return;
  nav.dataset.scrollReady = "true";

  const wrap = nav.closest(".staff-nav-links-wrap");
  if (!wrap) return;

  const btnPrev = wrap.querySelector(".staff-nav-scroll-btn--prev");
  const btnNext = wrap.querySelector(".staff-nav-scroll-btn--next");
  if (!btnPrev || !btnNext) return;

  let saveScrollTimer = null;

  function saveScrollPosition() {
    sessionStorage.setItem(NAV_SCROLL_STORAGE_KEY, String(nav.scrollLeft));
  }

  function updateScrollState() {
    const maxScroll = nav.scrollWidth - nav.clientWidth;
    const canScroll = maxScroll > 4;
    wrap.classList.toggle("is-scrollable", canScroll);
    wrap.classList.toggle("can-scroll-left", nav.scrollLeft > 4);
    wrap.classList.toggle("can-scroll-right", nav.scrollLeft < maxScroll - 4);
    btnPrev.disabled = !canScroll || nav.scrollLeft <= 4;
    btnNext.disabled = !canScroll || nav.scrollLeft >= maxScroll - 4;
  }

  function revealActiveLinkIfNeeded() {
    const active = nav.querySelector(".staff-nav-link.is-active");
    if (!active || isActiveLinkVisible(nav, active)) return;
    active.scrollIntoView({ inline: "nearest", block: "nearest" });
  }

  const savedScroll = Number(sessionStorage.getItem(NAV_SCROLL_STORAGE_KEY));
  if (Number.isFinite(savedScroll) && savedScroll >= 0) {
    nav.scrollLeft = savedScroll;
  }

  updateScrollState();
  revealActiveLinkIfNeeded();
  updateScrollState();

  nav.addEventListener(
    "wheel",
    (event) => {
      if (nav.scrollWidth <= nav.clientWidth + 4) return;
      if (Math.abs(event.deltaY) > Math.abs(event.deltaX)) {
        event.preventDefault();
        nav.scrollLeft += event.deltaY;
      }
    },
    { passive: false },
  );

  nav.addEventListener("scroll", () => {
    updateScrollState();
    clearTimeout(saveScrollTimer);
    saveScrollTimer = setTimeout(saveScrollPosition, 120);
  }, { passive: true });

  btnPrev.addEventListener("click", () => {
    nav.scrollBy({ left: -220, behavior: "smooth" });
  });
  btnNext.addEventListener("click", () => {
    nav.scrollBy({ left: 220, behavior: "smooth" });
  });

  window.addEventListener("resize", updateScrollState);
}

function initStaffNavigation() {
  const nav = document.querySelector(".staff-nav-links");
  if (!nav) return;
  initStaffNavScroll(nav);
}

function bindUserMenu() {
  const userMenuEl = document.getElementById("user-menu");
  const userMenuBtn = document.getElementById("btn-user-menu");
  const signOutBtn = document.getElementById("btn-sign-out");
  if (!userMenuEl || !userMenuBtn || !signOutBtn) return;

  userMenuBtn.addEventListener("click", () => {
    userMenuEl.hidden = !userMenuEl.hidden;
  });

  document.addEventListener("click", (event) => {
    if (
      !userMenuEl.hidden &&
      !userMenuEl.contains(event.target) &&
      !userMenuBtn.contains(event.target)
    ) {
      userMenuEl.hidden = true;
    }
  });

  signOutBtn.addEventListener("click", async () => {
    signOutBtn.disabled = true;
    try {
      await signOutStaff();
      window.location.href = "login.html";
    } catch {
      signOutBtn.disabled = false;
    }
  });
}

export function renderStaffNav(profile) {
  const avatarInitialsEl = document.getElementById("staff-avatar-initials");
  const menuNameEl = document.getElementById("menu-staff-name");
  const menuRoleEl = document.getElementById("menu-staff-role");
  if (avatarInitialsEl) avatarInitialsEl.textContent = getInitials(profile.name);
  if (menuNameEl) {
    menuNameEl.textContent = formatStaffDisplayName(profile) || profile.name || "—";
  }
  if (menuRoleEl) menuRoleEl.textContent = profile.role || "—";
}

initStaffNavigation();

export function initStaffAuth(onProfile) {
  bindUserMenu();

  onAuthStateChanged(auth, async (user) => {
    if (!user) {
      window.location.href = "login.html";
      return;
    }

    try {
      const profile = await verifyActiveStaff(user.uid);
      saveStaffSession(profile);
      renderStaffNav(profile);
      initEmergencyAlertsWatcher();
      if (onProfile) onProfile(profile);
    } catch (error) {
      await logSecurityAudit({
        action: LOG_ACTIONS.UNAUTHORIZED_ACCESS,
        details: error?.message || "Inactive or invalid staff account attempted portal access.",
        userName: user.email || "Unknown",
        userId: user.uid,
        source: "admin",
      });
      window.location.href = "login.html";
    }
  });
}
