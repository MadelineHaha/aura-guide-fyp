import { fetchSignInMethodsForEmail } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-auth.js";
import { httpsCallable } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-functions.js";
import {
  collection,
  getDocs,
  limit,
  query,
  where,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { auth, db, functions } from "./firebase.js";

export const DUPLICATE_EMAIL_MESSAGE =
  "This email is already registered in the system (patient, staff, or caregiver). Please use a different email.";

const COLLECTION_CHECKS = [
  { collection: "users", label: "patient" },
  { collection: "healthcarestaff", label: "staff member" },
  { collection: "caregiver", label: "caregiver" },
  { collection: "caregivers", label: "caregiver" },
];

function normalizeEmail(email) {
  return String(email || "").trim().toLowerCase();
}

function isPermissionDenied(error) {
  const code = String(error?.code || "");
  const message = String(error?.message || "").toLowerCase();
  return (
    code === "permission-denied" ||
    message.includes("missing or insufficient permissions")
  );
}

/** Server-side duplicate check via Cloud Function (preferred). */
async function checkEmailViaCallable(email) {
  const checkInviteEmail = httpsCallable(functions, "checkInviteEmail");
  const result = await checkInviteEmail({ email });
  const data = result?.data || {};
  if (data.available === false) {
    return {
      message: data.message || DUPLICATE_EMAIL_MESSAGE,
    };
  }
  return null;
}

/** Browser fallback when the checkInviteEmail function is not deployed. */
async function findEmailRegistrationConflictOffline(email) {
  const normalized = normalizeEmail(email);
  if (!normalized || !normalized.includes("@")) {
    return null;
  }

  for (const { collection: collectionName, label } of COLLECTION_CHECKS) {
    try {
      const snap = await getDocs(
        query(
          collection(db, collectionName),
          where("email", "==", normalized),
          limit(1),
        ),
      );
      if (!snap.empty) {
        return {
          collection: collectionName,
          label,
          message: `This email is already registered as a ${label}. Please use a different email.`,
        };
      }
    } catch (error) {
      if (isPermissionDenied(error)) {
        console.warn(`Skipped client email check for ${collectionName}:`, error);
        continue;
      }
      throw error;
    }
  }

  try {
    const methods = await fetchSignInMethodsForEmail(auth, normalized);
    if (methods.length > 0) {
      return {
        collection: "authentication",
        label: "account",
        message: DUPLICATE_EMAIL_MESSAGE,
      };
    }
  } catch (error) {
    console.warn("Could not verify email against Firebase Authentication:", error);
  }

  return null;
}

/** Throws a user-facing error when the email is already registered. */
export async function assertEmailAvailableForInvite(email) {
  const normalized = normalizeEmail(email);
  if (!normalized || !normalized.includes("@")) {
    return;
  }

  try {
    const callableConflict = await checkEmailViaCallable(normalized);
    if (callableConflict) {
      throw new Error(callableConflict.message || DUPLICATE_EMAIL_MESSAGE);
    }
    return;
  } catch (error) {
    const code = String(error?.code || "");
    const cleanCode = code.startsWith("functions/") ? code.slice(10) : code;
    if (cleanCode === "not-found" || cleanCode === "unavailable" || cleanCode === "internal") {
      const offlineConflict = await findEmailRegistrationConflictOffline(normalized);
      if (offlineConflict) {
        throw new Error(offlineConflict.message || DUPLICATE_EMAIL_MESSAGE);
      }
      return;
    }
    if (isPermissionDenied(error)) {
      throw new Error(
        "Could not verify this email. Deploy Cloud Functions and Firestore rules, then try again.",
      );
    }
    if (error?.message) {
      throw error;
    }
    throw new Error("Could not verify this email address.");
  }
}
