/** Clinic appointment hours shared with the mobile app. */
export const CLINIC_SLOT_HOURS = [9, 10, 11, 13, 14, 15, 16, 17, 18];

const BLOCKING_STATUSES = new Set(["pending", "scheduled", "rescheduled"]);

export function formatSlotLabel(hour, minute = 0) {
  const period = hour >= 12 ? "PM" : "AM";
  const h12 = hour % 12 === 0 ? 12 : hour % 12;
  const mm = String(minute).padStart(2, "0");
  return `${h12}:${mm} ${period}`;
}

export function timeInputValueForHour(hour) {
  return `${String(hour).padStart(2, "0")}:00`;
}

export function dateToInputValue(date) {
  const y = date.getFullYear();
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

export function clinicSlotsForDateString(dateStr) {
  const [y, m, d] = dateStr.split("-").map(Number);
  if (!y || !m || !d) return [];

  return CLINIC_SLOT_HOURS.map((hour) => {
    const value = timeInputValueForHour(hour);
    return {
      hour,
      minute: 0,
      value,
      label: formatSlotLabel(hour),
      date: new Date(y, m - 1, d, hour, 0, 0, 0),
    };
  });
}

export function isClinicTimeValue(timeStr) {
  const value = String(timeStr || "").trim();
  return CLINIC_SLOT_HOURS.some((hour) => timeInputValueForHour(hour) === value);
}

export function sameMinute(a, b) {
  if (!a || !b) return false;
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate() &&
    a.getHours() === b.getHours() &&
    a.getMinutes() === b.getMinutes()
  );
}

export function isBlockingAppointmentStatus(status) {
  return BLOCKING_STATUSES.has(String(status || "").trim().toLowerCase());
}

export function bookedTimesForStaffOnDate(
  appointments,
  staffId,
  dateStr,
  excludeAppointmentId = null,
) {
  const trimmedStaffId = String(staffId || "").trim();
  if (!trimmedStaffId || !dateStr) return [];

  const booked = [];
  for (const apt of appointments || []) {
    if (excludeAppointmentId && apt.id === excludeAppointmentId) continue;
    if (String(apt.staffId || "").trim() !== trimmedStaffId) continue;
    if (!isBlockingAppointmentStatus(apt.status)) continue;
    if (!apt.dateTime) continue;
    if (dateToInputValue(apt.dateTime) !== dateStr) continue;
    booked.push(apt.dateTime);
  }
  return booked;
}

export function getAvailableClinicSlots({
  appointments = [],
  staffId,
  dateStr,
  excludeAppointmentId = null,
  requireFuture = true,
}) {
  const candidates = clinicSlotsForDateString(dateStr);
  const booked = bookedTimesForStaffOnDate(
    appointments,
    staffId,
    dateStr,
    excludeAppointmentId,
  );
  const now = new Date();

  return candidates.filter((slot) => {
    if (requireFuture && slot.date <= now) return false;
    return !booked.some((taken) => sameMinute(taken, slot.date));
  });
}

export function assertClinicSlotAvailable({
  appointments = [],
  staffId,
  date,
  time,
  excludeAppointmentId = null,
  requireFuture = true,
}) {
  if (!isClinicTimeValue(time)) {
    throw new Error("Please select a valid clinic time slot.");
  }

  const available = getAvailableClinicSlots({
    appointments,
    staffId,
    dateStr: date,
    excludeAppointmentId,
    requireFuture,
  });

  if (!available.some((slot) => slot.value === time)) {
    throw new Error(
      "This time slot is no longer available. Please choose another time.",
    );
  }
}
