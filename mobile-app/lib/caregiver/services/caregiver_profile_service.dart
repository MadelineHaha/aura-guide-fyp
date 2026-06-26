import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../auth_session.dart';

class CaregiverProfileService {
  CaregiverProfileService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  static const collection = 'caregiver';

  String? _uid() => AuthSession.resolveUser()?.uid ?? _auth.currentUser?.uid;

  static String? caregiverIdFromData(Map<String, dynamic> data) {
    for (final key in ['caregiverId', 'caregiverID', 'caregiver_id']) {
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
    return data['email']?.toString().trim() ?? 'Caregiver';
  }

  static Set<String> connectedUserIdsFromData(Map<String, dynamic> data) {
    final raw = data['connectedUserIds'];
    if (raw is List) {
      return raw
          .map((value) => value.toString().trim().toUpperCase())
          .where((value) => value.isNotEmpty)
          .toSet();
    }
    final patients = data['connectedPatients'];
    if (patients is List) {
      return patients
          .map((entry) {
            if (entry is Map) {
              return (entry['userId'] ?? entry['userID'] ?? '')
                  .toString()
                  .trim()
                  .toUpperCase();
            }
            return '';
          })
          .where((value) => value.isNotEmpty)
          .toSet();
    }
    return {};
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

  Future<String?> currentCaregiverId() async {
    final profile = await loadCurrentProfile();
    if (profile == null) return null;
    return caregiverIdFromData(profile);
  }

  Future<Set<String>> currentConnectedUserIds() async {
    final profile = await loadCurrentProfile();
    if (profile == null) return {};
    return connectedUserIdsFromData(profile);
  }
}
