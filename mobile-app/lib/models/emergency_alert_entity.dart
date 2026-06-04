import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/clinic_datetime.dart';

/// Table 4.7 — EmergencyAlert entity (`emergencyalerts` collection).
class EmergencyAlertEntity {
  const EmergencyAlertEntity({
    required this.alertId,
    required this.dateTime,
    required this.location,
    required this.alertType,
    required this.status,
    required this.userId,
    this.resolutionNotes = '',
    this.staffId = '',
    this.dateTimeLabel,
  });

  static final RegExp alertIdPattern = RegExp(r'^E\d{5}$');

  static const alertTypeManualSos = 'Manual SOS';
  static const alertTypeFallDetection = 'Fall Detection';

  static const statusActive = 'Active';
  static const statusResolved = 'Resolved';

  final String alertId;
  final Timestamp dateTime;
  final String location;
  final String alertType;
  final String status;
  final String resolutionNotes;
  final String userId;
  final String staffId;
  final String? dateTimeLabel;

  bool get isActive => status == statusActive;

  static String formatClinicDateTime(DateTime clinicLocal) {
    final y = clinicLocal.year;
    final m = clinicLocal.month.toString().padLeft(2, '0');
    final d = clinicLocal.day.toString().padLeft(2, '0');
    final hh = clinicLocal.hour.toString().padLeft(2, '0');
    final mm = clinicLocal.minute.toString().padLeft(2, '0');
    final ss = clinicLocal.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  Map<String, dynamic> toFirestoreMap() {
    final clinic = ClinicDateTime.fromFirestore(dateTime) ?? ClinicDateTime.nowClinic();
    return {
      'alertId': alertId,
      'dateTime': dateTime,
      'dateTimeLabel': dateTimeLabel ?? formatClinicDateTime(clinic),
      'location': location,
      'alertType': alertType,
      'status': status,
      'resolutionNotes': resolutionNotes,
      'userId': userId,
      'staffId': staffId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  static EmergencyAlertEntity? fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    final alertId = (data['alertId'] as String?)?.trim() ?? docId;
    if (!alertIdPattern.hasMatch(alertId)) return null;

    final ts = data['dateTime'];
    if (ts is! Timestamp) return null;

    final userId = (data['userId'] as String?)?.trim() ??
        (data['userID'] as String?)?.trim() ??
        '';
    if (userId.isEmpty) return null;

    return EmergencyAlertEntity(
      alertId: alertId,
      dateTime: ts,
      location: (data['location'] as String?)?.trim() ?? '',
      alertType: (data['alertType'] as String?)?.trim() ?? alertTypeManualSos,
      status: (data['status'] as String?)?.trim() ?? statusActive,
      resolutionNotes: (data['resolutionNotes'] as String?)?.trim() ?? '',
      userId: userId,
      staffId: (data['staffId'] as String?)?.trim() ??
          (data['staffID'] as String?)?.trim() ??
          '',
      dateTimeLabel: (data['dateTimeLabel'] as String?)?.trim(),
    );
  }
}
