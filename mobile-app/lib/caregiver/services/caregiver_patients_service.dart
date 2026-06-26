import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/doctor_patient_summary.dart';
import 'caregiver_profile_service.dart';

class CaregiverPatientsService {
  CaregiverPatientsService({
    FirebaseFirestore? firestore,
    CaregiverProfileService? profileService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _profileService = profileService ?? CaregiverProfileService();

  final FirebaseFirestore _firestore;
  final CaregiverProfileService _profileService;

  DoctorPatientSummary? _mapDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Set<String> connectedIds,
  ) {
    final data = doc.data();
    final patientId = (data['userId'] as String?)?.trim().toUpperCase() ??
        (data['patientId'] as String?)?.trim().toUpperCase() ??
        '';
    if (patientId.isEmpty || !connectedIds.contains(patientId)) {
      return null;
    }

    final role = data['role']?.toString().trim().toLowerCase() ?? 'patient';
    if (role != 'patient' && !patientId.startsWith('U')) return null;

    return DoctorPatientSummary(
      authUid: doc.id,
      patientId: patientId,
      name: (data['name'] as String?)?.trim().isNotEmpty == true
          ? (data['name'] as String).trim()
          : 'Unnamed Patient',
      email: (data['email'] as String?)?.trim() ?? '',
      accountStatus: (data['accountStatus'] as String?)?.trim() ??
          (data['status'] as String?)?.trim() ??
          'Active',
    );
  }

  List<DoctorPatientSummary> _mapSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
    Set<String> connectedIds,
  ) {
    final patients = <DoctorPatientSummary>[];
    for (final doc in snap.docs) {
      final item = _mapDoc(doc, connectedIds);
      if (item != null && item.isActive) {
        patients.add(item);
      }
    }
    patients.sort((a, b) => a.name.compareTo(b.name));
    return patients;
  }

  Stream<List<DoctorPatientSummary>> watchConnectedPatients() async* {
    await for (final profile in _profileService.watchCurrentProfile()) {
      final connectedIds = CaregiverProfileService.connectedUserIdsFromData(
        profile,
      );
      if (connectedIds.isEmpty) {
        yield [];
        continue;
      }
      yield* _firestore.collection('users').snapshots().map(
            (snap) => _mapSnapshot(snap, connectedIds),
          );
    }
  }
}
