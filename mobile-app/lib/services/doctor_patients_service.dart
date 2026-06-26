import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/doctor_patient_summary.dart';

class DoctorPatientsService {
  DoctorPatientsService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  DoctorPatientSummary? _mapDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final role = data['role']?.toString().trim().toLowerCase() ?? 'patient';
    if (role != 'patient') return null;

    final patientId = (data['userId'] as String?)?.trim() ??
        (data['patientId'] as String?)?.trim() ??
        '';
    if (patientId.isEmpty) return null;

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
      assignedCaregiverUid:
          (data['assignedCaregiverId'] as String?)?.trim() ?? '',
      assignedCaregiverPublicId:
          (data['assignedCaregiverPublicId'] as String?)?.trim() ?? '',
      assignedCaregiverName:
          (data['assignedCaregiverName'] as String?)?.trim() ?? '',
    );
  }

  List<DoctorPatientSummary> _mapSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final patients = <DoctorPatientSummary>[];
    for (final doc in snap.docs) {
      final item = _mapDoc(doc);
      if (item != null && item.isActive) {
        patients.add(item);
      }
    }
    patients.sort((a, b) => a.name.compareTo(b.name));
    return patients;
  }

  Future<List<DoctorPatientSummary>> fetchPatients() async {
    final snap = await _firestore.collection('users').get();
    return _mapSnapshot(snap);
  }

  Stream<List<DoctorPatientSummary>> watchPatients() {
    return _firestore
        .collection('users')
        .snapshots()
        .map(_mapSnapshot);
  }
}
