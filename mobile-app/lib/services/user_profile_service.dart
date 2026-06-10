import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth_session.dart';
import '../models/accessibility_preferences.dart';

/// Loads and saves `users/{uid}` — document id must match Firebase Auth uid.
class UserProfileService {
  UserProfileService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  DocumentReference<Map<String, dynamic>> doc(String uid) =>
      _firestore.collection('users').doc(uid);

  /// Sync Auth email into Firestore, then read `users/{uid}`.
  Future<ProfileLoadResult> loadProfile(
    String uid, {
    bool syncAuthFirst = true,
  }) async {
    final authEmail = await _currentAuthEmail();
    if (syncAuthFirst) {
      await syncEmailFromAuth(uid);
    }

    var data = await _readDoc(doc(uid));
    if (_hasCoreFields(data)) {
      return ProfileLoadResult(
        data: _withAuthEmail(data, authEmail),
        authUid: uid,
        found: true,
      );
    }

    // Fallback: find profile by email (e.g. legacy doc id).
    if (authEmail.isNotEmpty) {
      final matches = await _firestore
          .collection('users')
          .where('email', isEqualTo: authEmail)
          .limit(5)
          .get();
      for (final match in matches.docs) {
        if (!_hasCoreFields(match.data())) continue;
        final merged = _mergePreferNonEmpty(match.data(), data);
        merged['authUid'] = uid;
        merged['email'] = authEmail;
        await doc(uid).set(merged, SetOptions(merge: true));
        data = await _readDoc(doc(uid));
        return ProfileLoadResult(
          data: _withAuthEmail(data, authEmail),
          authUid: uid,
          found: true,
          recoveredFromDocId: match.id,
        );
      }
    }

    return ProfileLoadResult(
      data: _withAuthEmail(data, authEmail),
      authUid: uid,
      found: data.isNotEmpty,
    );
  }

  Future<bool> syncEmailFromAuth(String uid) async {
    final user = AuthSession.resolveUser();
    if (user == null) return false;

    var authEmail = (user.email ?? '').trim();
    var verified = user.emailVerified;
    // Reload only when we have a live Auth user — avoids clearing currentUser
    // during profile open while the auth gate still shows Main Menu.
    if (_auth.currentUser != null) {
      try {
        await user.reload();
        authEmail = (AuthSession.resolveUser()?.email ?? authEmail).trim();
        verified = AuthSession.resolveUser()?.emailVerified ?? verified;
      } catch (_) {}
    }

    if (authEmail.isEmpty) return false;

    await doc(uid).set({
      'authUid': uid,
      'email': authEmail,
      'emailVerified': verified,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return true;
  }

  Future<void> saveAccessibilityPreferences({
    required String uid,
    required Map<String, dynamic> preferences,
  }) async {
    await doc(uid).set({
      'authUid': uid,
      AccessibilityPreferences.fieldName: preferences,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> saveProfileFields({
    required String uid,
    String? name,
    String? phoneNumber,
    String? address,
  }) async {
    final payload = <String, dynamic>{
      'authUid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
      'pendingEmail': FieldValue.delete(),
    };
    if (name != null && name.trim().isNotEmpty) payload['name'] = name.trim();
    if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
      payload['phoneNumber'] = phoneNumber.trim();
    }
    if (address != null && address.trim().isNotEmpty) {
      payload['address'] = address.trim();
    }
    await doc(uid).set(payload, SetOptions(merge: true));
  }

  Future<String> _currentAuthEmail() async {
    final user = AuthSession.resolveUser();
    if (user == null) return '';
    if (_auth.currentUser != null) {
      try {
        await user.reload();
      } catch (_) {}
    }
    return (AuthSession.resolveUser()?.email ?? user.email ?? '').trim();
  }

  Future<Map<String, dynamic>> _readDoc(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final snap = await ref.get(const GetOptions(source: Source.serverAndCache));
      if (!snap.exists) return {};
      return Map<String, dynamic>.from(snap.data() ?? {});
    } catch (_) {
      final snap = await ref.get();
      if (!snap.exists) return {};
      return Map<String, dynamic>.from(snap.data() ?? {});
    }
  }

  bool _hasCoreFields(Map<String, dynamic> data) {
    return _str(data['userId']).isNotEmpty ||
        _str(data['name']).isNotEmpty ||
        data['birthDate'] is Timestamp;
  }

  Map<String, dynamic> _withAuthEmail(
    Map<String, dynamic> data,
    String authEmail,
  ) {
    final out = Map<String, dynamic>.from(data);
    if (authEmail.isNotEmpty) out['email'] = authEmail;
    return out;
  }

  Map<String, dynamic> _mergePreferNonEmpty(
    Map<String, dynamic> primary,
    Map<String, dynamic> secondary,
  ) {
    final merged = Map<String, dynamic>.from(primary);
    for (final e in secondary.entries) {
      final v = e.value;
      if (v == null) continue;
      if (v is String && v.trim().isEmpty) continue;
      merged[e.key] = v;
    }
    return merged;
  }

  String _str(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    return v.toString();
  }
}

class ProfileLoadResult {
  const ProfileLoadResult({
    required this.data,
    required this.authUid,
    required this.found,
    this.recoveredFromDocId,
  });

  final Map<String, dynamic> data;
  final String authUid;
  final bool found;
  final String? recoveredFromDocId;
}
