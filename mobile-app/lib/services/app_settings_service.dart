import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../auth_session.dart';
import '../models/accessibility_preferences.dart';
import '../utils/accessibility_announcement.dart';
import 'system_accessibility_service.dart';
import 'user_profile_service.dart';

class AppSettings {
  const AppSettings({
    this.fontScale = 1.0,
    this.notificationsEnabled = true,
    this.fallDetectionEnabled = true,
    this.voiceAssistantEnabled = true,
    this.voiceOnlyModeEnabled = true,
    this.languageCode = 'en',
  });

  final double fontScale;
  final bool notificationsEnabled;
  final bool fallDetectionEnabled;
  final bool voiceAssistantEnabled;
  final bool voiceOnlyModeEnabled;
  final String languageCode;

  static const languages = <String, String>{
    'en': 'English',
    'ms': 'Bahasa Melayu',
    'zh': '中文',
  };

  factory AppSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) return const AppSettings();
    return AppSettings(
      fontScale: ((map['fontScale'] as num?) ?? 1.0).toDouble().clamp(
        0.85,
        1.35,
      ),
      notificationsEnabled: map['notificationsEnabled'] != false,
      fallDetectionEnabled: map['fallDetectionEnabled'] != false,
      voiceAssistantEnabled: map['voiceAssistantEnabled'] != false,
      voiceOnlyModeEnabled: map['voiceOnlyModeEnabled'] != false,
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
    'fallDetectionEnabled': fallDetectionEnabled,
    'voiceAssistantEnabled': voiceAssistantEnabled,
    'voiceOnlyModeEnabled': voiceOnlyModeEnabled,
    'languageCode': languageCode,
  };

  AppSettings copyWith({
    double? fontScale,
    bool? notificationsEnabled,
    bool? fallDetectionEnabled,
    bool? voiceAssistantEnabled,
    bool? voiceOnlyModeEnabled,
    String? languageCode,
  }) {
    return AppSettings(
      fontScale: fontScale ?? this.fontScale,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      fallDetectionEnabled: fallDetectionEnabled ?? this.fallDetectionEnabled,
      voiceAssistantEnabled:
          voiceAssistantEnabled ?? this.voiceAssistantEnabled,
      voiceOnlyModeEnabled: voiceOnlyModeEnabled ?? this.voiceOnlyModeEnabled,
      languageCode: languageCode ?? this.languageCode,
    );
  }
}

class AppSettingsService extends ChangeNotifier with WidgetsBindingObserver {
  AppSettingsService._({UserProfileService? profileService})
    : _profileService = profileService ?? UserProfileService();

  static final AppSettingsService instance = AppSettingsService._();

  static const _fontKey = 'settings_font_scale';
  static const _notificationsKey = 'settings_notifications';
  static const _fallDetectionKey = 'settings_fall_detection';
  static const _voiceAssistantKey = 'settings_voice_assistant';
  static const _voiceOnlyModeKey = 'settings_voice_only_mode';
  static const _languageKey = 'settings_language';

  final UserProfileService _profileService;
  final FlutterTts _tts = FlutterTts();
  final ValueNotifier<bool> isSpeakingNotifier = ValueNotifier(false);

  AppSettings _settings = const AppSettings();
  bool _ttsReady = false;
  bool _lifecycleAttached = false;
  String? _syncedUid;
  Timer? _firestoreDebounce;
  bool _cloudSaveInFlight = false;
  bool _cloudSaveQueued = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _settingsSub;
  Future<void> Function(bool enabled)? _notificationsPreferenceHandler;
  Future<void> Function()? _afterSettingsSyncHandler;

  static const _emergencySoundChannel = MethodChannel(
    'com.example.aura_guide_fyp/emergency_sound',
  );

  AppSettings get settings => _settings;

  void registerNotificationsPreferenceHandler(
    Future<void> Function(bool enabled) handler,
  ) {
    _notificationsPreferenceHandler = handler;
  }

  void registerAfterSettingsSyncHandler(Future<void> Function() handler) {
    _afterSettingsSyncHandler = handler;
  }

  Future<void> load() async {
    _ensureLifecycleAttached();
    final prefs = await SharedPreferences.getInstance();
    _settings = AppSettings(
      fontScale: prefs.getDouble(_fontKey) ?? 1.0,
      notificationsEnabled: prefs.getBool(_notificationsKey) ?? true,
      fallDetectionEnabled: prefs.getBool(_fallDetectionKey) ?? true,
      voiceAssistantEnabled: prefs.getBool(_voiceAssistantKey) ?? true,
      voiceOnlyModeEnabled: prefs.getBool(_voiceOnlyModeKey) ?? true,
      languageCode: prefs.getString(_languageKey) ?? 'en',
    );

    final uid = _resolveUid();
    if (uid != null) {
      await syncFromFirestore(uid);
    } else {
      await _applyTtsLanguage();
      await _applyPlatformLocale();
      notifyListeners();
    }
  }

  /// Loads `users/{uid}.settings` and keeps listening for remote changes.
  Future<void> syncFromFirestore(String uid) async {
    if (uid.isEmpty) return;
    try {
      final result = await _profileService.loadProfile(
        uid,
        syncAuthFirst: false,
      );
      final raw = AccessibilityPreferences.readFromUserDoc(result.data);
      final cloud = AccessibilityPreferences.fromFirestoreValue(raw);

      _settings = cloud;
      _syncedUid = uid;
      await _saveLocal();
      await _applyTtsLanguage();
      await _applyPlatformLocale();
      notifyListeners();

      _startFirestoreWatch(uid);

      final isEmpty =
          raw == null ||
          (raw is String && raw.trim().isEmpty) ||
          (raw is Map && raw.isEmpty);
      if (isEmpty) {
        await _saveToFirestoreNow();
      }

      final afterSync = _afterSettingsSyncHandler;
      if (afterSync != null) {
        unawaited(afterSync());
      }
    } catch (e) {
      debugPrint('AppSettingsService.syncFromFirestore failed: $e');
    }
  }

  void _startFirestoreWatch(String uid) {
    _settingsSub?.cancel();
    _settingsSub = _profileService
        .doc(uid)
        .snapshots()
        .listen(
          (snap) {
            if (_cloudSaveInFlight || !snap.exists) return;
            final data = snap.data();
            if (data == null) return;

            final raw = AccessibilityPreferences.readFromUserDoc(data);
            final cloud = AccessibilityPreferences.fromFirestoreValue(raw);
            if (AccessibilityPreferences.mapsEqual(
              cloud.toMap(),
              _settings.toMap(),
            )) {
              return;
            }

            _settings = cloud;
            _syncedUid = uid;
            unawaited(_saveLocal());
            unawaited(_applyTtsLanguage());
            unawaited(_applyPlatformLocale());
            notifyListeners();
          },
          onError: (Object error) {
            debugPrint('AppSettingsService settings watch failed: $error');
          },
        );
  }

  void clearCloudSync() {
    _syncedUid = null;
    _firestoreDebounce?.cancel();
    _firestoreDebounce = null;
    _settingsSub?.cancel();
    _settingsSub = null;
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
    final handler = _notificationsPreferenceHandler;
    if (handler != null) {
      unawaited(handler(value));
    }
  }

  Future<void> setFallDetectionEnabled(bool value) async {
    _settings = _settings.copyWith(fallDetectionEnabled: value);
    notifyListeners();
    await _persist();
  }

  Future<void> setVoiceAssistantEnabled(bool value) async {
    final voiceOnly = value ? _settings.voiceOnlyModeEnabled : false;
    _settings = _settings.copyWith(
      voiceAssistantEnabled: value,
      voiceOnlyModeEnabled: voiceOnly,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> setVoiceOnlyModeEnabled(bool value) async {
    _settings = _settings.copyWith(
      voiceOnlyModeEnabled: value,
      voiceAssistantEnabled: value ? true : _settings.voiceAssistantEnabled,
    );
    notifyListeners();
    await _persist();
    if (value) {
      await speakAndAwaitCompletion(
        localized('voiceOnlyModeEnabledAnnouncement'),
      );
    } else {
      await speakAndAwaitCompletion(
        localized('voiceOnlyModeDisabledAnnouncement'),
      );
    }
  }

  Future<void> setLanguageCode(String code) async {
    if (!AppSettings.languages.containsKey(code)) return;
    _settings = _settings.copyWith(languageCode: code);
    _ttsReady = false;
    notifyListeners();
    await _persist();
    await _applyTtsLanguage();
    await _applyPlatformLocale();
    final label = AppSettings.languages[code] ?? 'English';
    final message = localized('languageSpeakPrefix', {'label': label});
    if (SystemAccessibilityService.instance.isScreenReaderActive) {
      await AccessibilityAnnouncement.announce(message);
    } else {
      await speakAndAwaitCompletion(message);
    }
  }

  String get languageLabel =>
      AppSettings.languages[_settings.languageCode] ?? 'English';

  String localized(String key, [Map<String, Object?> params = const {}]) {
    return AppLocalizations(_settings.languageCode).t(key, params);
  }

  String? _lastSpokenText;
  String get lastSpokenText => _lastSpokenText ?? '';
  DateTime? _lastSpeakStartedAt;
  Object? _activeSpeakToken;

  /// Stops any in-progress voice prompt so the mic does not pick it up.
  Future<void> stopSpeaking() async {
    _activeSpeakToken = null;
    isSpeakingNotifier.value = false;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _emergencySoundChannel.invokeMethod<void>('stopEnglishTts');
      } catch (_) {
        // Fall through to flutter_tts stop.
      }
    }
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

    await _tts.awaitSpeakCompletion(true);
    if (_activeSpeakToken != token) return;
    _lastSpokenText = trimmed;
    _lastSpeakStartedAt = now;
    isSpeakingNotifier.value = true;
    await _tts.speak(trimmed);
    if (_activeSpeakToken == token) {
      isSpeakingNotifier.value = false;
    }
  }

  /// Normal-speed speech using the device default TTS engine (e.g. Google TTS).
  Future<void> speakSystemVoice(String text) async {
    await _speakWithSystemVoice(text, speechRate: 1.0);
  }

  /// Slower, clearer speech for navigation obstacle alerts.
  Future<void> speakCalmSystemVoice(String text) async {
    await _speakWithSystemVoice(text, speechRate: 0.50);
  }

  Future<void> _speakWithSystemVoice(
    String text, {
    required double speechRate,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final token = Object();
    _activeSpeakToken = token;

    await _configureSystemVoice(speechRate: speechRate);
    if (_activeSpeakToken != token) return;

    await _tts.stop();
    if (_activeSpeakToken != token) return;

    await _tts.awaitSpeakCompletion(true);
    if (_activeSpeakToken != token) return;
    _lastSpokenText = trimmed;
    _lastSpeakStartedAt = DateTime.now();
    isSpeakingNotifier.value = true;
    await _tts.speak(trimmed);
    if (_activeSpeakToken == token) {
      isSpeakingNotifier.value = false;
    }
  }

  /// Emergency prompts: always standard English at normal speed (not TalkBack voice).
  Future<void> speakEnglishSystemVoice(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final token = Object();
    _activeSpeakToken = token;

    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _emergencySoundChannel.invokeMethod<void>(
          'speakEnglishTts',
          <String, dynamic>{'text': trimmed},
        );
        if (_activeSpeakToken == token) {
          _lastSpokenText = trimmed;
          _lastSpeakStartedAt = DateTime.now();
        }
        return;
      } catch (e) {
        debugPrint('Native English TTS failed, using flutter_tts: $e');
      }
    }

    await _configureEnglishSystemVoice();
    if (_activeSpeakToken != token) return;

    await _tts.stop();
    if (_activeSpeakToken != token) return;

    _lastSpokenText = trimmed;
    _lastSpeakStartedAt = DateTime.now();
    if (!kIsWeb && Platform.isAndroid) {
      await _tts.speak(trimmed, focus: true);
    } else {
      await _tts.speak(trimmed);
    }
  }

  /// Emergency intro: normal-speed English and waits until playback finishes.
  Future<void> speakEnglishSystemVoiceAndAwait(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final token = Object();
    _activeSpeakToken = token;

    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _emergencySoundChannel.invokeMethod<void>(
          'speakEnglishTts',
          <String, dynamic>{'text': trimmed},
        );
        if (_activeSpeakToken == token) {
          _lastSpokenText = trimmed;
          _lastSpeakStartedAt = DateTime.now();
        }
        return;
      } catch (e) {
        debugPrint('Native English TTS await failed, using flutter_tts: $e');
      }
    }

    await _configureEnglishSystemVoice();
    if (_activeSpeakToken != token) return;

    await _tts.stop();
    if (_activeSpeakToken != token) return;

    await _tts.awaitSpeakCompletion(true);
    if (_activeSpeakToken != token) return;
    _lastSpokenText = trimmed;
    _lastSpeakStartedAt = DateTime.now();
    if (!kIsWeb && Platform.isAndroid) {
      await _tts.speak(trimmed, focus: true);
    } else {
      await _tts.speak(trimmed);
    }
  }

  /// Speaks [text] and waits until playback finishes (countdown prompts).
  Future<void> speakAndAwaitCompletion(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final token = Object();
    _activeSpeakToken = token;

    await _ensureTtsReady();
    if (_activeSpeakToken != token) return;

    await _tts.stop();
    if (_activeSpeakToken != token) return;

    await _tts.awaitSpeakCompletion(true);
    if (_activeSpeakToken != token) return;
    _lastSpokenText = trimmed;
    _lastSpeakStartedAt = DateTime.now();
    isSpeakingNotifier.value = true;
    if (!kIsWeb && Platform.isAndroid) {
      await _tts.speak(trimmed, focus: true);
    } else {
      await _tts.speak(trimmed);
    }
    if (_activeSpeakToken != token) return;

    await _tts.awaitSpeakCompletion(true);
    if (_activeSpeakToken == token) {
      isSpeakingNotifier.value = false;
    }
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
    await prefs.setBool(_fallDetectionKey, _settings.fallDetectionEnabled);
    await prefs.setBool(_voiceAssistantKey, _settings.voiceAssistantEnabled);
    await prefs.setBool(_voiceOnlyModeKey, _settings.voiceOnlyModeEnabled);
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
      await _profileService.saveUserSettings(
        uid: uid,
        settings: _settings.toMap(),
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
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.48);
    await _tts.setPitch(1.0);
    await _applyTtsLanguage();
    _ttsReady = true;
  }

  Future<void> _configureSystemVoice({double speechRate = 1.0}) async {
    await _tts.awaitSpeakCompletion(true);
    if (!kIsWeb && Platform.isAndroid) {
      final engine = await _tts.getDefaultEngine;
      if (engine != null && engine.isNotEmpty) {
        await _tts.setEngine(engine);
      }
    }
    await _tts.setSpeechRate(speechRate);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
    await _applyTtsLanguage();
  }

  void _ensureLifecycleAttached() {
    if (_lifecycleAttached) return;
    _lifecycleAttached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_applyPlatformLocale());
    }
  }

  Future<void> _configureEnglishSystemVoice() async {
    await _tts.awaitSpeakCompletion(true);
    await _preferGoogleTtsEngine();
    await _tts.setSpeechRate(1.0);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);

    try {
      await _tts.clearVoice();
    } catch (_) {
      // Optional on some platforms.
    }

    const locales = ['en-US', 'en-GB', 'en-AU', 'en'];
    for (final locale in locales) {
      try {
        final available = await _tts.isLanguageAvailable(locale);
        if (available == true || available == 1) {
          final result = await _tts.setLanguage(locale);
          if (result == 1 || result == true) {
            break;
          }
        }
      } catch (_) {
        // Try the next English locale.
      }
    }

    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      final voicesRaw = await _tts.getVoices;
      if (voicesRaw is! List) return;

      Map<String, String>? bestVoice;
      var bestScore = -1;

      for (final entry in voicesRaw) {
        if (entry is! Map) continue;
        final locale = _normalizeLocale((entry['locale'] ?? '').toString());
        if (!_isEnglishLocale(locale)) continue;

        final name = (entry['name'] ?? '').toString().toLowerCase();
        if (_isRejectedVoice(locale, name)) continue;

        final score = _englishVoiceScore(locale, name);
        if (score > bestScore) {
          bestScore = score;
          bestVoice = {
            'name': entry['name']?.toString() ?? '',
            'locale': entry['locale']?.toString() ?? 'en-US',
          };
        }
      }

      if (bestVoice != null &&
          bestVoice['name']!.isNotEmpty &&
          bestVoice['locale']!.isNotEmpty) {
        await _tts.setVoice(bestVoice);
        await _tts.setLanguage(bestVoice['locale']!);
      }
    } catch (_) {
      // Language-only configuration is still better than device default.
    }
  }

  Future<void> _preferGoogleTtsEngine() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final engines = await _tts.getEngines;
      if (engines is List) {
        for (final engine in engines) {
          final id = engine.toString().toLowerCase();
          if (id.contains('google') && id.contains('tts')) {
            await _tts.setEngine(engine.toString());
            return;
          }
        }
      }
      final defaultEngine = await _tts.getDefaultEngine;
      if (defaultEngine != null && defaultEngine.isNotEmpty) {
        await _tts.setEngine(defaultEngine);
      }
    } catch (_) {
      // Keep the current engine.
    }
  }

  String _normalizeLocale(String locale) {
    return locale.trim().toLowerCase().replaceAll('_', '-');
  }

  bool _isEnglishLocale(String locale) {
    return locale == 'en' || locale.startsWith('en-');
  }

  bool _isRejectedVoice(String locale, String name) {
    if (locale.startsWith('pt') ||
        locale.contains('bra') ||
        name.contains('pt-') ||
        name.contains('pt_') ||
        name.contains('por') ||
        name.contains('fr-') ||
        name.contains('fra')) {
      return true;
    }
    return false;
  }

  int _englishVoiceScore(String locale, String name) {
    var score = 0;
    if (locale == 'en-us') score += 100;
    if (locale == 'en-gb') score += 80;
    if (locale == 'en-au') score += 60;
    if (locale.startsWith('en')) score += 40;
    if (name.contains('en-us')) score += 20;
    if (name.contains('local')) score += 10;
    if (name.contains('network')) score += 5;
    return score;
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

  /// Sets Android app locale so TalkBack uses the selected language in this app.
  Future<void> _applyPlatformLocale() async {
    if (kIsWeb || !Platform.isAndroid) return;

    final tag = switch (_settings.languageCode) {
      'ms' => 'ms-MY',
      'zh' => 'zh-CN',
      _ => 'en',
    };
    try {
      await _emergencySoundChannel.invokeMethod<void>(
        'setAppLocale',
        <String, dynamic>{'languageTag': tag},
      );
    } catch (error) {
      debugPrint('AppSettingsService setAppLocale failed: $error');
    }
  }
}
