/// Today's medication row (Medication + MedicationReminder join for UI).
class MedicationItem {
  const MedicationItem({
    required this.reminderId,
    required this.medicationId,
    required this.name,
    required this.scheduledTime,
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
  final String dosage;
  final String frequency;
  final String instructions;
  final bool takenToday;
  final String reminderMessage;
  final String status;
}
