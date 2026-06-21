import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'activity_log_actions.dart';
import 'activity_log_service.dart';
import 'app_settings_service.dart';
import 'device_permissions_service.dart';
import 'voice_assistant_coordinator.dart';

/// Shared speech-to-text helper for form fields and search bars.
class FieldSpeechInput extends ChangeNotifier {
  FieldSpeechInput._();

  static final FieldSpeechInput instance = FieldSpeechInput._();

  factory FieldSpeechInput() => instance;

  final SpeechToText _speech = SpeechToText();

  bool _ready = false;
  bool _listening = false;
  String? _localeId;
  TextEditingController? _activeController;
  bool _callbackSession = false;
  String _lastRecognized = '';
  int _listenSession = 0;

  bool get isListening => _listening;

  bool get isCallbackListening => _listening && _callbackSession;

  bool isListeningFor(TextEditingController controller) {
    return _listening && identical(_activeController, controller);
  }

  Future<String?> _voiceInputFailure(String details) async {
    unawaited(
      ActivityLogService.instance.logWarning(
        action: ActivityLogActions.voiceRecognitionFailure,
        details: details,
      ),
    );
    return details.startsWith('Microphone')
        ? 'Microphone permission is required. Please allow microphone access in your device settings.'
        : 'Voice input is not available: $details';
  }

  Future<String?> toggleForController(
    TextEditingController controller, {
    ListenMode listenMode = ListenMode.dictation,
  }) async {
    if (_listening && identical(_activeController, controller)) {
      await stop();
      return null;
    }

    if (_listening) {
      await stop();
    }

    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
    if (!micGranted) {
      return _voiceInputFailure('Microphone permission denied for voice input.');
    }

    try {
      await _ensureReady();
    } catch (error) {
      return _voiceInputFailure(error.toString());
    }

    _activeController = controller;
    _callbackSession = false;
    _listening = true;
    _lastRecognized = '';
    final session = ++_listenSession;
    VoiceAssistantCoordinator.instance.acquireMicLock();
    notifyListeners();

    try {
      await _speech.cancel();
    } catch (_) {}

    await Future<void>.delayed(const Duration(milliseconds: 250));

    if (!_listening || session != _listenSession) {
      return null;
    }

    try {
      await _speech.listen(
        onResult: (result) {
          if (session != _listenSession || _activeController == null) return;

          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            _lastRecognized = words;
            _activeController!.value = TextEditingValue(
              text: words,
              selection: TextSelection.collapsed(offset: words.length),
            );
            notifyListeners();
          }

          if (result.finalResult) {
            unawaited(stop());
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        localeId: _localeId,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: listenMode,
        ),
      );
    } catch (error) {
      await stop();
      return 'Could not start voice input: $error';
    }

    return null;
  }

  Future<String?> toggleForCallback({
    required ValueChanged<String> onText,
    ListenMode listenMode = ListenMode.dictation,
  }) async {
    if (_listening && _callbackSession) {
      await stop();
      return null;
    }

    if (_listening) {
      await stop();
    }

    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
    if (!micGranted) {
      return _voiceInputFailure('Microphone permission denied for voice input.');
    }

    try {
      await _ensureReady();
    } catch (error) {
      return _voiceInputFailure(error.toString());
    }

    _activeController = null;
    _callbackSession = true;
    _lastRecognized = '';
    _listening = true;
    final session = ++_listenSession;
    VoiceAssistantCoordinator.instance.acquireMicLock();
    notifyListeners();

    try {
      await _speech.cancel();
    } catch (_) {}

    await Future<void>.delayed(const Duration(milliseconds: 250));

    if (!_listening || session != _listenSession) {
      return null;
    }

    try {
      await _speech.listen(
        onResult: (result) {
          if (session != _listenSession) return;

          final words = result.recognizedWords.trim();
          if (words.isNotEmpty) {
            _lastRecognized = words;
            notifyListeners();
          }
          if (result.finalResult) {
            final heard = words.isNotEmpty ? words : _lastRecognized;
            if (heard.isNotEmpty) {
              onText(heard);
            }
            unawaited(stop());
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        localeId: _localeId,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: listenMode,
        ),
      );
    } catch (error) {
      await stop();
      return 'Could not start voice input: $error';
    }

    return null;
  }

  Future<void> stop() async {
    if (!_listening) return;

    _listenSession++;
    try {
      await _speech.stop();
    } catch (_) {}

    _listening = false;
    _activeController = null;
    _callbackSession = false;
    _lastRecognized = '';
    VoiceAssistantCoordinator.instance.releaseMicLock();
    notifyListeners();
  }

  Future<void> _ensureReady() async {
    _localeId = await _resolveLocale();

    if (_ready) return;

    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done') {
          unawaited(stop());
        }
      },
      onError: (error) {
        debugPrint('FieldSpeechInput error: $error');
        unawaited(stop());
      },
    );
    if (!available) {
      throw StateError('Speech recognition is not available on this device.');
    }

    _ready = true;
  }

  Future<String?> _resolveLocale() async {
    final lang = AppSettingsService.instance.settings.languageCode;
    final preferred = switch (lang) {
      'zh' => const ['zh_CN', 'zh_TW', 'zh_HK', 'zh_SG', 'zh'],
      'ms' => const ['ms_MY', 'ms'],
      _ => const ['en_MY', 'en_US', 'en_GB', 'en_SG', 'en_AU', 'en'],
    };

    try {
      final locales = await _speech.locales();
      for (final id in preferred) {
        if (locales.any((locale) => locale.localeId == id)) {
          return id;
        }
      }
      if (locales.isNotEmpty) return locales.first.localeId;
    } catch (error) {
      debugPrint('FieldSpeechInput locale lookup failed: $error');
    }
    return preferred.last;
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}
