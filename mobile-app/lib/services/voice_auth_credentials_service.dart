import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Auto-generated email/password for voice-only accounts (stored on device).
class VoiceAuthCredentials {
  const VoiceAuthCredentials({
    required this.email,
    required this.password,
  });

  final String email;
  final String password;
}

class VoiceAuthCredentialsService {
  VoiceAuthCredentialsService._();

  static final VoiceAuthCredentialsService instance =
      VoiceAuthCredentialsService._();

  static const _emailDomain = 'auraguide.local';

  static String voiceEmailFor(String uid) => 'voice_$uid@$_emailDomain';

  String _generatePassword(Random random) {
    const upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lower = 'abcdefghjkmnpqrstuvwxyz';
    const digits = '23456789';
    const special = r'!@#$%^&*';
    final all = upper + lower + digits + special;

    final chars = <String>[
      upper[random.nextInt(upper.length)],
      lower[random.nextInt(lower.length)],
      digits[random.nextInt(digits.length)],
      special[random.nextInt(special.length)],
    ];
    for (var i = 0; i < 12; i++) {
      chars.add(all[random.nextInt(all.length)]);
    }
    chars.shuffle(random);
    return chars.join();
  }

  Future<({String uid, VoiceAuthCredentials credentials})>
      createAccountWithEmail(String email) async {
    final random = Random.secure();
    final password = _generatePassword(random);
    final normalizedEmail = email.trim().toLowerCase();

    final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: normalizedEmail,
      password: password,
    );

    final uid = credential.user?.uid;
    if (uid == null) {
      throw StateError('No uid returned from Firebase Auth.');
    }

    final credentials = VoiceAuthCredentials(
      email: normalizedEmail,
      password: password,
    );
    await save(uid, credentials);

    return (uid: uid, credentials: credentials);
  }

  Future<VoiceAuthCredentials?> loadByEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedEmail = email.trim().toLowerCase();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (!key.startsWith('voice_auth_email_')) continue;
      final storedEmail = prefs.getString(key);
      if (storedEmail?.toLowerCase() != normalizedEmail) continue;
      final authUid = key.substring('voice_auth_email_'.length);
      return load(authUid);
    }
    return null;
  }

  Future<({String uid, VoiceAuthCredentials credentials, String profileEmail})>
      createVoiceOnlyAccount() async {
    final random = Random.secure();
    final password = _generatePassword(random);
    final stagingEmail =
        'pending_${DateTime.now().millisecondsSinceEpoch}@$_emailDomain';

    final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: stagingEmail,
      password: password,
    );

    final uid = credential.user?.uid;
    if (uid == null) {
      throw StateError('No uid returned from Firebase Auth.');
    }

    final profileEmail = voiceEmailFor(uid);
    final credentials = VoiceAuthCredentials(
      email: stagingEmail,
      password: password,
    );
    await save(uid, credentials);

    return (
      uid: uid,
      credentials: credentials,
      profileEmail: profileEmail,
    );
  }

  Future<void> save(String authUid, VoiceAuthCredentials credentials) async {
    if (authUid.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey(authUid), credentials.email);
    await prefs.setString(_passwordKey(authUid), credentials.password);
  }

  Future<VoiceAuthCredentials?> load(String authUid) async {
    if (authUid.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_emailKey(authUid));
    final password = prefs.getString(_passwordKey(authUid));
    if (email == null || password == null) return null;
    return VoiceAuthCredentials(email: email, password: password);
  }

  String _emailKey(String authUid) => 'voice_auth_email_$authUid';

  String _passwordKey(String authUid) => 'voice_auth_password_$authUid';
}
