import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase config for the Aura Guide Android app (auraguide-46d15).
/// Values match [google-services.json] in android/app/.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('Web is not configured for this mobile app.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for $defaultTargetPlatform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDGaewy9zHwJ46bBp9moSa2wmCm8HdAd_c',
    appId: '1:1031218970443:android:d7d12d421b3a25f04572ce',
    messagingSenderId: '1031218970443',
    projectId: 'auraguide-46d15',
    authDomain: 'auraguide-46d15.firebaseapp.com',
    storageBucket: 'auraguide-46d15.firebasestorage.app',
  );
}
