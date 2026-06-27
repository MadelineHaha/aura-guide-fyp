import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/therapy_session_item.dart';
import '../utils/appointment_types.dart';
import '../utils/clinic_datetime.dart';

class TherapySessionsService {
  TherapySessionsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static const _appointments = 'appointments';

  static bool _isTherapyType(String? value) {
    return AppointmentTypes.isTherapistAppointmentType(value);
  }

  String? _staffIdFromData(Map<String, dynamic> data) {
    for (final key in ['staffId', 'staffID']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  String? _patientIdFromData(Map<String, dynamic> data) {
    for (final key in ['userId', 'patientUserId', 'patientId']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  TherapySessionItem? _mapDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final appointmentType = (data['appointmentType'] as String?)?.trim() ??
        (data['type'] as String?)?.trim() ??
        '';
    if (!_isTherapyType(appointmentType)) return null;

    final dateTime = ClinicDateTime.fromFirestore(data['dateTime']) ??
        ClinicDateTime.fromFirestore(data['scheduledAt']);
    if (dateTime == null) return null;

    final patientId = _patientIdFromData(data) ?? '';
    if (patientId.isEmpty) return null;

    return TherapySessionItem(
      id: doc.id,
      patientId: patientId,
      staffId: _staffIdFromData(data) ?? '',
      appointmentType: appointmentType,
      dateTime: dateTime,
      status: (data['status'] as String?)?.trim() ?? 'Scheduled',
      sessionName: (data['sessionName'] as String?)?.trim() ?? '',
      sessionDuration: (data['sessionDuration'] as String?)?.trim() ?? '',
      sessionRemarks: (data['sessionRemarks'] as String?)?.trim() ?? '',
      sessionStatus: (data['sessionStatus'] as String?)?.trim() ?? '',
      sessionOutcome: (data['sessionOutcome'] as String?)?.trim() ?? '',
      notes: (data['notes'] as String?)?.trim() ?? '',
    );
  }

  Future<List<TherapySessionItem>> fetchForPatient(String patientId) async {
    final trimmed = patientId.trim();
    if (trimmed.isEmpty) return [];

    final snap = await _firestore
        .collection(_appointments)
        .where('userId', isEqualTo: trimmed)
        .get();

    final items = <TherapySessionItem>[];
    for (final doc in snap.docs) {
      final item = _mapDoc(doc);
      if (item != null) items.add(item);
    }
    items.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return items;
  }

  Stream<List<TherapySessionItem>> watchForPatient(String patientId) {
    final trimmed = patientId.trim();
    if (trimmed.isEmpty) {
      return Stream.value(const []);
    }
    return _firestore
        .collection(_appointments)
        .where('userId', isEqualTo: trimmed)
        .snapshots()
        .map((snap) {
      final items = <TherapySessionItem>[];
      for (final doc in snap.docs) {
        final item = _mapDoc(doc);
        if (item != null) items.add(item);
      }
      items.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      return items;
    });
  }

  Future<List<TherapySessionItem>> fetchForStaff(String staffId) async {
    final trimmedStaffId = staffId.trim();
    if (trimmedStaffId.isEmpty) return [];

    final seen = <String>{};
    final items = <TherapySessionItem>[];

    Future<void> collect(String field) async {
      final snap = await _firestore
          .collection(_appointments)
          .where(field, isEqualTo: trimmedStaffId)
          .get();
      for (final doc in snap.docs) {
        if (!seen.add(doc.id)) continue;
        final item = _mapDoc(doc);
        if (item != null) items.add(item);
      }
    }

    await collect('staffId');
    await collect('staffID');

    items.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    return items;
  }

  Future<void> updateSessionDetails({
    required String appointmentId,
    required String sessionName,
    required String sessionDuration,
    required String sessionRemarks,
    required String sessionStatus,
    required String sessionOutcome,
  }) async {
    await _firestore.collection(_appointments).doc(appointmentId).update({
      'sessionName': sessionName,
      'sessionDuration': sessionDuration,
      'sessionRemarks': sessionRemarks,
      'sessionStatus': sessionStatus,
      'sessionOutcome': sessionOutcome,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<String> createRehabAppointment({
    required String patientId,
    required String staffId,
    required DateTime dateTime,
    required String sessionName,
    String notes = '',
  }) async {
    final ref = await _firestore.collection(_appointments).add({
      'userId': patientId,
      'patientUserId': patientId,
      'staffId': staffId,
      'staffID': staffId,
      'type': 'Therapy Session',
      'appointmentType': 'Therapy Session',
      'dateTime': ClinicDateTime.toTimestamp(dateTime),
      'scheduledAt': ClinicDateTime.toTimestamp(dateTime),
      'status': 'Scheduled',
      'sessionName': sessionName,
      'notes': notes,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> createRehabPlan({
    required String patientId,
    required String staffId,
    required DateTime startDate,
    required int weeks,
    required List<String> milestoneNames,
    String notes = '',
  }) async {
    for (var i = 0; i < weeks; i++) {
      final sessionDate = DateTime(
        startDate.year,
        startDate.month,
        startDate.day + (i * 7),
        9,
        0,
      );
      final name = i < milestoneNames.length && milestoneNames[i].trim().isNotEmpty
          ? milestoneNames[i].trim()
          : 'Week ${i + 1} Session';
      await createRehabAppointment(
        patientId: patientId,
        staffId: staffId,
        dateTime: sessionDate,
        sessionName: name,
        notes: notes,
      );
    }
  }
}
