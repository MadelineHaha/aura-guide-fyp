import {
  isSignInWithEmailLink,
  signInWithEmailLink,
  updatePassword,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-auth.js";
import {
  doc,
  getDoc,
  deleteDoc,
  runTransaction,
  serverTimestamp,
  updateDoc,
} from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { auth, db } from "./firebase.js";
import { STAFF_COUNTER_PATH, formatStaffId } from "./staff-id-service.js";
import { CAREGIVER_COUNTER_PATH, formatCaregiverId } from "./caregiver-id-service.js";

const HEALTHCARE_STAFF_COLLECTION = "healthcarestaff";
const CAREGIVER_COLLECTION = "caregiver";

const form = document.getElementById("accept-form");
const passwordInput = document.getElementById("password");
const submitBtn = document.getElementById("submit-btn");
const errorEl = document.getElementById("form-error");
const successEl = document.getElementById("form-success");
const loadingContainer = document.getElementById("loading-container");

let inviteData = null;
let inviteId = null;

async function init() {
  const urlParams = new URLSearchParams(window.location.search);
  inviteId = urlParams.get("inviteId");

  if (!inviteId) {
    showError("Invalid invitation link.");
    return;
  }

  if (isSignInWithEmailLink(auth, window.location.href)) {
    try {
      const inviteRef = doc(db, "invitations", inviteId);
      const inviteSnap = await getDoc(inviteRef);
      
      if (!inviteSnap.exists()) {
        showError("Invitation not found or already used.");
        return;
      }
      
      inviteData = inviteSnap.data();
      
      // Sign in the user
      await signInWithEmailLink(auth, inviteData.email, window.location.href);
      
      // Setup UI
      loadingContainer.hidden = true;
      form.hidden = false;
    } catch (error) {
      showError(error.message || "Could not sign you in with this link.");
    }
  } else {
    showError("This link is not valid for email sign in.");
  }
}

function showError(msg) {
  loadingContainer.hidden = true;
  form.hidden = true;
  errorEl.textContent = msg;
  errorEl.hidden = false;
  successEl.hidden = true;
}

function showSuccess(msg) {
  errorEl.hidden = true;
  successEl.textContent = msg;
  successEl.hidden = false;
}

form.addEventListener("submit", async (e) => {
  e.preventDefault();
  const password = passwordInput.value.trim();
  
  if (password.length < 8) {
    errorEl.textContent = "Password must be at least 8 characters.";
    errorEl.hidden = false;
    return;
  }
  
  errorEl.hidden = true;
  submitBtn.disabled = true;
  submitBtn.textContent = "Creating Account...";
  
  try {
    const user = auth.currentUser;
    if (!user) throw new Error("You are not signed in. Please reload the page.");
    
    // Set Password
    await updatePassword(user, password);
    
    // Create Profile Document
    if (inviteData.role === "caregiver") {
      await createCaregiverProfile(user.uid, inviteData);
    } else {
      await createStaffProfile(user.uid, inviteData);
    }
    
    // Clean up invitation
    await deleteDoc(doc(db, "invitations", inviteId));
    
    showSuccess("Account created successfully! Redirecting...");
    
    // Redirect
    setTimeout(() => {
      if (inviteData.role === "caregiver") {
        // Doesn't normally login to staff portal, but if they do, fallback to patients or something
        window.location.href = "login.html";
      } else {
        window.location.href = "staff-dashboard.html";
      }
    }, 1500);
    
  } catch (err) {
    submitBtn.disabled = false;
    submitBtn.textContent = "Set Password & Create Account";
    errorEl.textContent = err.message || "Failed to create account.";
    errorEl.hidden = false;
  }
});

async function createStaffProfile(uid, data) {
  const staffRef = doc(db, HEALTHCARE_STAFF_COLLECTION, uid);
  const counterRef = doc(db, ...STAFF_COUNTER_PATH);
  
  await runTransaction(db, async (transaction) => {
    const counterSnap = await transaction.get(counterRef);
    const next = counterSnap.exists() ? Number(counterSnap.data().next) || 1 : 1;
    const assignedStaffId = formatStaffId(next);

    transaction.set(counterRef, { next: next + 1 }, { merge: true });
    transaction.set(staffRef, {
      staffID: assignedStaffId,
      name: data.name,
      email: data.email,
      role: data.role,
      phone: data.phone || "",
      status: "Active",
      authUid: uid,
      invitePending: false, // Account is now fully setup
      accountActivated: true,
      inviteId: inviteId, // Included to satisfy security rules
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
  });
}

async function createCaregiverProfile(uid, data) {
  const caregiverRef = doc(db, CAREGIVER_COLLECTION, uid);
  const counterRef = doc(db, ...CAREGIVER_COUNTER_PATH);
  
  let assignedCaregiverId = "";
  
  await runTransaction(db, async (transaction) => {
    const counterSnap = await transaction.get(counterRef);
    const next = counterSnap.exists() ? Number(counterSnap.data().next) || 1 : 1;
    assignedCaregiverId = formatCaregiverId(next);
    
    const connectedUserIds = (data.connectedPatients || []).map((entry) => entry.userId);

    transaction.set(counterRef, { next: next + 1 }, { merge: true });
    transaction.set(caregiverRef, {
      caregiverID: assignedCaregiverId,
      name: data.name,
      email: data.email,
      phone: data.phone || "",
      role: "caregiver",
      status: "Active",
      authUid: uid,
      invitePending: false,
      accountActivated: true,
      inviteId: inviteId, // Included to satisfy security rules
      connectedUserIds: connectedUserIds,
      connectedPatients: data.connectedPatients || [],
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    });
  });
  
  // Sync Patient Caregiver Links
  if (data.connectedPatients && data.connectedPatients.length > 0) {
    try {
      for (const patient of data.connectedPatients) {
        await updateDoc(doc(db, "users", patient.patientDocId), {
          assignedCaregiverId: uid,
          assignedCaregiverName: data.name,
          assignedCaregiverPublicId: assignedCaregiverId,
          updatedAt: serverTimestamp(),
        });
      }
    } catch (e) {
      console.error("Failed to sync patient caregiver links", e);
    }
  }
}

init();
