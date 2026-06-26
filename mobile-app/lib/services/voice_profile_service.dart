import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/voice_profile_data.dart';
import 'phone_number_service.dart';
import 'voice_embedding_service.dart';

class VoiceVerificationResult {
  const VoiceVerificationResult._({
    required this.status,
    this.profile,
    this.score = 0,
    this.candidates = const [],
  });

  final VoiceVerificationStatus status;
  final Map<String, dynamic>? profile;
  final double score;
  final List<Map<String, dynamic>> candidates;

  factory VoiceVerificationResult.phraseNotFound() {
    return const VoiceVerificationResult._(
      status: VoiceVerificationStatus.phraseNotFound,
    );
  }

  factory VoiceVerificationResult.success(
    Map<String, dynamic> profile,
    double score,
  ) {
    return VoiceVerificationResult._(
      status: VoiceVerificationStatus.voiceMatched,
      profile: profile,
      score: score,
    );
  }

  factory VoiceVerificationResult.voiceMismatch({
    required List<Map<String, dynamic>> candidates,
    Map<String, dynamic>? bestCandidate,
    required double score,
  }) {
    return VoiceVerificationResult._(
      status: VoiceVerificationStatus.voiceMismatch,
      profile: bestCandidate,
      score: score,
      candidates: candidates,
    );
  }
}

enum VoiceVerificationStatus {
  phraseNotFound,
  voiceMatched,
  voiceMismatch,
}

class VoiceProfileService {
  VoiceProfileService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  final _embeddings = VoiceEmbeddingService.instance;

  String normalize(String raw) {
    return raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> saveVoiceProfile({
    required String uid,
    required String passphrase,
    List<double>? voiceprintVector,
    Map<String, dynamic>? voiceFeatures,
  }) async {
    final normalized = normalize(passphrase);
    if (uid.isEmpty || normalized.isEmpty) return;

    final profile = VoiceProfileData(
      passphrase: normalized,
      voiceprintVector: voiceprintVector ?? const [],
      voiceFeatures: voiceFeatures ?? const {},
    ).toMap();

    final isStaff = !(await _firestore.collection('users').doc(uid).get()).exists;
    final collection = isStaff ? 'healthcarestaff' : 'users';

    await _firestore.collection(collection).doc(uid).set({
      'authUid': uid,
      'voiceProfile': profile,
      'voicePassphrase': normalized,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<VoiceVerificationResult> verifyVoiceLogin({
    required String passphrase,
    required List<double> probeVector,
  }) async {
    if (!VoiceEmbeddingService.isUsableVoiceprint(probeVector)) {
      return VoiceVerificationResult.voiceMismatch(
        candidates: const [],
        score: 0,
      );
    }

    final candidates = await _findPassphraseCandidates(passphrase);
    if (candidates.isEmpty) {
      return VoiceVerificationResult.phraseNotFound();
    }

    Map<String, dynamic>? bestProfile;
    var bestScore = -1.0;

    for (final candidate in candidates) {
      final data = candidate.profile;
      final voiceData = VoiceProfileData.fromFirestore(data['voiceProfile']);
      final enrolled = voiceData?.voiceprintVector ?? const [];
      if (!VoiceEmbeddingService.isUsableVoiceprint(enrolled)) continue;

      final score = _embeddings.cosineSimilarity(enrolled, probeVector);
      if (score > bestScore) {
        bestScore = score;
        bestProfile = data;
      }
    }

    debugPrint(
      'VoiceProfileService: verifyVoiceLogin bestScore = $bestScore, matchThreshold = ${VoiceEmbeddingService.matchThreshold}',
    );

    if (bestProfile != null &&
        bestScore >= VoiceEmbeddingService.matchThreshold) {
      return VoiceVerificationResult.success(bestProfile, bestScore);
    }

    return VoiceVerificationResult.voiceMismatch(
      candidates: candidates.map((c) => c.profile).toList(),
      bestCandidate: bestProfile ?? candidates.first.profile,
      score: bestScore < 0 ? 0 : bestScore,
    );
  }

  Future<Map<String, dynamic>?> findProfileByPhone(String phone) async {
    final normalized = PhoneNumberService.normalize(phone);
    if (normalized.isEmpty) return null;

    final exact = await _firestore
        .collection('users')
        .where('phoneNumberNormalized', isEqualTo: normalized)
        .limit(1)
        .get();
    if (exact.docs.isNotEmpty) {
      return _withAuthUid(exact.docs.first);
    }

    final exactStaff = await _firestore
        .collection('healthcarestaff')
        .where('phoneNumberNormalized', isEqualTo: normalized)
        .limit(1)
        .get();
    if (exactStaff.docs.isNotEmpty) {
      return _withAuthUid(exactStaff.docs.first);
    }

    final all = await _firestore.collection('users').limit(200).get();
    for (final doc in all.docs) {
      final stored = doc.data()['phoneNumber']?.toString();
      if (PhoneNumberService.numbersMatch(stored, phone)) {
        return _withAuthUid(doc);
      }
    }

    final allStaff = await _firestore.collection('healthcarestaff').limit(200).get();
    for (final doc in allStaff.docs) {
      final stored = doc.data()['phoneNumber']?.toString();
      if (PhoneNumberService.numbersMatch(stored, phone)) {
        return _withAuthUid(doc);
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> findMatchingProfile(String voiceProfile) async {
    final candidates = await _findPassphraseCandidates(voiceProfile);
    if (candidates.isEmpty) return null;
    return candidates.first.profile;
  }

  Future<List<_VoiceCandidate>> _findPassphraseCandidates(
    String passphrase,
  ) async {
    final normalized = normalize(passphrase);
    if (normalized.isEmpty) return [];

    final results = <_VoiceCandidate>[];
    final seen = <String>{};

    void addProfile(String docId, Map<String, dynamic> data) {
      if (!seen.add(docId)) return;
      results.add(
        _VoiceCandidate(profile: _mapVoiceProfileDoc(docId, data)),
      );
    }

    try {
      final users = await _firestore
          .collection('users')
          .where('voicePassphrase', isEqualTo: normalized)
          .limit(50)
          .get();
      for (final doc in users.docs) {
        addProfile(doc.id, doc.data());
      }
    } catch (error, stack) {
      debugPrint(
        'VoiceProfileService users voice lookup failed: $error\n$stack',
      );
    }

    try {
      final staff = await _firestore
          .collection('healthcarestaff')
          .where('voicePassphrase', isEqualTo: normalized)
          .limit(50)
          .get();
      for (final doc in staff.docs) {
        addProfile(doc.id, doc.data());
      }
    } catch (error) {
      debugPrint('VoiceProfileService healthcarestaff voice lookup failed: $error');
    }

    return results;
  }

  Map<String, dynamic> _mapVoiceProfileDoc(
    String docId,
    Map<String, dynamic> data,
  ) {
    final authUid = (data['authUid'] as String?)?.trim() ?? '';
    return {
      ...data,
      'authUid': authUid.isEmpty ? docId : authUid,
      'voiceProfile': data['voiceProfile'],
    };
  }

  Map<String, dynamic> _withAuthUid(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return {
      ...doc.data(),
      'authUid': doc.id,
    };
  }
}

class _VoiceCandidate {
  const _VoiceCandidate({required this.profile});

  final Map<String, dynamic> profile;
}
