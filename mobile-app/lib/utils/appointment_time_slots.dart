import 'package:cloud_firestore/cloud_firestore.dart';

import 'clinic_datetime.dart';

/// Firestore time slots use `dateTime` (Timestamp), not plain text labels.
class AppointmentTimeSlots {
  AppointmentTimeSlots._();

  static DateTime? parseDateTimeValue(dynamic value) =>
      ClinicDateTime.fromFirestore(value);

  /// Maps a template [dateTime] onto [calendarDate] (same clock time).
  static DateTime onCalendarDate(DateTime template, DateTime calendarDate) {
    return DateTime(
      calendarDate.year,
      calendarDate.month,
      calendarDate.day,
      template.hour,
      template.minute,
    );
  }

  static bool sameMinute(DateTime a, DateTime b) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day &&
        a.hour == b.hour &&
        a.minute == b.minute;
  }

  static String formatTimeLabel(DateTime dateTime) {
    final hour = dateTime.hour;
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:$minute $period';
  }

  static void sortByTime(List<DateTime> slots) {
    slots.sort((a, b) => a.compareTo(b));
  }

  static List<DateTime> dedupeMinutes(List<DateTime> slots) {
    final seen = <String>{};
    final out = <DateTime>[];
    for (final slot in slots) {
      final key = '${slot.year}-${slot.month}-${slot.day}-'
          '${slot.hour}-${slot.minute}';
      if (seen.add(key)) out.add(slot);
    }
    return out;
  }

  /// Reads slot `dateTime` values from a Firestore array field.
  static List<DateTime> parseSlotListForDate(dynamic raw, DateTime calendarDate) {
    if (raw is! List) return [];

    final slots = <DateTime>[];
    for (final item in raw) {
      DateTime? parsed;
      if (item is Timestamp || item is DateTime) {
        parsed = parseDateTimeValue(item);
      } else if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        parsed = parseDateTimeValue(map['dateTime'] ?? map['scheduledAt']);
      } else if (item is String) {
        parsed = _parseLegacyLabelOnDate(item, calendarDate);
      }

      if (parsed == null) continue;

      final onDay = onCalendarDate(parsed, calendarDate);
      slots.add(onDay);
    }
    return dedupeMinutes(slots);
  }

  static DateTime? _parseLegacyLabelOnDate(String label, DateTime calendarDate) {
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*(AM|PM)$',
      caseSensitive: false,
    ).firstMatch(label.trim());
    if (match == null) return null;

    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final period = match.group(3)!.toUpperCase();
    if (period == 'PM' && hour != 12) hour += 12;
    if (period == 'AM' && hour == 12) hour = 0;

    return DateTime(
      calendarDate.year,
      calendarDate.month,
      calendarDate.day,
      hour,
      minute,
    );
  }

  static const clinicSlotHours = [9, 10, 11, 13, 14, 15, 16, 17, 18];

  /// Standard clinic hours: 9–11 AM and 1–6 PM.
  static List<DateTime> clinicSlotsOnDate(DateTime calendarDate) {
    return clinicSlotHours
        .map(
          (h) => DateTime(
            calendarDate.year,
            calendarDate.month,
            calendarDate.day,
            h,
            0,
          ),
        )
        .toList();
  }

  static List<DateTime> defaultSlotsOnDate(DateTime calendarDate) =>
      clinicSlotsOnDate(calendarDate);
}
