import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/voice_capture_result.dart';
import 'app_settings_service.dart';
import 'device_permissions_service.dart';
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

    await _speech.listen(
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 4),
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

    return null;
  }

  Future<String?> _resolvePassphraseLocale() async {
    const preferred = ['en_US', 'en_GB', 'en_AU', 'en_SG', 'en'];
    try {
      final locales = await _speech.locales();
      for (final id in preferred) {
        if (locales.any((locale) => locale.localeId == id)) {
          return id;
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
    _captureProcessed = true;
    _finalizeTimer?.cancel();

    await _finishRecording();

    _capturedPhrase = VoicePassphrase.normalize(phrase);
    _hasValidSample = true;
    notifyListeners();
    unawaited(_captureVoiceprintAfterPhrase());
    await _announceFeedback(VoicePassphrase.captureSuccessMessage);

    final result = captureResult;
    if (result != null) {
      await onValidCapture?.call(result);
    }
  }

  Future<void> _finalizeCapture({
    String? preferredPhrase,
    bool requireHeardSpeech = false,
  }) async {
    if (_captureProcessed) return;

    final phrase = _pickPhrase(preferredPhrase);
    if (phrase.isEmpty) {
      if (requireHeardSpeech) {
        await _finishRecording();
        await _rejectCapture();
      }
      return;
    }

    if (VoicePassphrase.isSignMeIn(phrase)) {
      await _acceptCapture(phrase);
      return;
    }

    await _finishRecording();
    await _rejectCapture(
      debugHeard: phrase,
    );
  }

  Future<void> _captureVoiceprintAfterPhrase() async {
    try {
      await _audioRecorder.start();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      final wavBytes = await _audioRecorder.stop();
      _applyAudioEmbedding(wavBytes);
    } catch (e) {
      debugPrint('VoicePassphraseController voiceprint capture failed: $e');
    }
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
    if (!_isRecording) return;
    try {
      await _speech.stop();
    } catch (_) {}
    _isRecording = false;
    notifyListeners();
  }

  void _applyAudioEmbedding(Uint8List? wavBytes) {
    if (wavBytes == null || wavBytes.isEmpty) return;

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

  Future<void> _rejectCapture({String debugHeard = ''}) async {
    if (_invalidFeedbackSpoken) return;

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
      VoicePassphrase.retakeMessage,
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
    _cancelFeedback();
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
    _cancelFeedback();
    _speech.stop();
    unawaited(_audioRecorder.dispose());
    super.dispose();
  }
}
