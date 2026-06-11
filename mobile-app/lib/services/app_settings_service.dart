import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_session.dart';
import '../models/accessibility_preferences.dart';
import 'user_profile_service.dart';

class AppSettings {
  const AppSettings({
    this.fontScale = 1.0,
    this.notificationsEnabled = true,
    this.languageCode = 'en',
  });

  final double fontScale;
  final bool notificationsEnabled;
  final String languageCode;

  static const languages = <String, String>{
    'en': 'English',
    'ms': 'Bahasa Melayu',
    'zh': '中文',
  };

  factory AppSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) return const AppSettings();
    return AppSettings(
      fontScale: ((map['fontScale'] as num?) ?? 1.0).toDouble().clamp(0.85, 1.35),
      notificationsEnabled: map['notificationsEnabled'] != false,
      languageCode: _languageFromMap(map['languageCode']),
    );
  }

  static String _languageFromMap(dynamic code) {
    final value = (code is String ? code : code?.toString() ?? '').trim();
    if (languages.containsKey(value)) return value;
    return 'en';
  }

  Map<String, dynamic> toMap() => {
        'fontScale': fontScale,
        'notificationsEnabled': notificationsEnabled,
        'languageCode': languageCode,
      };

  AppSettings copyWith({
    double? fontScale,
    bool? notificationsEnabled,
    String? languageCode,
  }) {
    return AppSettings(
      fontScale: fontScale ?? this.fontScale,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      languageCode: languageCode ?? this.languageCode,
    );
  }
}

class AppSettingsService extends ChangeNotifier {
  AppSettingsService._({UserProfileService? profileService})
      : _profileService = profileService ?? UserProfileService();

  static final AppSettingsService instance = AppSettingsService._();

  static const _fontKey = 'settings_font_scale';
  static const _notificationsKey = 'settings_notifications';
  static const _languageKey = 'settings_language';

  final UserProfileService _profileService;
  final FlutterTts _tts = FlutterTts();

  AppSettings _settings = const AppSettings();
  bool _ttsReady = false;
  String? _syncedUid;
  Timer? _firestoreDebounce;
  bool _cloudSaveInFlight = false;
  bool _cloudSaveQueued = false;

  AppSettings get settings => _settings;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _settings = AppSettings(
      fontScale: prefs.getDouble(_fontKey) ?? 1.0,
      notificationsEnabled: prefs.getBool(_notificationsKey) ?? true,
      languageCode: prefs.getString(_languageKey) ?? 'en',
    );
    notifyListeners();

    final uid = _resolveUid();
    if (uid != null) {
      await syncFromFirestore(uid);
    }
  }

  /// Loads `users/{uid}.accessibilityPreferences` and applies them locally.
  Future<void> syncFromFirestore(String uid) async {
    if (uid.isEmpty) return;
    try {
      final result = await _profileService.loadProfile(uid, syncAuthFirst: false);
      final raw = result.data[AccessibilityPreferences.fieldName];
      final cloud = AccessibilityPreferences.fromFirestoreValue(raw);

      _settings = cloud;
      _syncedUid = uid;
      await _saveLocal();
      await _applyTtsLanguage();
      notifyListeners();

      if (raw == null ||
          (raw is String && raw.trim().isEmpty) ||
          (raw is Map && raw.isEmpty)) {
        await _saveToFirestoreNow();
      }
    } catch (e) {
      debugPrint('AppSettingsService.syncFromFirestore failed: $e');
    }
  }

  void clearCloudSync() {
    _syncedUid = null;
    _firestoreDebounce?.cancel();
    _firestoreDebounce = null;
  }

  Future<void> setFontScale(double value) async {
    final clamped = value.clamp(0.85, 1.35);
    _settings = _settings.copyWith(fontScale: clamped);
    notifyListeners();
    await _persist(debounceCloud: true);
  }

  Future<void> setNotificationsEnabled(bool value) async {
    _settings = _settings.copyWith(notificationsEnabled: value);
    notifyListeners();
    await _persist();
  }

  Future<void> setLanguageCode(String code) async {
    if (!AppSettings.languages.containsKey(code)) return;
    _settings = _settings.copyWith(languageCode: code);
    notifyListeners();
    await _persist();
    await _applyTtsLanguage();
  }

  String get languageLabel =>
      AppSettings.languages[_settings.languageCode] ?? 'English';

  String? _lastSpokenText;
  DateTime? _lastSpeakStartedAt;
  Object? _activeSpeakToken;

  /// Stops any in-progress voice prompt so the mic does not pick it up.
  Future<void> stopSpeaking() async {
    _activeSpeakToken = null;
    try {
      await _tts.stop();
    } catch (_) {
      // Ignore stop errors when nothing is playing.
    }
  }

  /// Short TTS prompts (e.g. voice passphrase retake). TalkBack is used for UI.
  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final now = DateTime.now();
    if (trimmed == _lastSpokenText &&
        _lastSpeakStartedAt != null &&
        now.difference(_lastSpeakStartedAt!) <
            const Duration(milliseconds: 900)) {
      return;
    }

    final token = Object();
    _activeSpeakToken = token;

    await _ensureTtsReady();
    if (_activeSpeakToken != token) return;

    await _tts.stop();
    if (_activeSpeakToken != token) return;

    _lastSpokenText = trimmed;
    _lastSpeakStartedAt = now;
    await _tts.speak(trimmed);
  }

  Future<void> _persist({bool debounceCloud = false}) async {
    await _saveLocal();
    if (debounceCloud) {
      _scheduleCloudSave();
      return;
    }
    await _saveToFirestoreNow();
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontKey, _settings.fontScale);
    await prefs.setBool(_notificationsKey, _settings.notificationsEnabled);
    await prefs.setString(_languageKey, _settings.languageCode);
  }

  void _scheduleCloudSave() {
    _firestoreDebounce?.cancel();
    _firestoreDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_saveToFirestoreNow());
    });
  }

  Future<void> _saveToFirestoreNow() async {
    final uid = _syncedUid ?? _resolveUid();
    if (uid == null || uid.isEmpty) return;

    if (_cloudSaveInFlight) {
      _cloudSaveQueued = true;
      return;
    }

    _cloudSaveInFlight = true;
    try {
      await _profileService.saveAccessibilityPreferences(
        uid: uid,
        preferences: AccessibilityPreferences.toMap(_settings),
      );
      _syncedUid = uid;
    } catch (e) {
      debugPrint('AppSettingsService cloud save failed: $e');
    } finally {
      _cloudSaveInFlight = false;
      if (_cloudSaveQueued) {
        _cloudSaveQueued = false;
        await _saveToFirestoreNow();
      }
    }
  }

  String? _resolveUid() {
    final user = AuthSession.resolveUser() ?? FirebaseAuth.instance.currentUser;
    return user?.uid;
  }

  Future<void> _ensureTtsReady() async {
    if (_ttsReady) return;
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _applyTtsLanguage();
    _ttsReady = true;
  }

  Future<void> _applyTtsLanguage() async {
    final code = switch (_settings.languageCode) {
      'ms' => 'ms-MY',
      'zh' => 'zh-CN',
      _ => 'en-US',
    };
    try {
      await _tts.setLanguage(code);
    } catch (_) {
      // Device default is acceptable.
    }
  }
}
