import 'package:cloud_firestore/cloud_firestore.dart';

import '../caregiver/services/caregiver_profile_service.dart';
import '../models/doctor_patient_summary.dart';
import '../utils/clinic_datetime.dart';

class DoctorAdherenceService {
  DoctorAdherenceService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const _medications = 'medications';
  static const _reminders = 'medicationreminders';

  Future<bool> _hasActiveMedication(String patientId) async {
    final snap = await _firestore
        .collection(_medications)
        .where('userId', isEqualTo: patientId)
        .get();
    final today = _dateString(ClinicDateTime.nowClinic());
    for (final doc in snap.docs) {
      final data = doc.data();
      final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
      if (status == 'cancelled') continue;
      final endDate = (data['endDate'] as String?)?.trim() ?? '';
      if (endDate.isNotEmpty && endDate.compareTo(today) < 0) continue;
      return true;
    }
    return false;
  }

  Future<int?> adherencePercentForPatient(
    String patientId, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) async {
    if (!await _hasActiveMedication(patientId)) return null;

    final startStr = _dateString(rangeStart);
    final endStr = _dateString(rangeEnd);

    final snap = await _firestore
        .collection(_reminders)
        .where('userId', isEqualTo: patientId)
        .get();

    var total = 0;
    var taken = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      final doseDate = (data['doseDate'] as String?)?.trim() ?? '';
      if (doseDate.isEmpty) continue;
      if (doseDate.compareTo(startStr) < 0 || doseDate.compareTo(endStr) > 0) {
        continue;
      }
      total++;
      if (data['taken'] == true) taken++;
    }

    if (total == 0) return null;
    return ((taken / total) * 100).round();
  }

  String _dateString(DateTime date) {
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<List<PatientAdherenceRow>> loadLowAdherenceRows(
    List<DoctorPatientSummary> patients, {
    required String rangeKey,
  }) async {
    final now = ClinicDateTime.nowClinic();
    late DateTime start;
    late DateTime end;
    switch (rangeKey) {
      case 'today':
        start = ClinicDateTime.clinicDayStart(now);
        end = start;
        break;
      case 'month':
        start = DateTime(now.year, now.month, 1);
        end = now;
        break;
      default:
        start = DateTime(2000);
        end = now;
    }

    final rows = <PatientAdherenceRow>[];
    for (final patient in patients) {
      final percent = await adherencePercentForPatient(
        patient.patientId,
        rangeStart: start,
        rangeEnd: end,
      );
      if (percent == null) continue;
      final contact = await _resolveContactTarget(patient);
      rows.add(
        PatientAdherenceRow(
          patientId: patient.patientId,
          name: patient.name,
          adherencePercent: percent,
          contactParticipantId: contact.participantId,
          contactDisplayName: contact.displayName,
          contactIsCaregiver: contact.isCaregiver,
        ),
      );
    }

    rows.sort((a, b) => a.adherencePercent.compareTo(b.adherencePercent));
    return rows.where((row) => row.adherencePercent < 100).toList();
  }

  Future<_AdherenceContactTarget> _resolveContactTarget(
    DoctorPatientSummary patient,
  ) async {
    var caregiverPublicId = patient.assignedCaregiverPublicId.trim();
    var caregiverName = patient.assignedCaregiverName.trim();

    if (caregiverPublicId.isEmpty) {
      final caregiverUid = patient.assignedCaregiverUid.trim();
      if (caregiverUid.isNotEmpty) {
        final snap =
            await _firestore.collection('caregiver').doc(caregiverUid).get();
        if (snap.exists) {
          final data = snap.data() ?? {};
          caregiverPublicId =
              CaregiverProfileService.caregiverIdFromData(data) ?? '';
          if (caregiverName.isEmpty) {
            caregiverName = CaregiverProfileService.displayName(data);
          }
        }
      }
    }

    if (caregiverPublicId.isNotEmpty) {
      return _AdherenceContactTarget(
        participantId: caregiverPublicId,
        displayName:
            caregiverName.isNotEmpty ? caregiverName : caregiverPublicId,
        isCaregiver: true,
      );
    }

    return _AdherenceContactTarget(
      participantId: patient.patientId,
      displayName: patient.name,
      isCaregiver: false,
    );
  }
}

class _AdherenceContactTarget {
  const _AdherenceContactTarget({
    required this.participantId,
    required this.displayName,
    required this.isCaregiver,
  });

  final String participantId;
  final String displayName;
  final bool isCaregiver;
}

class PatientAdherenceRow {
  const PatientAdherenceRow({
    required this.patientId,
    required this.name,
    required this.adherencePercent,
    required this.contactParticipantId,
    required this.contactDisplayName,
    required this.contactIsCaregiver,
  });

  final String patientId;
  final String name;
  final int adherencePercent;
  final String contactParticipantId;
  final String contactDisplayName;
  final bool contactIsCaregiver;
}
