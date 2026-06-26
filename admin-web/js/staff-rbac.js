/** Role-based access for the staff portal (client-side navigation + data scoping). */

export const STAFF_ROLES = {
  ADMIN: "admin",
  DOCTOR: "doctor",
  THERAPIST: "therapist",
};

const ROLE_ALIASES = {
  admin: STAFF_ROLES.ADMIN,
  administrator: STAFF_ROLES.ADMIN,
  doctor: STAFF_ROLES.DOCTOR,
  dr: STAFF_ROLES.DOCTOR,
  physician: STAFF_ROLES.DOCTOR,
  therapist: STAFF_ROLES.THERAPIST,
  caregiver: "caregiver",
  nurse: "caregiver",
};

/** @returns {"admin"|"doctor"|"therapist"|"caregiver"|""} */
export function normalizeStaffRole(role) {
  const key = String(role || "").trim().toLowerCase();
  return ROLE_ALIASES[key] || "";
}

const PAGE_ACCESS = {
  [STAFF_ROLES.ADMIN]: [
    "dashboard.html",
    "patients.html",
    "doctors.html",
    "therapists.html",
    "caregivers.html",
    "appointments.html",
    "emergencies.html",
    "reports.html",
    "communication.html",
    "logs.html",
    "administration.html",
  ],
  [STAFF_ROLES.DOCTOR]: [
    "staff-dashboard.html",
    "appointments.html",
    "patients.html",
    "medical-records.html",
    "medications.html",
    "communication.html",
    "staff-reports.html",
  ],
  [STAFF_ROLES.THERAPIST]: [
    "staff-dashboard.html",
    "patients.html",
    "therapy-sessions.html",
    "rehab-plans.html",
    "communication.html",
    "therapist-reports.html",
  ],
};

export function homePageForRole(role) {
  return normalizeStaffRole(role) === STAFF_ROLES.ADMIN
    ? "dashboard.html"
    : "staff-dashboard.html";
}

export function allowedPagesForRole(role) {
  const normalized = normalizeStaffRole(role);
  return PAGE_ACCESS[normalized] || [];
}

export function canAccessPage(role, pageName) {
  const pages = allowedPagesForRole(role);
  if (pages.length === 0) return false;
  const normalizedPage = String(pageName || "").trim().toLowerCase();
  return pages.some((page) => page.toLowerCase() === normalizedPage);
}

export function isAdmin(role) {
  return normalizeStaffRole(role) === STAFF_ROLES.ADMIN;
}

export function isDoctor(role) {
  return normalizeStaffRole(role) === STAFF_ROLES.DOCTOR;
}

export function isTherapist(role) {
  return normalizeStaffRole(role) === STAFF_ROLES.THERAPIST;
}

/** All patients for medication / medical-records pages (doctors see every patient in Firestore). */
export function filterPatientsForClinicalPages(patients, profile) {
  return filterPatientsForRole(patients, profile);
}

/** Filters patient rows to those visible for the signed-in staff member. */
export function filterPatientsForRole(patients, profile) {
  const role = normalizeStaffRole(profile?.role);
  const uid = String(profile?.uid || "").trim();
  // Admin, Doctor, and Therapist can see all patients
  if (!role || role === STAFF_ROLES.ADMIN || role === STAFF_ROLES.DOCTOR || role === STAFF_ROLES.THERAPIST) {
    return patients;
  }
  // If caregiver (or other future roles), scope appropriately
  return patients.filter((patient) => patient.assignedCaregiverId === uid);
}

export function roleDisplayLabel(role) {
  const normalized = normalizeStaffRole(role);
  switch (normalized) {
    case STAFF_ROLES.ADMIN:
      return "Administrator";
    case STAFF_ROLES.DOCTOR:
      return "Doctor";
    case STAFF_ROLES.THERAPIST:
      return "Therapist";
    case "caregiver":
      return "Caregiver";
    default:
      return String(role || "Staff").trim() || "Staff";
  }
}
