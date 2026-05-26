import 'package:cloud_firestore/cloud_firestore.dart';

class VoiceProfileService {
  VoiceProfileService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  String normalize(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<Map<String, dynamic>?> findMatchingProfile(String voiceProfile) async {
    final normalized = normalize(voiceProfile);
    if (normalized.isEmpty) return null;

    final snap = await _firestore
        .collection('users')
        .where('voiceProfile', isEqualTo: normalized)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return snap.docs.first.data();
  }
}
