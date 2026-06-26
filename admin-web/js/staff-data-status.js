/** Shared Firestore load errors and in-page banners for staff portal pages. */

export function formatFirestoreError(error, context = "data") {
  const code = String(error?.code || "");
  const message = String(error?.message || "").trim();

  if (code === "permission-denied") {
    return `Could not load ${context}. Sign in as an active admin and deploy Firestore rules: firebase deploy --only firestore:rules`;
  }
  if (code === "failed-precondition") {
    return `Could not load ${context}. A Firestore index may still be building — check the browser console and refresh in a minute.`;
  }
  if (code === "unavailable") {
    return `Could not reach Firestore while loading ${context}. Check your network connection and try again.`;
  }
  if (message && message.toLowerCase() !== "internal") {
    return message;
  }
  return `Could not load ${context} from Firestore.`;
}

export function showStaffDataBanner(message, { id = "staff-data-banner" } = {}) {
  if (!message) return;

  let banner = document.getElementById(id);
  if (!banner) {
    banner = document.createElement("div");
    banner.id = id;
    banner.className = "staff-data-banner";
    banner.setAttribute("role", "alert");

    const anchor =
      document.querySelector(".staff-page-header") ||
      document.querySelector(".staff-dashboard") ||
      document.querySelector("main") ||
      document.body;
    anchor.insertAdjacentElement("afterbegin", banner);
  }

  banner.textContent = message;
  banner.hidden = false;
}

export function clearStaffDataBanner(id = "staff-data-banner") {
  const banner = document.getElementById(id);
  if (banner) banner.hidden = true;
}
