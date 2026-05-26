import { onAuthStateChanged } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-auth.js";
import { auth } from "./firebase.js";
import {
  verifyActiveStaff,
  saveStaffSession,
  signOutStaff,
} from "./staff-auth.js";

export function getInitials(name) {
  if (!name) return "?";
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return "?";
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
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
  if (menuNameEl) menuNameEl.textContent = profile.name || "—";
  if (menuRoleEl) menuRoleEl.textContent = profile.role || "—";
}

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
      if (onProfile) onProfile(profile);
    } catch {
      window.location.href = "login.html";
    }
  });
}
