import { onAuthStateChanged } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-auth.js";
import { auth } from "./firebase.js";
import { isFirebaseConfigured } from "./firebase-config.js";
import {
  signInStaff,
  verifyActiveStaff,
  getAuthErrorMessage,
} from "./staff-auth.js";

const form = document.querySelector(".login-form");
const emailInput = document.getElementById("email");
const passwordInput = document.getElementById("password");
const submitBtn = document.querySelector(".btn-sign-in");
const errorEl = document.getElementById("login-error");
const toggleBtn = document.querySelector(".toggle-password");

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

  const email = emailInput.value.trim();
  const password = passwordInput.value;

  if (!email || !password) {
    showError("Please enter your email and password.");
    return;
  }

  if (!isFirebaseConfigured()) {
    showError(
      "Firebase is not configured yet. Paste your project settings into js/firebase-config.js (see instructions in that file)."
    );
    return;
  }

  setLoading(true);

  try {
    await signInStaff(email, password);
    window.location.href = "dashboard.html";
  } catch (error) {
    showError(getAuthErrorMessage(error));
  } finally {
    setLoading(false);
  }
});

onAuthStateChanged(auth, async (user) => {
  if (!user) return;
  try {
    await verifyActiveStaff(user.uid);
    window.location.href = "dashboard.html";
  } catch {
    /* stay on login — profile missing or inactive */
  }
});
