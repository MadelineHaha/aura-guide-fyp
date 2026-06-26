import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth_session.dart';
import 'healthcare_staff_service.dart';

class StaffProfileService {
  StaffProfileService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const collection = HealthcareStaffService.collection;

  String? _uid() => AuthSession.resolveUser()?.uid ?? _auth.currentUser?.uid;

  static String? staffIdFromData(Map<String, dynamic> data) {
    for (final key in ['staffID', 'staffId', 'staff_id']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static bool isActiveProfile(Map<String, dynamic> data) {
    return data['status']?.toString().trim().toLowerCase() == 'active';
  }

  static String displayName(Map<String, dynamic> data) {
    final name = data['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    return data['email']?.toString().trim() ?? 'Doctor';
  }

  Future<Map<String, dynamic>?> loadCurrentProfile() async {
    final uid = _uid();
    if (uid == null) return null;
    final snap = await _firestore.collection(collection).doc(uid).get();
    if (!snap.exists) return null;
    final data = snap.data() ?? {};
    if (!isActiveProfile(data)) return null;
    return data;
  }

  Stream<Map<String, dynamic>> watchCurrentProfile() {
    final uid = _uid();
    if (uid == null) {
      return Stream.value(const {});
    }
    return _firestore.collection(collection).doc(uid).snapshots().map((snap) {
      if (!snap.exists) return const {};
      final data = snap.data() ?? {};
      if (!isActiveProfile(data)) return const {};
      return data;
    });
  }

  Future<String?> currentStaffId() async {
    final profile = await loadCurrentProfile();
    if (profile == null) return null;
    return staffIdFromData(profile);
  }
}
