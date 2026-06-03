import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Configures Firebase Auth for Android (skips Play Integrity / reCAPTCHA during FYP dev).
Future<void> configureFirebaseAuth() async {
  if (kIsWeb) return;
  await FirebaseAuth.instance.setSettings(
    appVerificationDisabledForTesting: true,
  );
}

/// Returns a user-facing warning if the device clock or HTTPS to Google looks wrong.
Future<String?> firebaseConnectivityWarning() async {
  if (kIsWeb) return null;
  try {
    final client = HttpClient();
    final request = await client.headUrl(Uri.parse('https://www.google.com'));
    final response = await request.close();
    final dateHeader = response.headers.value(HttpHeaders.dateHeader);
    client.close(force: true);
    if (dateHeader != null) {
      final serverTime = HttpDate.parse(dateHeader);
      final skew = serverTime.difference(DateTime.now()).abs();
      if (skew > const Duration(minutes: 3)) {
        return 'Your phone date/time is about ${skew.inMinutes} minutes off. '
            'Turn on Settings → Date & time → Use network-provided time, then try again.';
      }
    }
    return null;
  } on SocketException {
    return 'No internet connection. Check Wi‑Fi or mobile data.';
  } catch (e) {
    final text = e.toString().toLowerCase();
    if (text.contains('chain validation') ||
        text.contains('certificate') ||
        text.contains('handshake')) {
      return 'This device cannot verify Google\'s security certificate. '
          'Fix date & time (automatic), turn off VPN/Private DNS, update Google Play services, '
          'or use an emulator image with the Play Store.';
    }
    return null;
  }
}

String firebaseAuthErrorMessage(FirebaseAuthException e) {
  final msg = (e.message ?? '').toLowerCase();
  if (e.code == 'internal-error' &&
      msg.contains('chain validation failed')) {
    return 'Secure connection failed on this device. '
        'Set date & time to automatic, turn off VPN, update Google Play services, '
        'then uninstall the app and run: flutter clean && flutter run';
  }
  switch (e.code) {
    case 'invalid-email':
      return 'Please enter a valid email address.';
    case 'email-already-in-use':
      return 'This email is already registered. Try logging in instead.';
    case 'weak-password':
      return 'Password is too weak. Follow the requirements above.';
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'Incorrect email or password.';
    case 'user-disabled':
      return 'This account has been disabled.';
    case 'too-many-requests':
      return 'Too many attempts. Wait a few minutes, then try again.';
    case 'network-request-failed':
      return 'No network connection. Check Wi‑Fi or mobile data.';
    case 'operation-not-allowed':
      return 'Email/password sign-in is not enabled in Firebase. Enable it under Authentication → Sign-in method.';
    default:
      return e.message ?? 'Authentication failed (${e.code}).';
  }
}
