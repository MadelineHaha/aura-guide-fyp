import { onAuthStateChanged } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-auth.js";
import { auth } from "./firebase.js";
import { isFirebaseConfigured } from "./firebase-config.js";
import {
  signInStaff,
  verifyActiveStaff,
  getAuthErrorMessage,
  LOGIN_ERROR_MESSAGE,
} from "./staff-auth.js";
import { LOG_ACTIONS } from "./activity-log-actions.js";
import { logStaffActivity, logSecurityAudit, warmUpActivityLogIpCache } from "./activity-logs-service.js";
import {
  attemptsRemainingMessage,
  clearLoginLockout,
  getLoginLockoutStatus,
  lockoutMessage,
  recordLoginFailure,
} from "./login-lockout.js";

const form = document.querySelector(".login-form");
const emailInput = document.getElementById("email");
const passwordInput = document.getElementById("password");
const submitBtn = document.querySelector(".btn-sign-in");
const errorEl = document.getElementById("login-error");
const toggleBtn = document.querySelector(".toggle-password");

let lockoutTimer = null;

function showError(message) {
  errorEl.textContent = message;
  errorEl.hidden = false;
}

function clearError() {
  errorEl.textContent = "";
  errorEl.hidden = true;
}

function setLoading(isLoading) {
  submitBtn.disabled = isLoading;
  submitBtn.classList.toggle("is-loading", isLoading);
  submitBtn.textContent = isLoading ? "Signing in…" : "Sign in to Staff Dashboard";
  emailInput.disabled = isLoading;
  passwordInput.disabled = isLoading;
}

function applyLockoutUi() {
  const status = getLoginLockoutStatus();
  const locked = status.locked;

  emailInput.disabled = locked;
  passwordInput.disabled = locked;
  submitBtn.disabled = locked;

  if (locked) {
    showError(lockoutMessage(status));
  }
}

function startLockoutTimer() {
  if (lockoutTimer) clearInterval(lockoutTimer);
  applyLockoutUi();

  lockoutTimer = setInterval(() => {
    const status = getLoginLockoutStatus();
    if (!status.locked) {
      clearInterval(lockoutTimer);
      lockoutTimer = null;
      applyLockoutUi();
      clearError();
      return;
    }
    showError(lockoutMessage(status));
  }, 1000);
}

function handleFailedLogin(email, message) {
  const result = recordLoginFailure();

  if (result.justLocked) {
    startLockoutTimer();
    showError(lockoutMessage(result));
  } else if (result.locked) {
    startLockoutTimer();
    showError(lockoutMessage(result));
  } else {
    const attemptsHint = attemptsRemainingMessage(result.attemptsRemaining);
    showError(attemptsHint ? `${message} ${attemptsHint}` : message);
  }

  void writeFailedLoginAudit(email, message, result);
}

async function writeFailedLoginAudit(email, message, result) {
  await logSecurityAudit({
    action: LOG_ACTIONS.FAILED_LOGIN,
    details: message || LOGIN_ERROR_MESSAGE,
    userName: email || "Unknown",
    userId: email || "—",
    source: "admin",
  });

  if (result.justLocked) {
    await logSecurityAudit({
      action: LOG_ACTIONS.ACCOUNT_LOCKOUT,
      details: `Staff login locked for ${result.remainingLabel} after 3 failed attempts (lockout #${result.lockoutCount}).`,
      userName: email || "Unknown",
      userId: email || "—",
      source: "admin",
    });
  }
}

toggleBtn.addEventListener("click", () => {
  const isHidden = passwordInput.type === "password";
  passwordInput.type = isHidden ? "text" : "password";
  toggleBtn.classList.toggle("is-visible", isHidden);
  toggleBtn.setAttribute("aria-label", isHidden ? "Hide password" : "Show password");
  toggleBtn.setAttribute("aria-pressed", String(isHidden));
});

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  clearError();

  const lockoutStatus = getLoginLockoutStatus();
  if (lockoutStatus.locked) {
    showError(lockoutMessage(lockoutStatus));
    return;
  }

  const email = emailInput.value.trim();
  const password = passwordInput.value;

  if (!email || !password) {
    showError("Please enter your email and password.");
    return;
  }

  if (!isFirebaseConfigured()) {
    showError(
      "Firebase is not configured yet. Paste your project settings into js/firebase-config.js (see instructions in that file).",
    );
    return;
  }

  setLoading(true);

  try {
    await signInStaff(email, password);
    clearLoginLockout();
    window.location.href = "dashboard.html";
  } catch (error) {
    const message = getAuthErrorMessage(error);
    handleFailedLogin(email, message);
  } finally {
    setLoading(false);
    applyLockoutUi();
  }
});

startLockoutTimer();
void warmUpActivityLogIpCache();

onAuthStateChanged(auth, async (user) => {
  if (!user) return;
  try {
    await verifyActiveStaff(user.uid);
    window.location.href = "dashboard.html";
  } catch {
    /* stay on login — profile missing or inactive */
  }
});
