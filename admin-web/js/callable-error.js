/** Maps Firebase callable / Identity Toolkit errors to user-facing text. */
export function formatCallableError(error, fallback = "Could not complete the request.") {
  const code = String(error?.code || "");
  const cleanCode = code.startsWith("functions/") ? code.slice(10) : code;
  const details = typeof error?.details === "string" ? error.details.trim() : "";
  const rawMessage = String(error?.message || "").trim();
  const message = details || rawMessage;

  if (cleanCode === "not-found" || cleanCode === "unavailable") {
    return "Cloud Functions are not deployed yet. Deploy: firebase deploy --only functions:inviteHealthcareStaff,functions:checkInviteEmail,firestore:rules";
  }
  if (cleanCode === "permission-denied") {
    return "You do not have permission to perform this action. Sign in as an active admin.";
  }
  if (cleanCode === "unauthenticated") {
    return "Your session expired. Sign in again and retry.";
  }
  if (cleanCode === "already-exists") {
    return message && message.toLowerCase() !== "internal"
      ? message
      : "An account with this email already exists.";
  }
  if (cleanCode === "invalid-argument" && message) {
    return message;
  }
  if (cleanCode === "failed-precondition" && message) {
    return message;
  }
  if (cleanCode === "internal") {
    if (message && message.toLowerCase() !== "internal") {
      return message;
    }
    return "The server invite function failed. Check Firebase logs or deploy the latest functions.";
  }
  if (message && message.toLowerCase() !== "internal") {
    return message;
  }
  return fallback;
}

export function isFirestorePermissionDenied(error) {
  const code = String(error?.code || "");
  const message = String(error?.message || "").toLowerCase();
  return (
    code === "permission-denied" ||
    message.includes("missing or insufficient permissions")
  );
}

export function shouldFallbackToDirectInvite(error) {
  const code = String(error?.code || "");
  const cleanCode = code.startsWith("functions/") ? code.slice(10) : code;
  return cleanCode === "not-found" || cleanCode === "unavailable" || cleanCode === "internal";
}

export function humanizeIdentityError(code) {
  const value = String(code || "").trim();
  switch (value) {
    case "EMAIL_EXISTS":
      return "An account with this email already exists.";
    case "OPERATION_NOT_ALLOWED":
    case "auth/operation-not-allowed":
      return "Email/Password sign-up is disabled in Firebase Authentication. Make sure you saved the changes in your Firebase Console for project 'auraguide-46d15'. Both 'Email/Password' AND 'Email link' switches must be enabled.";
    case "INVALID_EMAIL":
      return "Please enter a valid email address.";
    case "TOO_MANY_ATTEMPTS_TRY_LATER":
      return "Too many attempts. Wait a few minutes and try again.";
    default:
      return value || "Could not complete the authentication request.";
  }
}
