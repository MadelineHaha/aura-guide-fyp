class TherapySessionItem {
  const TherapySessionItem({
    required this.id,
    required this.patientId,
    required this.staffId,
    required this.appointmentType,
    required this.dateTime,
    required this.status,
    required this.sessionName,
    required this.sessionDuration,
    required this.sessionRemarks,
    required this.sessionStatus,
    required this.sessionOutcome,
    required this.notes,
  });

  final String id;
  final String patientId;
  final String staffId;
  final String appointmentType;
  final DateTime dateTime;
  final String status;
  final String sessionName;
  final String sessionDuration;
  final String sessionRemarks;
  final String sessionStatus;
  final String sessionOutcome;
  final String notes;

  bool get isTherapyType {
    final type = appointmentType.trim().toLowerCase();
    return type == 'therapy session' || type == 'therapist session';
  }

  bool get isPlanned {
    final value = status.trim().toLowerCase();
    return value == 'scheduled' || value == 'pending';
  }

  bool get isCompleted {
    final value = status.trim().toLowerCase();
    return value == 'done' || value == 'completed';
  }
}
