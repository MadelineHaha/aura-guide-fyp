import { collection, getDocs } from "https://www.gstatic.com/firebasejs/11.6.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { HEALTHCARE_STAFF_COLLECTION } from "./staff-auth.js";

export async function fetchActiveStaff() {
  const snap = await getDocs(collection(db, HEALTHCARE_STAFF_COLLECTION));
  return snap.docs
    .map((docSnap) => {
      const data = docSnap.data();
      return {
        uid: docSnap.id,
        staffID: data.staffID || "",
        name: data.name || "",
        role: data.role || "",
        status: data.status || "",
      };
    })
    .filter((staff) => staff.status === "Active" && staff.staffID)
    .sort((a, b) => a.name.localeCompare(b.name));
}
