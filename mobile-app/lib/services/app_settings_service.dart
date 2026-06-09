import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  const AppSettings({
    this.audioFeedbackEnabled = false,
    this.fontScale = 1.0,
    this.notificationsEnabled = true,
    this.languageCode = 'en',
  });

  final bool audioFeedbackEnabled;
  final double fontScale;
  final bool notificationsEnabled;
  final String languageCode;

  static const languages = <String, String>{
    'en': 'English',
    'ms': 'Bahasa Melayu',
    'zh': '中文',
  };

  AppSettings copyWith({
    bool? audioFeedbackEnabled,
    double? fontScale,
    bool? notificationsEnabled,
    String? languageCode,
  }) {
    return AppSettings(
      audioFeedbackEnabled: audioFeedbackEnabled ?? this.audioFeedbackEnabled,
      fontScale: fontScale ?? this.fontScale,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      languageCode: languageCode ?? this.languageCode,
    );
  }
}

class AppSettingsService extends ChangeNotifier {
  AppSettingsService._();

  static final AppSettingsService instance = AppSettingsService._();

  static const _audioKey = 'settings_audio_feedback';
  static const _fontKey = 'settings_font_scale';
  static const _notificationsKey = 'settings_notifications';
  static const _languageKey = 'settings_language';

  AppSettings _settings = const AppSettings();
  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;

  AppSettings get settings => _settings;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _settings = AppSettings(
      audioFeedbackEnabled: prefs.getBool(_audioKey) ?? false,
      fontScale: prefs.getDouble(_fontKey) ?? 1.0,
      notificationsEnabled: prefs.getBool(_notificationsKey) ?? true,
      languageCode: prefs.getString(_languageKey) ?? 'en',
    );
    notifyListeners();
  }

  Future<void> setAudioFeedbackEnabled(bool value) async {
    _settings = _settings.copyWith(audioFeedbackEnabled: value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_audioKey, value);
    if (value) {
      await speak(
        'Audio feedback enabled. Swipe right for next, swipe left for previous. Double tap to activate.',
      );
    } else {
      await _tts.stop();
    }
  }

  Future<void> setFontScale(double value) async {
    final clamped = value.clamp(0.85, 1.35);
    _settings = _settings.copyWith(fontScale: clamped);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontKey, clamped);
  }

  Future<void> setNotificationsEnabled(bool value) async {
    _settings = _settings.copyWith(notificationsEnabled: value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsKey, value);
  }

  Future<void> setLanguageCode(String code) async {
    _settings = _settings.copyWith(languageCode: code);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, code);
    await _applyTtsLanguage();
  }

  String get languageLabel =>
      AppSettings.languages[_settings.languageCode] ?? 'English';

  Future<void> speakIfEnabled(String text) async {
    if (!_settings.audioFeedbackEnabled) return;
    await speak(text);
  }

  Future<void> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    await _ensureTtsReady();
    await _tts.stop();
    await _tts.speak(trimmed);
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
