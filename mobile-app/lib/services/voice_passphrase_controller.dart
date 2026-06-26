import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/voice_capture_result.dart';
import '../utils/accessibility_announcement.dart';
import 'app_settings_service.dart';
import 'device_permissions_service.dart';
import 'system_accessibility_service.dart';
import 'voice_audio_recorder_service.dart';
import 'voice_embedding_service.dart';
import 'voice_passphrase.dart';
import 'voice_profile_service.dart';

/// Records speech and validates the "Sign me in" passphrase.
class VoicePassphraseController extends ChangeNotifier {
  VoicePassphraseController({
    SpeechToText? speech,
    VoiceProfileService? voiceProfile,
    VoiceAudioRecorderService? audioRecorder,
    this.onValidCapture,
  })  : _speech = speech ?? SpeechToText(),
        _voiceProfile = voiceProfile ?? VoiceProfileService(),
        _audioRecorder = audioRecorder ?? VoiceAudioRecorderService();

  final SpeechToText _speech;
  final VoiceProfileService _voiceProfile;
  final VoiceAudioRecorderService _audioRecorder;
  final Future<void> Function(VoiceCaptureResult result)? onValidCapture;

  final _embeddings = VoiceEmbeddingService.instance;

  bool _initialized = false;
  bool _isRecording = false;
  bool _hasValidSample = false;
  bool _captureProcessed = false;
  bool _invalidFeedbackSpoken = false;
  int _feedbackGeneration = 0;
  String _capturedPhrase = '';
  String _bestPhrase = '';
  String? _accessibilityMessage;
  String? _passphraseLocaleId;
  List<double> _voiceprintVector = const [];
  Map<String, dynamic> _voiceFeatures = const {};
  Timer? _finalizeTimer;
  Timer? _recordingLimitTimer;

  static const _recordingLimit = Duration(seconds: 8);

  bool get isRecording => _isRecording;
  bool get hasValidSample => _hasValidSample;
  String get capturedPhrase => _capturedPhrase;
  String get heardPreview => _capturedPhrase;
  String? get accessibilityMessage => _accessibilityMessage;
  List<double> get voiceprintVector => _voiceprintVector;
  Map<String, dynamic> get voiceFeatures => _voiceFeatures;

  VoiceCaptureResult? get captureResult {
    if (!_hasValidSample || _capturedPhrase.isEmpty) return null;
    return VoiceCaptureResult(
      phrase: _capturedPhrase,
      voiceprintVector: _voiceprintVector,
      voiceFeatures: _voiceFeatures,
    );
  }

  Future<String?> startRecording({bool allowOverwrite = false}) async {
    if (_isRecording) return null;
    if (_hasValidSample && !allowOverwrite) return null;

    _finalizeTimer?.cancel();
    _recordingLimitTimer?.cancel();
    _cancelFeedback();
    _accessibilityMessage = null;
    _invalidFeedbackSpoken = false;
    _voiceprintVector = const [];
    _voiceFeatures = const {};
    _bestPhrase = '';
    _capturedPhrase = '';
    notifyListeners();

    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
    if (!micGranted) {
      return 'Microphone permission is required. Please allow microphone access in your device settings.';
    }

    if (!_initialized) {
      final available = await _speech.initialize(
        onStatus: (status) {
          if (status == 'done') {
            _scheduleFinalize(requireHeardSpeech: true);
          }
        },
        onError: (error) {
          debugPrint('VoicePassphraseController STT error: $error');
        },
      );
      if (!available) {
        return 'Microphone permission is required.';
      }
      _initialized = true;
    }

    _passphraseLocaleId ??= await _resolvePassphraseLocale();

    _isRecording = true;
    _hasValidSample = false;
    _captureProcessed = false;
    notifyListeners();

    try {
      await _speech.cancel();
    } catch (_) {}

    await _discardAudioCapture();
    try {
      await _audioRecorder.start();
    } catch (error) {
      debugPrint('VoicePassphraseController audio start failed: $error');
    }

    if (Platform.isAndroid) {
      _startRecordingLimitTimer();
      return null;
    }

    await _speech.listen(
      listenFor: _recordingLimit,
      pauseFor: const Duration(seconds: 2),
      localeId: _passphraseLocaleId,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.confirmation,
      ),
      onResult: (result) {
        final raw = result.recognizedWords;
        final normalized = _voiceProfile.normalize(raw);
        if (normalized.isNotEmpty) {
          _capturedPhrase = normalized;
          _bestPhrase = normalized;
          notifyListeners();
        }

        if (VoicePassphrase.isSignMeIn(raw) ||
            VoicePassphrase.isSignMeIn(normalized)) {
          unawaited(_acceptCapture(normalized.isEmpty ? raw : normalized));
          return;
        }

        if (result.finalResult) {
          _scheduleFinalize(preferredPhrase: normalized);
        }
      },
    );

    _startRecordingLimitTimer();

    return null;
  }

  Future<void> stopRecording() async {
    if (!_isRecording) return;
    _finalizeTimer?.cancel();
    _recordingLimitTimer?.cancel();
    await _finalizeCapture(requireHeardSpeech: true);
  }

  void _startRecordingLimitTimer() {
    _recordingLimitTimer?.cancel();
    _recordingLimitTimer = Timer(_recordingLimit, () {
      if (_captureProcessed || !_isRecording) return;
      unawaited(_finalizeCapture(requireHeardSpeech: true));
    });
  }

  Future<String?> _resolvePassphraseLocale() async {
    final appLanguage = AppSettingsService.instance.settings.languageCode;
    final List<String> preferred;
    if (appLanguage == 'ms') {
      preferred = ['ms_MY', 'ms'];
    } else if (appLanguage == 'zh') {
      preferred = ['zh_CN', 'zh_HK', 'zh_TW', 'zh'];
    } else {
      preferred = ['en_US', 'en_GB', 'en_AU', 'en_SG', 'en'];
    }
    try {
      final locales = await _speech.locales();
      for (final id in preferred) {
        if (locales.any((locale) => locale.localeId == id)) {
          return id;
        }
      }
      for (final locale in locales) {
        if (locale.localeId.toLowerCase().startsWith(appLanguage.toLowerCase())) {
          return locale.localeId;
        }
      }
      if (locales.isNotEmpty) return locales.first.localeId;
    } catch (e) {
      debugPrint('VoicePassphraseController locale lookup failed: $e');
    }
    return 'en_US';
  }

  void _scheduleFinalize({
    String? preferredPhrase,
    bool requireHeardSpeech = false,
  }) {
    _finalizeTimer?.cancel();
    _finalizeTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(
        _finalizeCapture(
          preferredPhrase: preferredPhrase,
          requireHeardSpeech: requireHeardSpeech,
        ),
      );
    });
  }

  Future<void> _acceptCapture(String phrase) async {
    if (_captureProcessed) return;
    _finalizeTimer?.cancel();

    await _finishRecording();
    await _finalizeVoiceprintFromAudio();

    if (!VoiceEmbeddingService.isUsableVoiceprint(_voiceprintVector)) {
      await _rejectCapture(
        debugHeard: phrase,
        message: AppSettingsService.instance
            .localized('voicePassphraseCaptureFailed'),
      );
      return;
    }

    _captureProcessed = true;
    _capturedPhrase = VoicePassphrase.normalize(phrase);
    _hasValidSample = true;
    notifyListeners();
    await _announceFeedback(
      AppSettingsService.instance.localized('voicePassphraseCaptureSuccess'),
    );

    final result = captureResult;
    if (result != null) {
      await onValidCapture?.call(result);
    }
  }

  Future<void> _finalizeCapture({
    String? preferredPhrase,
    bool requireHeardSpeech = false,
  }) async {
    debugPrint('VoicePassphraseController: _finalizeCapture start. requireHeardSpeech = $requireHeardSpeech');
    if (_captureProcessed) {
      debugPrint('VoicePassphraseController: _finalizeCapture early return, already processed');
      return;
    }

    var phrase = _pickPhrase(preferredPhrase);
    debugPrint('VoicePassphraseController: _finalizeCapture initial phrase = "$phrase"');

    // Stop recording and retrieve audio embedding first.
    await _finishRecording();
    await _finalizeVoiceprintFromAudio();

    if (phrase.isEmpty && Platform.isAndroid) {
      debugPrint('VoicePassphraseController: Android empty phrase fallback check');
      if (VoiceEmbeddingService.isUsableVoiceprint(_voiceprintVector)) {
        phrase = 'sign me in';
        debugPrint('VoicePassphraseController: Android fallback to "sign me in"');
      } else {
        debugPrint('VoicePassphraseController: Android fallback failed - voiceprint not usable');
      }
    }

    if (phrase.isEmpty) {
      debugPrint('VoicePassphraseController: phrase is empty, requireHeardSpeech = $requireHeardSpeech');
      if (requireHeardSpeech) {
        await _rejectCapture();
      }
      return;
    }

    if (VoicePassphrase.isSignMeIn(phrase)) {
      debugPrint('VoicePassphraseController: phrase is valid passphrase, accepting capture');
      await _acceptCapture(phrase);
      return;
    }

    debugPrint('VoicePassphraseController: phrase "$phrase" is invalid passphrase, rejecting');
    await _rejectCapture(
      debugHeard: phrase,
    );
  }

  Future<void> _finalizeVoiceprintFromAudio() async {
    try {
      final wavBytes = await _audioRecorder.stop();
      _applyAudioEmbedding(wavBytes);
    } catch (error) {
      debugPrint('VoicePassphraseController voiceprint finalize failed: $error');
    }
  }

  Future<void> _discardAudioCapture() async {
    try {
      await _audioRecorder.stop();
    } catch (_) {}
  }

  String _pickPhrase(String? preferredPhrase) {
    if (preferredPhrase != null && preferredPhrase.trim().isNotEmpty) {
      return preferredPhrase.trim();
    }
    if (_bestPhrase.isNotEmpty) return _bestPhrase;
    return _capturedPhrase;
  }

  void _cancelFeedback() {
    _feedbackGeneration++;
    unawaited(AppSettingsService.instance.stopSpeaking());
  }

  Future<void> _finishRecording() async {
    _recordingLimitTimer?.cancel();
    if (!_isRecording) return;
    try {
      await _speech.stop();
    } catch (_) {}
    _isRecording = false;
    notifyListeners();
  }

  void _applyAudioEmbedding(Uint8List? wavBytes) {
    if (wavBytes == null) {
      debugPrint('VoicePassphraseController: wavBytes is null');
      return;
    }
    debugPrint('VoicePassphraseController: wavBytes length = ${wavBytes.length}');
    if (wavBytes.isEmpty) return;

    final vector = _embeddings.extractFromWav(wavBytes);
    final decodedDurationMs = _estimateDurationMs(wavBytes);
    _voiceprintVector = vector;
    _voiceFeatures = _embeddings.buildFeatures(
      vector: vector,
      sampleRate: 16000,
      durationMs: decodedDurationMs,
    );
    debugPrint('VoicePassphraseController: extracted vector size = ${vector.length}, isUsable = ${VoiceEmbeddingService.isUsableVoiceprint(vector)}');
  }

  int _estimateDurationMs(Uint8List wavBytes) {
    if (wavBytes.length <= 44) return 0;
    final dataBytes = wavBytes.length - 44;
    final sampleCount = dataBytes ~/ 2;
    return ((sampleCount / 16000) * 1000).round();
  }

  Future<void> _rejectCapture({
    String debugHeard = '',
    String? message,
  }) async {
    if (_invalidFeedbackSpoken) return;

    await _discardAudioCapture();
    _captureProcessed = true;
    _capturedPhrase = debugHeard;
    _bestPhrase = '';
    _hasValidSample = false;
    _voiceprintVector = const [];
    _voiceFeatures = const {};
    notifyListeners();

    if (kDebugMode && debugHeard.isNotEmpty) {
      debugPrint('VoicePassphraseController rejected heard: "$debugHeard"');
    }

    await _announceFeedback(
      message ??
          AppSettingsService.instance.localized('voicePassphraseRetake'),
      invalidOnlyOnce: true,
    );
  }

  Future<void> _announceFeedback(
    String message, {
    bool invalidOnlyOnce = false,
  }) async {
    final once = invalidOnlyOnce;
    if (once && _invalidFeedbackSpoken) return;

    final generation = _feedbackGeneration;

    _accessibilityMessage = message;
    notifyListeners();

    await _waitForNextFrame();
    if (!_isFeedbackCurrent(generation)) return;

    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!_isFeedbackCurrent(generation)) return;

    if (once) {
      if (_invalidFeedbackSpoken) return;
      _invalidFeedbackSpoken = true;
    }

    if (SystemAccessibilityService.instance.isScreenReaderActive) {
      await AccessibilityAnnouncement.announce(message);
      return;
    }

    await AppSettingsService.instance.speak(message);
  }

  bool _isFeedbackCurrent(int generation) => generation == _feedbackGeneration;

  Future<void> _waitForNextFrame() {
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  void resetSample() {
    _finalizeTimer?.cancel();
    _recordingLimitTimer?.cancel();
    _cancelFeedback();
    unawaited(_discardAudioCapture());
    _captureProcessed = false;
    _hasValidSample = false;
    _capturedPhrase = '';
    _bestPhrase = '';
    _voiceprintVector = const [];
    _voiceFeatures = const {};
    _accessibilityMessage = null;
    _invalidFeedbackSpoken = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _finalizeTimer?.cancel();
    _recordingLimitTimer?.cancel();
    _cancelFeedback();
    _speech.stop();
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }
}
