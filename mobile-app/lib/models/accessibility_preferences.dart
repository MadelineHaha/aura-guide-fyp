import 'dart:convert';

import '../services/app_settings_service.dart';

/// Reads/writes app settings on `users/{uid}` in Firestore.
///
/// Primary field: [settingsFieldName]. [legacyFieldName] is kept for older docs.
class AccessibilityPreferences {
  AccessibilityPreferences._();

  static const settingsFieldName = 'settings';
  static const legacyFieldName = 'accessibilityPreferences';

  static Map<String, dynamic> defaultMap() => const AppSettings().toMap();

  static dynamic readFromUserDoc(Map<String, dynamic> data) {
    if (data.containsKey(settingsFieldName)) {
      return data[settingsFieldName];
    }
    return data[legacyFieldName];
  }

  static AppSettings fromFirestoreValue(dynamic value) {
    if (value is Map) {
      return AppSettings.fromMap(Map<String, dynamic>.from(value));
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return AppSettings.fromMap(Map<String, dynamic>.from(decoded));
        }
      } catch (_) {
        // Legacy plain-text values are ignored; defaults apply.
      }
    }
    return const AppSettings();
  }

  static Map<String, dynamic> toMap(AppSettings settings) => settings.toMap();

  static bool mapsEqual(Map<String, dynamic> a, Map<String, dynamic> b) {
    return toMap(fromFirestoreValue(a)) == toMap(fromFirestoreValue(b));
  }
}
