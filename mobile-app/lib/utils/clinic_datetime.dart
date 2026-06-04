import 'package:cloud_firestore/cloud_firestore.dart';

/// Clinic wall-clock time (Malaysia, UTC+8). Firestore stores UTC instants.
class ClinicDateTime {
  ClinicDateTime._();

  static const Duration _offset = Duration(hours: 8);

  /// Parses `dateTime` / `scheduledAt` from Firestore into clinic-local components.
  static DateTime? fromFirestore(dynamic value) {
    int? epochMs;
    if (value is Timestamp) {
      epochMs = value.millisecondsSinceEpoch;
    } else if (value is DateTime) {
      epochMs = value.toUtc().millisecondsSinceEpoch;
    } else if (value is int) {
      epochMs = value;
    } else if (value is num) {
      epochMs = value.toInt();
    }
    if (epochMs == null) return null;

    final shifted = DateTime.fromMillisecondsSinceEpoch(epochMs, isUtc: true)
        .add(_offset);
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
    );
  }

  /// Writes a clinic-local wall time to Firestore as a UTC instant.
  static Timestamp toTimestamp(DateTime clinicLocal) {
    final utc = DateTime.utc(
      clinicLocal.year,
      clinicLocal.month,
      clinicLocal.day,
      clinicLocal.hour,
      clinicLocal.minute,
      clinicLocal.second,
    ).subtract(_offset);
    return Timestamp.fromMillisecondsSinceEpoch(utc.millisecondsSinceEpoch);
  }

  static DateTime clinicDayStart(DateTime calendarDate) {
    return DateTime(
      calendarDate.year,
      calendarDate.month,
      calendarDate.day,
    );
  }

  static bool isAfterNow(DateTime clinicLocal) {
    return toTimestamp(clinicLocal).compareTo(Timestamp.now()) > 0;
  }

  static bool isBeforeNow(DateTime clinicLocal) {
    return toTimestamp(clinicLocal).compareTo(Timestamp.now()) < 0;
  }

  /// Current time as clinic-local wall clock (for UI labels).
  static DateTime nowClinic() {
    final shifted = DateTime.now().toUtc().add(_offset);
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
    );
  }
}
