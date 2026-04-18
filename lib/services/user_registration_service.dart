import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_entity.dart';

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
    String voiceProfile = '',
    String emergencyContact = '',
    String accessibilityPreferences = '',
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
        voiceProfile: voiceProfile,
        emergencyContact: emergencyContact,
        accessibilityPreferences: accessibilityPreferences,
        status: status,
      );
      transaction.set(userRef, entity.toFirestore());
    });
  }

  /// Removes the signed-in account if profile creation fails after Auth signup.
  Future<void> deleteCurrentAuthUser() async {
    await _auth.currentUser?.delete();
  }
}
