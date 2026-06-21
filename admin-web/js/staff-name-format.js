const EN_PREFIX = {
  doctor: "Doctor",
  therapist: "Therapist",
  caregiver: "Caregiver",
};

const MS_PREFIX = {
  doctor: "Doktor",
  therapist: "Ahli Terapi",
  caregiver: "Penjaga",
};

const ZH_SUFFIX = {
  doctor: "医生",
  therapist: "治疗师",
  caregiver: "护理员",
};

export function normalizeStaffRole(role) {
  const value = String(role || "").trim().toLowerCase();
  if (!value) return null;
  if (value.includes("doctor") || value === "dr" || value === "physician") {
    return "doctor";
  }
  if (value.includes("therapist") || value.includes("therapy")) {
    return "therapist";
  }
  if (value.includes("caregiver") || value.includes("nurse")) {
    return "caregiver";
  }
  return null;
}

export function baseStaffName(rawName) {
  let name = String(rawName || "").trim();
  if (!name) return "";

  for (const suffix of Object.values(ZH_SUFFIX)) {
    if (name.endsWith(suffix) && name.length > suffix.length) {
      name = name.slice(0, -suffix.length).trim();
      break;
    }
  }

  const prefixes = [
    "Doctor ",
    "Therapist ",
    "Caregiver ",
    "Dr. ",
    "Dr ",
    "Doktor ",
    "Doktor. ",
    "Ahli Terapi ",
    "Penjaga ",
  ];
  for (const prefix of prefixes) {
    if (name.startsWith(prefix)) {
      return name.slice(prefix.length).trim();
    }
  }

  return name;
}

export function formatStaffNameByRole(name, role, languageCode = "en") {
  const baseName = baseStaffName(name);
  if (!baseName) return "";
  const category = normalizeStaffRole(role);
  if (!category) return baseName;

  if (languageCode === "zh") {
    return `${baseName}${ZH_SUFFIX[category]}`;
  }
  if (languageCode === "ms") {
    return `${MS_PREFIX[category]} ${baseName}`;
  }
  return `${EN_PREFIX[category]} ${baseName}`;
}

export function formatStaffDisplayName(staff, languageCode = "en") {
  const fallbackId = staff?.staffID || staff?.staffId || "—";
  const baseName = baseStaffName(staff?.name || "");
  if (!baseName) return fallbackId;
  return formatStaffNameByRole(baseName, staff?.role, languageCode);
}
