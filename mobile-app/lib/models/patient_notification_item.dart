import 'package:cloud_firestore/cloud_firestore.dart';

enum PatientNotificationKind { delivered, scheduled }

enum PatientNotificationStatus { delivered, pending, completed, missed, upcoming }

class PatientNotificationItem {
  const PatientNotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.timeLabel,
    required this.dateLabel,
    required this.kind,
    required this.status,
    this.scheduledTime,
    this.medicationName,
    this.reminderId,
    this.medicationId,
    this.isUnreadInFirestore = false,
    required this.sortMillis,
  });

  final String id;
  final String title;
  final String body;
  final String timeLabel;
  final String dateLabel;
  final PatientNotificationKind kind;
  final PatientNotificationStatus status;
  final Timestamp? scheduledTime;
  final String? medicationName;
  final String? reminderId;
  final String? medicationId;
  final bool isUnreadInFirestore;
  final int sortMillis;
}
