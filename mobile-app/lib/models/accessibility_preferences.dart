import 'dart:convert';

import '../services/app_settings_service.dart';

/// Reads/writes the `users.accessibilityPreferences` Firestore field.
class AccessibilityPreferences {
  AccessibilityPreferences._();

  static const fieldName = 'accessibilityPreferences';

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
}
