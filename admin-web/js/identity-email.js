import { firebaseConfig } from "./firebase-config.js";
import { humanizeIdentityError } from "./callable-error.js";

/** Sends Firebase password-reset / account-setup email to a new staff or caregiver. */
export async function sendPasswordSetupEmail(email, continueUrl) {
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:sendOobCode?key=${firebaseConfig.apiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        requestType: "PASSWORD_RESET",
        email: String(email || "").trim().toLowerCase(),
        continueUrl: continueUrl || undefined,
      }),
    },
  );

  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(
      humanizeIdentityError(payload?.error?.message || "EMAIL_SEND_FAILED"),
    );
  }
}

import { auth } from "./firebase.js";
import { sendSignInLinkToEmail } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-auth.js";

/** Sends Firebase Email Link Authentication (passwordless sign-in) for invitations. */
export async function sendInviteLinkEmail(email, continueUrl) {
  const actionCodeSettings = {
    url: continueUrl,
    handleCodeInApp: true,
  };

  try {
    await sendSignInLinkToEmail(auth, email, actionCodeSettings);
  } catch (error) {
    throw new Error(
      humanizeIdentityError(error?.code || "EMAIL_SEND_FAILED"),
    );
  }
}
