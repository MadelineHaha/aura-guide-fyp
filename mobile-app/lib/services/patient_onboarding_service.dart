import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/voice_pin_capture_result.dart';
import 'voice_auth_credentials_service.dart';
import 'voice_embedding_service.dart';
import 'voice_passphrase.dart';
import 'voice_profile_service.dart';

class PatientOnboardingException implements Exception {
  PatientOnboardingException(this.message);

  final String message;

  @override
  String toString() => message;
}

class PatientOnboardingService {
  PatientOnboardingService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  /// Finds a pending patient profile by spoken PIN and signs the user in.
  Future<PatientActivationResult> signInWithSpokenPin({
    required String pin,
    VoicePinCaptureResult? voiceCapture,
  }) async {
    final trimmedPin = pin.trim();
    if (!RegExp(r'^\d{4}$').hasMatch(trimmedPin)) {
      throw PatientOnboardingException('Speak a 4-digit PIN.');
    }

    final pendingDoc = await _findPendingPatientByPin(trimmedPin);
    if (pendingDoc == null) {
      throw PatientOnboardingException(
        'Invalid PIN. Ask your clinic administrator to confirm the PIN or create your account again.',
      );
    }

    final profile = pendingDoc.data();
    final storedPin = _resolveStoredPin(profile);
    if (storedPin != trimmedPin) {
      throw PatientOnboardingException('Invalid PIN. Please try again.');
    }

    final publicUserId =
        (profile['userId'] ?? profile['userID'] ?? '').toString().trim().toUpperCase();
    if (publicUserId.isEmpty) {
      throw PatientOnboardingException(
        'This patient account is not ready yet. Contact your clinic administrator.',
      );
    }

    final authUid = await _signInToPendingPatient(profile, pendingDoc.id);
    final email = _resolvePatientEmail(profile, authUid);

    await _writeActivatedProfile(
      authUid: authUid,
      email: email,
      publicUserId: publicUserId,
      profile: profile,
      pin: trimmedPin,
      pendingDocId: pendingDoc.id,
    );

    final voiceprint = voiceCapture?.voiceprintVector ?? const <double>[];
    if (VoiceEmbeddingService.isUsableVoiceprint(voiceprint)) {
      await VoiceProfileService().saveVoiceProfile(
        uid: authUid,
        passphrase: VoicePassphrase.expectedNormalized,
        voiceprintVector: voiceprint,
        voiceFeatures: voiceCapture?.voiceFeatures,
      );
    }

    return PatientActivationResult(
      uid: authUid,
      email: email,
      userId: publicUserId,
    );
  }

  /// Clears onboarding PIN flags for a signed-in patient (legacy voice-setup path).
  Future<void> completeOnboarding() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    await _firestore.collection('users').doc(uid).set(
      {
        'onboardingPending': false,
        'emailPending': false,
        'onboardingPin': FieldValue.delete(),
        'pin': FieldValue.delete(),
        'voiceAuthPassword': FieldValue.delete(),
        'onboardingCompletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _findPendingPatientByPin(
    String pin,
  ) async {
    for (final field in ['onboardingPin', 'pin']) {
      final doc = await _queryPendingUserByPinField(field, pin);
      if (doc != null) {
        return doc;
      }
    }
    return null;
  }

  Future<QueryDocumentSnapshot<Map<String, dynamic>>?> _queryPendingUserByPinField(
    String field,
    String pin,
  ) async {
    final values = <Object>[pin];
    final numericPin = int.tryParse(pin);
    if (numericPin != null) {
      values.add(numericPin);
    }

    for (final value in values) {
      final snap = await _firestore
          .collection('users')
          .where(field, isEqualTo: value)
          .where('onboardingPending', isEqualTo: true)
          .limit(2)
          .get();

      if (snap.docs.isEmpty) {
        continue;
      }
      if (snap.docs.length > 1) {
        throw PatientOnboardingException(
          'Multiple accounts share this PIN. Contact your clinic administrator.',
        );
      }

      final doc = snap.docs.first;
      if (_resolveStoredPin(doc.data()) != pin) {
        continue;
      }
      return doc;
    }
    return null;
  }

  String _resolveStoredPin(Map<String, dynamic> profile) {
    return (profile['onboardingPin'] ?? profile['pin'] ?? '').toString().trim();
  }

  String _resolvePatientEmail(Map<String, dynamic> profile, String authUid) {
    final storedEmail = (profile['email'] ?? '').toString().trim().toLowerCase();
    if (storedEmail.isNotEmpty) {
      return storedEmail;
    }
    if (authUid.isNotEmpty) {
      return VoiceAuthCredentialsService.voiceEmailFor(authUid);
    }
    return '';
  }

  Future<String> _signInToPendingPatient(
    Map<String, dynamic> profile,
    String pendingDocId,
  ) async {
    final authUid =
        (profile['authUid'] ?? pendingDocId).toString().trim();
    final email = _resolvePatientEmail(profile, authUid);
    final password = (profile['voiceAuthPassword'] ?? '').toString();

    if (authUid.isNotEmpty && email.isNotEmpty && password.isNotEmpty) {
      final signedIn = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = signedIn.user?.uid;
      if (uid == null || uid.isEmpty) {
        throw PatientOnboardingException('Could not sign in to this patient account.');
      }
      await VoiceAuthCredentialsService.instance.save(
        uid,
        VoiceAuthCredentials(email: email, password: password),
      );
      return uid;
    }

    if (authUid.isNotEmpty && email.isNotEmpty) {
      final creds = await VoiceAuthCredentialsService.instance.load(authUid);
      if (creds != null) {
        final signedIn = await _auth.signInWithEmailAndPassword(
          email: creds.email,
          password: creds.password,
        );
        final uid = signedIn.user?.uid;
        if (uid == null || uid.isEmpty) {
          throw PatientOnboardingException('Could not sign in to this patient account.');
        }
        return uid;
      }
    }

    if (email.isEmpty) {
      throw PatientOnboardingException(
        'This patient account is missing login credentials. Ask your clinic administrator to recreate the account.',
      );
    }

    return _ensurePatientAuthAccount(email: email);
  }

  Future<String> _ensurePatientAuthAccount({required String email}) async {
    final normalizedEmail = email.trim().toLowerCase();

    try {
      final created = await VoiceAuthCredentialsService.instance
          .createAccountWithEmail(normalizedEmail);
      return created.uid;
    } on FirebaseAuthException catch (error) {
      if (error.code != 'email-already-in-use') {
        rethrow;
      }

      final creds =
          await VoiceAuthCredentialsService.instance.loadByEmail(normalizedEmail);
      if (creds == null) {
        throw PatientOnboardingException(
          'This patient account could not be activated. Contact your clinic administrator.',
        );
      }

      final signedIn = await _auth.signInWithEmailAndPassword(
        email: creds.email,
        password: creds.password,
      );
      final uid = signedIn.user?.uid;
      if (uid == null || uid.isEmpty) {
        throw PatientOnboardingException('Could not sign in to this patient account.');
      }
      return uid;
    }
  }

  Future<void> _writeActivatedProfile({
    required String authUid,
    required String email,
    required String publicUserId,
    required Map<String, dynamic> profile,
    required String pin,
    required String pendingDocId,
  }) async {
    final payload = <String, dynamic>{
      'userId': publicUserId,
      'name': profile['name'] ?? '',
      'email': email,
      'birthDate': profile['birthDate'],
      'address': profile['address'] ?? '',
      'gender': profile['gender'] ?? '',
      'phone': profile['phone'] ?? '',
      'emergencyContact': profile['emergencyContact'] ?? '',
      'settings': profile['settings'] ?? profile['accessibilityPreferences'],
      'status': profile['status'] ?? 'Active',
      'authUid': authUid,
      'onboardingPending': false,
      'emailPending': false,
      'onboardingPin': FieldValue.delete(),
      'pin': FieldValue.delete(),
      'voiceAuthPassword': FieldValue.delete(),
      'onboardingCompletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'registeredByStaff': profile['registeredByStaff'] ?? '',
      'createdAt': profile['createdAt'] ?? FieldValue.serverTimestamp(),
    };

    if (profile['voiceProfile'] != null && profile['voiceProfile'] != '') {
      payload['voiceProfile'] = profile['voiceProfile'];
    }
    if (profile['voicePassphrase'] != null) {
      payload['voicePassphrase'] = profile['voicePassphrase'];
    }

    await _firestore.collection('users').doc(authUid).set(
          payload,
          SetOptions(merge: true),
        );

    if (pendingDocId.isNotEmpty && pendingDocId != authUid) {
      await _firestore.collection('users').doc(pendingDocId).delete();
    }

    try {
      await _firestore.collection('onboardingPins').doc(pin).set(
        {
          'onboardingPending': false,
          'authUid': authUid,
          'activatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on FirebaseException catch (error) {
      if (error.code != 'permission-denied') {
        rethrow;
      }
    }
  }
}

class PatientActivationResult {
  const PatientActivationResult({
    required this.uid,
    required this.email,
    required this.userId,
  });

  final String uid;
  final String email;
  final String userId;
}

String patientOnboardingErrorMessage(Object error) {
  if (error is PatientOnboardingException) {
    return error.message;
  }
  if (error is FirebaseAuthException) {
    if (error.code == 'admin-restricted-operation') {
      return 'Patient sign-up is disabled in Firebase. Enable Email/Password sign-up in Authentication settings.';
    }
    if (error.code == 'operation-not-allowed') {
      return 'Email/Password sign-in is not enabled in Firebase Authentication.';
    }
    if (error.code == 'invalid-credential' || error.code == 'wrong-password') {
      return 'Could not sign in to this patient account. Ask your clinic administrator to recreate the account.';
    }
    return error.message ?? 'Could not sign in to this patient account.';
  }
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'Could not read the patient record. Deploy updated Firestore rules (firebase deploy --only firestore:rules) and try again.';
  }
  return error.toString();
}
