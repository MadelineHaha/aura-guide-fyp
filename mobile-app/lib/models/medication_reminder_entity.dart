import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/clinic_datetime.dart';

/// Table 4.6 — MedicationReminder entity (`medicationreminders` collection).
class MedicationReminderEntity {
  const MedicationReminderEntity({
    required this.reminderId,
    required this.reminderTime,
    required this.reminderType,
    required this.reminderMessage,
    required this.repeatPattern,
    required this.status,
    required this.medicationId,
    required this.userId,
    required this.staffId,
    this.reminderTimeLabel,
    this.completedDate = '',
  });

  static final RegExp reminderIdPattern = RegExp(r'^R\d{5}$');

  static const typeVoice = 'Voice';
  static const typeVibration = 'Vibration';
  static const typeNotification = 'Notification';

  static const statusPending = 'Pending';
  static const statusCompleted = 'Completed';
  static const statusMissed = 'Missed';

  static const repeatDaily = 'Daily';

  final String reminderId;
  final Timestamp reminderTime;
  final String reminderType;
  final String reminderMessage;
  final String repeatPattern;
  final String status;
  final String medicationId;
  final String userId;
  final String staffId;
  final String? reminderTimeLabel;
  /// Clinic date `YYYY-MM-DD` when patient marked Completed (app field).
  final String completedDate;

  bool isTakenOnDate(String yyyyMmDd) {
    return status == statusCompleted && completedDate == yyyyMmDd;
  }

  static String formatClockLabel(Timestamp ts) {
    final clinic = ClinicDateTime.fromFirestore(ts);
    if (clinic == null) return '—';
    final hour = clinic.hour;
    final minute = clinic.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:$minute $period';
  }

  static String formatDateTimeLabel(Timestamp ts) {
    final clinic = ClinicDateTime.fromFirestore(ts);
    if (clinic == null) return '';
    final y = clinic.year;
    final m = clinic.month.toString().padLeft(2, '0');
    final d = clinic.day.toString().padLeft(2, '0');
    final hh = clinic.hour.toString().padLeft(2, '0');
    final mm = clinic.minute.toString().padLeft(2, '0');
    final ss = clinic.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  static MedicationReminderEntity? fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    final reminderId = (data['reminderId'] as String?)?.trim() ?? docId;
    if (!reminderIdPattern.hasMatch(reminderId)) return null;

    final reminderTime = data['reminderTime'];
    if (reminderTime is! Timestamp) return null;

    final medicationId = (data['medicationId'] as String?)?.trim() ?? '';
    final userId = (data['userId'] as String?)?.trim() ??
        (data['userID'] as String?)?.trim() ??
        '';
    if (medicationId.isEmpty || userId.isEmpty) return null;

    return MedicationReminderEntity(
      reminderId: reminderId,
      reminderTime: reminderTime,
      reminderType:
          (data['reminderType'] as String?)?.trim() ?? typeNotification,
      reminderMessage: (data['reminderMessage'] as String?)?.trim() ?? '',
      repeatPattern: (data['repeatPattern'] as String?)?.trim() ?? repeatDaily,
      status: (data['status'] as String?)?.trim() ?? statusPending,
      medicationId: medicationId,
      userId: userId,
      staffId: (data['staffId'] as String?)?.trim() ??
          (data['staffID'] as String?)?.trim() ??
          '',
      reminderTimeLabel: (data['reminderTimeLabel'] as String?)?.trim(),
      completedDate: (data['completedDate'] as String?)?.trim() ?? '',
    );
  }
}
