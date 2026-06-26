import { onAuthStateChanged } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-auth.js";
import { auth } from "./firebase.js";
import {
  verifyActiveStaff,
  saveStaffSession,
  getStaffSession,
  signOutStaff,
} from "./staff-auth.js";
import { LOG_ACTIONS } from "./activity-log-actions.js";
import { logSecurityAudit } from "./activity-logs-service.js";
import { initEmergencyAlertsWatcher } from "./emergency-alerts-watcher.js";
import { formatStaffDisplayName } from "./staff-name-format.js";
import {
  allowedPagesForRole,
  canAccessPage,
  homePageForRole,
  roleDisplayLabel,
  isAdmin,
  isDoctor,
  isTherapist,
} from "./staff-rbac.js";

const NAV_SCROLL_STORAGE_KEY = "staffNavScrollLeft";
let staffAuthListenerBound = false;
let emergencyWatcherStarted = false;
let activeStaffUid = null;
let activeStaffProfile = null;
let pageAccessEnforced = false;
const profileCallbacks = new Set();

function currentStaffPageName() {
  const segments = (window.location.pathname || "").split("/").filter(Boolean);
  const file = segments.pop() || "";
  if (!file || file.toLowerCase() === "html") {
    return "dashboard.html";
  }
  if (file.toLowerCase().endsWith(".html")) {
    return file.toLowerCase();
  }
  return `${file.toLowerCase()}.html`;
}

function isLoginPage() {
  return currentStaffPageName() === "login.html";
}

function redirectToLogin() {
  if (isLoginPage()) return;
  window.location.replace("login.html");
}

function redirectToHome(role) {
  const home = homePageForRole(role);
  if (currentStaffPageName() === home) return;
  window.location.replace(home);
}

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

let userMenuBound = false;

function bindUserMenu() {
  if (userMenuBound) return;
  userMenuBound = true;

  const userMenuEl = document.getElementById("user-menu");
  const userMenuBtn = document.getElementById("btn-user-menu");
  const signOutBtn = document.getElementById("btn-sign-out");
  if (!userMenuEl || !userMenuBtn || !signOutBtn) return;

  userMenuBtn.addEventListener("click", (event) => {
    event.stopPropagation();
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
  if (menuRoleEl) menuRoleEl.textContent = roleDisplayLabel(profile.role) || "—";
}

initStaffNavigation();

// Fast-path: Immediately render the navigation bar and user profile using cached session 
// before Firebase Auth has time to initialize. This eliminates the 1-second loading delay!
const cachedSession = getStaffSession();
if (cachedSession && cachedSession.role) {
  applyRbacNavigation(cachedSession.role);
  renderStaffNav(cachedSession);
}

export function applyRbacNavigation(role) {
  const navContainer = document.querySelector(".staff-nav-links");
  if (!navContainer) return;

  const currentPath = window.location.pathname.split("/").pop().toLowerCase() || "dashboard.html";

  const NAV_LINKS = {
    admin: [
      { label: "Dashboard", href: "dashboard.html" },
      { label: "Patients", href: "patients.html" },
      { label: "Doctors", href: "doctors.html" },
      { label: "Therapists", href: "therapists.html" },
      { label: "Caregivers", href: "caregivers.html" },
      { label: "Appointments", href: "appointments.html" },
      { label: "Emergencies", href: "emergencies.html" },
      { label: "Reports", href: "reports.html" },
      { label: "Communication", href: "communication.html" },
      { label: "Audit Log", href: "logs.html" }
    ],
    doctor: [
      { label: "Dashboard", href: "staff-dashboard.html" },
      { label: "Patients", href: "patients.html" },
      { label: "Medical Records", href: "medical-records.html" },
      { label: "Medication Management", href: "medications.html" },
      { label: "Appointments", href: "appointments.html" },
      { label: "Communication", href: "communication.html" },
      { label: "Reports", href: "staff-reports.html" }
    ],
    therapist: [
      { label: "Dashboard", href: "staff-dashboard.html" },
      { label: "Patients", href: "patients.html" },
      { label: "Therapy Sessions", href: "therapy-sessions.html" },
      { label: "Rehab Plans", href: "rehab-plans.html" },
      { label: "Communication", href: "communication.html" },
      { label: "Reports", href: "therapist-reports.html" }
    ]
  };

  const navRole = isAdmin(role) ? "admin" : isDoctor(role) ? "doctor" : isTherapist(role) ? "therapist" : null;
  if (!navRole) return;

  const normalizePath = (p) => p.replace(/\.html$/i, "");
  
  const linksHtml = NAV_LINKS[navRole].map(link => {
    const isActive = normalizePath(currentPath) === normalizePath(link.href) ? "is-active" : "";
    return `<a class="staff-nav-link ${isActive}" href="${link.href}">${link.label}</a>`;
  }).join("");

  navContainer.innerHTML = linksHtml;
  
  // Failsafe: Ensure navigation is fully visible in case the browser 
  // has cached an older version of the CSS that set opacity to 0.
  navContainer.style.opacity = "1";
  
  // Scroll the active link into view if it is overflowing
  setTimeout(() => {
    const active = navContainer.querySelector(".is-active");
    if (active) {
      active.scrollIntoView({ behavior: "smooth", inline: "nearest", block: "nearest" });
    }
  }, 50);
}

/** Redirects once per page load when the role cannot open the current HTML page. */
export function enforcePageAccess(role) {
  if (pageAccessEnforced || isLoginPage()) return;
  pageAccessEnforced = true;

  const currentPage = currentStaffPageName();
  if (!canAccessPage(role, currentPage)) {
    redirectToHome(role);
  }
}

function notifyProfileCallbacks(profile) {
  activeStaffProfile = profile;
  for (const callback of profileCallbacks) {
    try {
      callback(profile);
    } catch (callbackError) {
      console.error("Staff page init callback failed:", callbackError);
    }
  }
}

async function handleSignedInStaff(user, { enforceAccess = false } = {}) {
  try {
    const profile = await verifyActiveStaff(user.uid);
    saveStaffSession(profile);
    renderStaffNav(profile);
    applyRbacNavigation(profile.role);
    if (enforceAccess) {
      enforcePageAccess(profile.role);
    }
    if (!emergencyWatcherStarted) {
      initEmergencyAlertsWatcher();
      emergencyWatcherStarted = true;
    }
    activeStaffUid = user.uid;
    notifyProfileCallbacks(profile);
  } catch (error) {
    await logSecurityAudit({
      action: LOG_ACTIONS.UNAUTHORIZED_ACCESS,
      details: error?.message || "Inactive or invalid staff account attempted portal access.",
      userName: user.email || "Unknown",
      userId: user.uid,
      source: "admin",
    });
    redirectToLogin();
  }
}

export function initStaffAuth(onProfile) {
  bindUserMenu();

  if (typeof onProfile === "function") {
    profileCallbacks.add(onProfile);
    if (activeStaffProfile) {
      try {
        onProfile(activeStaffProfile);
      } catch (callbackError) {
        console.error("Staff page init callback failed:", callbackError);
      }
    }
  }

  if (staffAuthListenerBound) return;
  staffAuthListenerBound = true;

  void auth.authStateReady().then(() => {
    onAuthStateChanged(auth, async (user) => {
      if (!user) {
        activeStaffUid = null;
        activeStaffProfile = null;
        if (!isLoginPage()) redirectToLogin();
        return;
      }

      if (user.uid === activeStaffUid && activeStaffProfile) {
        try {
          const profile = await verifyActiveStaff(user.uid);
          saveStaffSession(profile);
          renderStaffNav(profile);
          applyRbacNavigation(profile.role);
          activeStaffProfile = profile;
          notifyProfileCallbacks(profile);
        } catch {
          /* keep current page on transient profile read errors */
        }
        return;
      }

      await handleSignedInStaff(user, { enforceAccess: true });
    });
  });
}
