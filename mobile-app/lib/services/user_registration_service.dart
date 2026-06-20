import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_entity.dart';
import '../models/voice_profile_data.dart';
import 'phone_number_service.dart';

class UserRegistrationService {
  UserRegistrationService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Creates the Firestore user profile for [uid] with a new sequential [UserEntity.userId].
  Future<void> createUserProfile({
    required String uid,
    required String name,
    required DateTime birthDate,
    required String email,
    String voicePassphrase = '',
    List<double>? voiceprintVector,
    Map<String, dynamic>? voiceFeatures,
    String phoneNumber = '',
    String emergencyContact = '',
    Map<String, dynamic>? accessibilityPreferences,
    UserStatus status = UserStatus.active,
  }) async {
    final userRef = _firestore.collection(UserEntity.collection).doc(uid);
    final counterRef = _firestore.doc(UserEntity.counterDocPath);

    await _firestore.runTransaction((transaction) async {
      final counterSnap = await transaction.get(counterRef);
      final next = (counterSnap.data()?['next'] as int?) ?? 1;
      final userId = 'U${next.toString().padLeft(5, '0')}';

      transaction.set(counterRef, {'next': next + 1}, SetOptions(merge: true));

      final entity = UserEntity(
        userId: userId,
        name: name,
        birthDate: birthDate,
        email: email,
        emergencyContact: emergencyContact,
        accessibilityPreferences: accessibilityPreferences,
        status: status,
      );

      final payload = <String, dynamic>{
        ...entity.toFirestore(),
        'authUid': uid,
      };

      final normalizedPhrase = voicePassphrase.trim().toLowerCase();
      if (normalizedPhrase.isNotEmpty) {
        payload['voicePassphrase'] = normalizedPhrase;
        payload['voiceProfile'] = VoiceProfileData(
          passphrase: normalizedPhrase,
          voiceprintVector: voiceprintVector ?? const [],
          voiceFeatures: voiceFeatures ?? const {},
        ).toMap();
      }

      final trimmedPhone = phoneNumber.trim();
      if (trimmedPhone.isNotEmpty) {
        payload['phoneNumber'] = trimmedPhone;
        payload['phoneNumberNormalized'] =
            PhoneNumberService.normalize(trimmedPhone);
      }

      transaction.set(userRef, payload);
    });
  }

  /// Removes the signed-in account if profile creation fails after Auth signup.
  Future<void> deleteCurrentAuthUser() async {
    await _auth.currentUser?.delete();
  }
}
