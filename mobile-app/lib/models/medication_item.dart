import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/clinic_datetime.dart';

/// Today's medication row (Medication + MedicationReminder join for UI).
class MedicationItem {
  const MedicationItem({
    required this.reminderId,
    required this.medicationId,
    required this.name,
    required this.scheduledTime,
    required this.reminderTime,
    required this.dosage,
    required this.frequency,
    required this.instructions,
    required this.takenToday,
    required this.reminderMessage,
    required this.status,
  });

  final String reminderId;
  final String medicationId;
  final String name;
  /// Display time e.g. `08:00 AM`.
  final String scheduledTime;
  final Timestamp reminderTime;
  final String dosage;
  final String frequency;
  final String instructions;
  final bool takenToday;
  final String reminderMessage;
  final String status;

  /// True when today's scheduled time has passed and the dose is not taken.
  bool get isOverdue {
    if (takenToday) return false;

    final schedule = ClinicDateTime.fromFirestore(reminderTime);
    if (schedule == null) return false;

    final now = ClinicDateTime.nowClinic();
    final scheduledToday = DateTime(
      now.year,
      now.month,
      now.day,
      schedule.hour,
      schedule.minute,
    );
    return now.isAfter(scheduledToday);
  }
}
