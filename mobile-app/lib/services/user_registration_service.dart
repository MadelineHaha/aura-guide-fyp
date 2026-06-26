import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_entity.dart';
import '../models/voice_profile_data.dart';
import 'activity_log_actions.dart';
import 'activity_log_service.dart';
import 'phone_number_service.dart';

class UserRegistrationService {
  UserRegistrationService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Creates the Firestore user profile for [uid] with a new sequential ID.
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
    String role = 'patient',
  }) async {
    final bool isPatient = role.trim().toLowerCase() == 'patient';

    if (isPatient) {
      final userRef = _firestore.collection(UserEntity.collection).doc(uid);
      final counterRef = _firestore.doc(UserEntity.counterDocPath);

      await _firestore.runTransaction((transaction) async {
        final counterSnap = await transaction.get(counterRef);
        final next = (counterSnap.data()?['next'] as num?)?.toInt() ?? 1;
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
          role: role,
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

      unawaited(
        ActivityLogService.instance.log(
          action: ActivityLogActions.registerAccount,
          details: 'New patient account created for $name.',
          userName: name,
        ),
      );
    } else {
      final staffRef = _firestore.collection('healthcarestaff').doc(uid);
      final counterRef = _firestore.doc('system/healthcareStaffCounter');

      await _firestore.runTransaction((transaction) async {
        final counterSnap = await transaction.get(counterRef);
        final next = (counterSnap.data()?['next'] as num?)?.toInt() ?? 1;
        final staffId = 'S${next.toString().padLeft(5, '0')}';

        transaction.set(counterRef, {'next': next + 1}, SetOptions(merge: true));

        final capitalizedRole = _capitalizeRole(role);

        final payload = <String, dynamic>{
          'staffID': staffId,
          'staffId': staffId,
          'name': name,
          'email': email,
          'role': capitalizedRole,
          'status': 'Active',
          'authUid': uid,
          'createdAt': FieldValue.serverTimestamp(),
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

        transaction.set(staffRef, payload);
      });

      unawaited(
        ActivityLogService.instance.log(
          action: ActivityLogActions.registerAccount,
          details: 'New staff account created for $name ($role).',
          userName: name,
        ),
      );
    }
  }

  String _capitalizeRole(String role) {
    final r = role.trim().toLowerCase();
    if (r == 'doctor') return 'Doctor';
    if (r == 'therapist') return 'Therapist';
    if (r == 'caregiver') return 'Caregiver';
    if (r.isEmpty) return role;
    return r[0].toUpperCase() + r.substring(1);
  }

  /// Removes the signed-in account if profile creation fails after Auth signup.
  Future<void> deleteCurrentAuthUser() async {
    await _auth.currentUser?.delete();
  }
}
