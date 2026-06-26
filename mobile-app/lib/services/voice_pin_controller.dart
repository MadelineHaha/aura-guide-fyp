import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/voice_pin_capture_result.dart';
import '../utils/accessibility_announcement.dart';
import 'app_settings_service.dart';
import 'device_permissions_service.dart';
import 'spoken_pin_parser.dart';
import 'system_accessibility_service.dart';
import 'voice_audio_recorder_service.dart';
import 'voice_embedding_service.dart';
import 'voice_profile_service.dart';

/// Records speech, extracts a 4-digit PIN, and captures a voiceprint from the same audio.
class VoicePinController extends ChangeNotifier {
  VoicePinController({
    SpeechToText? speech,
    VoiceAudioRecorderService? audioRecorder,
    this.onValidCapture,
  })  : _speech = speech ?? SpeechToText(),
        _audioRecorder = audioRecorder ?? VoiceAudioRecorderService();

  final SpeechToText _speech;
  final VoiceAudioRecorderService _audioRecorder;
  final Future<void> Function(VoicePinCaptureResult result)? onValidCapture;

  final _embeddings = VoiceEmbeddingService.instance;
  final _profiles = VoiceProfileService();

  bool _initialized = false;
  bool _isRecording = false;
  bool _isAnalyzing = false;
  bool _hasValidSample = false;
  bool _captureProcessed = false;
  bool _invalidFeedbackSpoken = false;
  bool _audioCaptureStarted = false;
  int _feedbackGeneration = 0;
  String _capturedPin = '';
  String _heardPreview = '';
  String _longestTranscript = '';
  final List<String> _sessionDigitTokens = [];
  String? _accessibilityMessage;
  String? _localeId;
  List<double> _voiceprintVector = const [];
  Map<String, dynamic> _voiceFeatures = const {};
  Timer? _recordingLimitTimer;

  static const _recordingLimit = Duration(seconds: 8);

  bool get isRecording => _isRecording;
  bool get isAnalyzing => _isAnalyzing;
  bool get hasValidSample => _hasValidSample;
  String get capturedPin => _capturedPin;
  String get heardPreview => _heardPreview;
  String? get accessibilityMessage => _accessibilityMessage;

  VoicePinCaptureResult? get captureResult {
    if (_capturedPin.length != 4) return null;
    return VoicePinCaptureResult(
      pin: _capturedPin,
      voiceprintVector: _voiceprintVector,
      voiceFeatures: _voiceFeatures,
    );
  }

  Future<String?> startRecording({bool allowOverwrite = false}) async {
    if (_isRecording || _isAnalyzing) return null;
    if (_hasValidSample && !allowOverwrite) return null;

    _recordingLimitTimer?.cancel();
    _cancelFeedback();
    _accessibilityMessage = null;
    _invalidFeedbackSpoken = false;
    _audioCaptureStarted = false;
    _voiceprintVector = const [];
    _voiceFeatures = const {};
    _capturedPin = '';
    _heardPreview = '';
    _longestTranscript = '';
    _sessionDigitTokens.clear();
    _isAnalyzing = false;
    notifyListeners();

    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
    if (!micGranted) {
      return 'Microphone permission is required. Please allow microphone access in your device settings.';
    }

    if (!_initialized) {
      final available = await _speech.initialize(
        onError: (error) {
          debugPrint('VoicePinController STT error: $error');
        },
      );
      if (!available) {
        return 'Microphone permission is required.';
      }
      _initialized = true;
    }

    _localeId ??= await _resolveLocale();

    _isRecording = true;
    _hasValidSample = false;
    _captureProcessed = false;
    notifyListeners();

    try {
      await _speech.cancel();
    } catch (_) {}

    await _discardAudioCapture();

    // On Android, starting the WAV recorder before STT often blocks speech recognition.
    if (!Platform.isAndroid) {
      await _startAudioCaptureIfNeeded();
    }

    await _speech.listen(
      listenFor: _recordingLimit,
      pauseFor: _recordingLimit,
      localeId: _localeId,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.dictation,
      ),
      onResult: (result) {
        if (_captureProcessed || !_isRecording) return;
        unawaited(_handleSpeechResult(result.recognizedWords));
      },
    );

    _startRecordingLimitTimer();
    return null;
  }

  Future<void> _handleSpeechResult(String raw) async {
    if (raw.trim().isEmpty) return;

    if (raw.length > _longestTranscript.length) {
      _longestTranscript = raw;
    }

    final normalized = _profiles.normalize(raw);
    final transcript = normalized.isNotEmpty ? normalized : raw;
    _heardPreview = transcript;
    notifyListeners();

    await _startAudioCaptureIfNeeded();

    final beforeCount = _sessionDigitTokens.length;
    final merged = SpokenPinParser.mergeDigitTokens(_sessionDigitTokens, raw);
    _sessionDigitTokens
      ..clear()
      ..addAll(merged);

    if (_sessionDigitTokens.length > beforeCount) {
      _heardPreview = _sessionDigitTokens.join(' ');
      notifyListeners();
    }

    if (!SpokenPinParser.hasCompleteTokenList(_sessionDigitTokens)) {
      return;
    }

    final pin = SpokenPinParser.pinFromTokens(_sessionDigitTokens);
    if (pin != null) {
      await _onFourDigitPinDetected(pin);
    }
  }

  Future<void> _startAudioCaptureIfNeeded() async {
    if (_audioCaptureStarted) return;
    _audioCaptureStarted = true;
    try {
      await _audioRecorder.start();
    } catch (error) {
      debugPrint('VoicePinController audio start failed: $error');
      _audioCaptureStarted = false;
    }
  }

  Future<void> stopRecording() async {
    if (!_isRecording || _captureProcessed) return;
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

  Future<String?> _resolveLocale() async {
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
      debugPrint('VoicePinController locale lookup failed: $e');
    }
    return 'en_US';
  }

  Future<void> _onFourDigitPinDetected(String pin) async {
    if (_captureProcessed) return;
    _captureProcessed = true;
    _recordingLimitTimer?.cancel();

    _capturedPin = pin;
    _heardPreview = pin;
    _isRecording = false;
    _isAnalyzing = true;
    notifyListeners();

    try {
      await _speech.stop();
    } catch (_) {}

    await _startAudioCaptureIfNeeded();

    if (Platform.isAndroid) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    await _finalizeVoiceprintFromAudio();

    if (!VoiceEmbeddingService.isUsableVoiceprint(_voiceprintVector)) {
      debugPrint(
        'VoicePinController: no usable voiceprint; continuing with PIN only.',
      );
    }

    await _announceFeedback(
      AppSettingsService.instance.localized('patientOnboardingPinVerifying'),
    );

    final result = captureResult;
    if (result == null) {
      _isAnalyzing = false;
      _captureProcessed = false;
      await _rejectCapture(debugHeard: pin);
      return;
    }

    try {
      await onValidCapture?.call(result);
      _hasValidSample = true;
    } catch (error) {
      _captureProcessed = false;
      _capturedPin = '';
      _hasValidSample = false;
      rethrow;
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  Future<void> _finalizeCapture({
    bool requireHeardSpeech = false,
  }) async {
    if (_captureProcessed) return;

    await _startAudioCaptureIfNeeded();

    String? pin = SpokenPinParser.pinFromTokens(_sessionDigitTokens);
    pin ??= SpokenPinParser.parseFourDigitPin(_longestTranscript);
    pin ??= SpokenPinParser.parseFourDigitPin(_heardPreview);

    if (pin != null) {
      await _onFourDigitPinDetected(pin);
      return;
    }

    if (!requireHeardSpeech) return;

    _captureProcessed = true;
    _recordingLimitTimer?.cancel();
    await _finishRecording();
    await _discardAudioCapture();

    final noSpeech = _longestTranscript.trim().isEmpty &&
        _sessionDigitTokens.isEmpty &&
        _heardPreview.trim().isEmpty;
    await _rejectCapture(
      debugHeard: _heardPreview,
      message: noSpeech
          ? AppSettingsService.instance
              .localized('patientOnboardingPinNoSpeech')
          : null,
    );
  }

  Future<void> _finalizeVoiceprintFromAudio() async {
    try {
      final wavBytes = await _audioRecorder.stop();
      _audioCaptureStarted = false;
      _applyAudioEmbedding(wavBytes);
    } catch (error) {
      debugPrint('VoicePinController voiceprint finalize failed: $error');
      _audioCaptureStarted = false;
    }
  }

  Future<void> _discardAudioCapture() async {
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    _audioCaptureStarted = false;
  }

  void _cancelFeedback() {
    _feedbackGeneration++;
    unawaited(AppSettingsService.instance.stopSpeaking());
  }

  Future<void> _finishRecording() async {
    if (!_isRecording) return;
    try {
      await _speech.stop();
    } catch (_) {}
    _isRecording = false;
    notifyListeners();
  }

  void _applyAudioEmbedding(Uint8List? wavBytes) {
    if (wavBytes == null || wavBytes.isEmpty) {
      debugPrint('VoicePinController: no audio bytes captured');
      return;
    }
    debugPrint('VoicePinController: wavBytes length = ${wavBytes.length}');

    final vector = _embeddings.extractFromWav(wavBytes);
    final decodedDurationMs = _estimateDurationMs(wavBytes);
    _voiceprintVector = vector;
    _voiceFeatures = _embeddings.buildFeatures(
      vector: vector,
      sampleRate: 16000,
      durationMs: decodedDurationMs,
    );
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

    _isAnalyzing = false;
    _isRecording = false;
    _captureProcessed = false;
    _heardPreview = debugHeard;
    _capturedPin = '';
    _hasValidSample = false;
    _voiceprintVector = const [];
    _voiceFeatures = const {};
    _sessionDigitTokens.clear();
    _longestTranscript = '';
    notifyListeners();

    if (kDebugMode && debugHeard.isNotEmpty) {
      debugPrint('VoicePinController rejected heard: "$debugHeard"');
    }

    await _announceFeedback(
      message ??
          AppSettingsService.instance.localized('patientOnboardingPinVoiceRetake'),
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
    _recordingLimitTimer?.cancel();
    _cancelFeedback();
    unawaited(_discardAudioCapture());
    _captureProcessed = false;
    _hasValidSample = false;
    _isAnalyzing = false;
    _isRecording = false;
    _audioCaptureStarted = false;
    _capturedPin = '';
    _heardPreview = '';
    _longestTranscript = '';
    _sessionDigitTokens.clear();
    _voiceprintVector = const [];
    _voiceFeatures = const {};
    _accessibilityMessage = null;
    _invalidFeedbackSpoken = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _recordingLimitTimer?.cancel();
    _cancelFeedback();
    _speech.stop();
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }
}
