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
  });

  static final RegExp alertIdPattern = RegExp(r'^E\d{5}$');

  static const alertTypeManualSos = 'Manual SOS';
  static const alertTypeFallDetection = 'Fall Detection';
  static const alertTypeFallDetectionTest = 'Fall Detection Test';

  static const statusActive = 'Active';
  static const statusResponded = 'Responded';
  static const statusResolved = 'Resolved';

  /// ERD `AlertID` — document id, format `ENNNNN` (e.g. E00001).
  final String alertId;

  /// ERD `DateTime` — `YYYY-MM-DD HH:mm:ss`.
  final String dateTime;

  /// ERD `Location` — GPS coordinates string.
  final String location;

  /// ERD `AlertType` — e.g. Manual SOS, Fall Detection.
  final String alertType;

  /// ERD `Status` — Active, Responded, or Resolved.
  final String status;

  /// ERD `ResolutionNotes`.
  final String resolutionNotes;

  /// ERD `UserID` — linked patient, format `UNNNNN`.
  final String userId;

  /// ERD `StaffID` — linked staff, format `SNNNNN` (empty until assigned).
  final String staffId;

  bool get isActive => status == statusActive;

  /// Active or Responded — blocks sending another SOS until Resolved.
  bool get isOpen =>
      status == statusActive || status == statusResponded;

  /// Human-readable time; same as [dateTime] per ERD format.
  String get dateTimeLabel => dateTime;

  static String formatClinicDateTime(DateTime clinicLocal) {
    final y = clinicLocal.year;
    final m = clinicLocal.month.toString().padLeft(2, '0');
    final d = clinicLocal.day.toString().padLeft(2, '0');
    final hh = clinicLocal.hour.toString().padLeft(2, '0');
    final mm = clinicLocal.minute.toString().padLeft(2, '0');
    final ss = clinicLocal.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  static String? _readString(Map<String, dynamic> data, String pascal, String camel) {
    final value = data[pascal] ?? data[camel];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Writes only the eight ERD fields (Table 4.7) using PascalCase keys.
  Map<String, dynamic> toFirestoreMap() {
    return {
      'AlertID': alertId,
      'DateTime': dateTime,
      'Location': location,
      'AlertType': alertType,
      'Status': status,
      'ResolutionNotes': resolutionNotes,
      'UserID': userId,
      'StaffID': staffId,
    };
  }

  static EmergencyAlertEntity? fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    final alertId = _readString(data, 'AlertID', 'alertId') ?? docId.trim();
    if (!alertIdPattern.hasMatch(alertId)) return null;

    final dateTime = _readString(data, 'DateTime', 'dateTime');
    if (dateTime == null) return null;

    final userId = _readString(data, 'UserID', 'userId') ??
        _readString(data, 'UserID', 'userID');
    if (userId == null) return null;

    return EmergencyAlertEntity(
      alertId: alertId,
      dateTime: dateTime,
      location: _readString(data, 'Location', 'location') ?? '',
      alertType:
          _readString(data, 'AlertType', 'alertType') ?? alertTypeManualSos,
      status: _readString(data, 'Status', 'status') ?? statusActive,
      resolutionNotes:
          _readString(data, 'ResolutionNotes', 'resolutionNotes') ?? '',
      userId: userId,
      staffId: _readString(data, 'StaffID', 'staffId') ??
          _readString(data, 'StaffID', 'staffID') ??
          '',
    );
  }
}
