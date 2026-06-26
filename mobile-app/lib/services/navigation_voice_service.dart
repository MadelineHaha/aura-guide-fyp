import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'app_settings_service.dart';

/// Thin Text-To-Speech wrapper for navigation and obstacle voice output.
class NavigationVoiceService {
  NavigationVoiceService._();

  static final NavigationVoiceService instance = NavigationVoiceService._();

  final FlutterTts _tts = FlutterTts();
  final _settings = AppSettingsService.instance;

  var _initialized = false;
  String? _lastSpokenText;
  DateTime? _lastSpokenAt;

  static const _cooldown = Duration(seconds: 5);

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _tts.setLanguage(_ttsLanguageCode());
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
      await _tts.awaitSpeakCompletion(false);
      _initialized = true;
    } catch (error) {
      debugPrint('NavigationVoiceService initialize failed: $error');
    }
  }

  /// Speaks [text], stopping any in-progress speech first.
  /// Skips duplicate text spoken within [_cooldown] unless [force] is true.
  Future<void> speak(String text, {bool force = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (!_initialized) await initialize();

    final now = DateTime.now();
    if (!force &&
        _lastSpokenText == trimmed &&
        _lastSpokenAt != null &&
        now.difference(_lastSpokenAt!) < _cooldown) {
      return;
    }

    try {
      await stop();
      await _tts.speak(trimmed);
      _lastSpokenText = trimmed;
      _lastSpokenAt = now;
    } catch (error) {
      debugPrint('NavigationVoiceService speak failed: $error');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (error) {
      debugPrint('NavigationVoiceService stop failed: $error');
    }
  }

  Future<void> dispose() async {
    await stop();
    _initialized = false;
    _lastSpokenText = null;
    _lastSpokenAt = null;
  }

  void clearDuplicateGuard() {
    _lastSpokenText = null;
    _lastSpokenAt = null;
  }

  String _ttsLanguageCode() {
    return switch (_settings.settings.languageCode) {
      'ms' => 'ms-MY',
      'zh' => 'zh-CN',
      _ => 'en-US',
    };
  }
}
