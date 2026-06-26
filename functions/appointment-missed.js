const admin = require("firebase-admin");

const db = admin.firestore();

const MISSED_ELIGIBLE_STATUSES = new Set(["scheduled", "pending", "rescheduled"]);

function normalizeStatus(status) {
  const value = String(status || "Scheduled").trim().toLowerCase();
  if (value === "cancelled") return "cancelled";
  if (value === "done" || value === "completed") return "done";
  if (value === "missed") return "missed";
  if (value === "rescheduled") return "rescheduled";
  if (value === "pending") return "pending";
  return "scheduled";
}

function timestampToDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

/**
 * Marks appointments whose dateTime has passed and were never completed as Missed.
 * @returns {Promise<number>} number of documents updated
 */
async function markOverdueAppointmentsAsMissed() {
  const now = new Date();
  const snap = await db.collection("appointments").get();
  let updated = 0;
  let batch = db.batch();
  let batchCount = 0;

  for (const docSnap of snap.docs) {
    const data = docSnap.data() || {};
    if (!MISSED_ELIGIBLE_STATUSES.has(normalizeStatus(data.status))) continue;

    const apptTime = timestampToDate(data.dateTime || data.scheduledAt);
    if (!apptTime || apptTime >= now) continue;

    batch.update(docSnap.ref, {
      status: "Missed",
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    updated += 1;
    batchCount += 1;

    if (batchCount >= 400) {
      await batch.commit();
      batch = db.batch();
      batchCount = 0;
    }
  }

  if (batchCount > 0) {
    await batch.commit();
  }

  return updated;
}

module.exports = {
  markOverdueAppointmentsAsMissed,
};
