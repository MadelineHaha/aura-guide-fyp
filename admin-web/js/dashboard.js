import { onAuthStateChanged } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-auth.js";
import { auth } from "./firebase.js";
import {
  verifyActiveStaff,
  saveStaffSession,
  signOutStaff,
} from "./staff-auth.js";

const nameEl = document.getElementById("staff-name");
const roleEl = document.getElementById("staff-role");
const staffIdEl = document.getElementById("staff-id");
const emailEl = document.getElementById("staff-email");
const signOutBtn = document.getElementById("btn-sign-out");

function renderProfile(profile) {
  nameEl.textContent = profile.name || "—";
  roleEl.textContent = profile.role || "—";
  staffIdEl.textContent = profile.staffID || "—";
  emailEl.textContent = profile.email || "—";
}

signOutBtn.addEventListener("click", async () => {
  signOutBtn.disabled = true;
  try {
    await signOutStaff();
    window.location.href = "login.html";
  } catch {
    signOutBtn.disabled = false;
  }
});

onAuthStateChanged(auth, async (user) => {
  if (!user) {
    window.location.href = "login.html";
    return;
  }

  try {
    const profile = await verifyActiveStaff(user.uid);
    saveStaffSession(profile);
    renderProfile(profile);
  } catch {
    window.location.href = "login.html";
  }
});
