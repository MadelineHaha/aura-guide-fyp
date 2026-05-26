import { initStaffAuth } from "./staff-shell.js";

const greetingEl = document.getElementById("dashboard-greeting");

function formatGreeting(profile) {
  const now = new Date();
  const hour = now.getHours();
  const dayPart =
    hour < 12 ? "morning" : hour < 17 ? "afternoon" : "evening";
  const dateStr = now.toLocaleDateString("en-GB", {
    weekday: "long",
    day: "numeric",
    month: "long",
    year: "numeric",
  });
  const displayName = profile.name || "Staff";
  const honorific = profile.role?.toLowerCase().includes("doctor") ? "Dr." : "";
  const who = honorific
    ? `${honorific} ${displayName.split(" ").pop()}`
    : displayName;
  return `${dateStr} — Good ${dayPart}, ${who}`;
}

initStaffAuth((profile) => {
  if (greetingEl) greetingEl.textContent = formatGreeting(profile);
});
