import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/emergency_alert_entity.dart';
import 'app_experience_service.dart';
import 'app_settings_service.dart';
import 'device_permissions_service.dart';
import 'emergency_alert_service.dart';
import 'emergency_ai_service.dart';
import 'patient_call_session.dart';
import 'voice_call_service.dart';

enum FallResponsePhase { idle, responding, sending }

/// Monitors device motion for sudden falls and runs the voice check-in flow.
class FallDetectionCoordinator extends ChangeNotifier {
  FallDetectionCoordinator._();

  static final FallDetectionCoordinator instance = FallDetectionCoordinator._();

  static const _freeFallThreshold = 3.0;
  static const _impactThreshold = 13.5;
  static const _freeFallMinMs = 100;
  static const _impactWindowMs = 2200;
  static const _cooldownMs = 30000;
  static const _responseTimeoutSeconds = 15;

  /// Sudden spike after a calm period (catches drops without a clear free-fall).
  static const _spikeImpactThreshold = 15.0;
  static const _calmEmaThreshold = 6.5;
  static const _calmMinMs = 80;

  final _speech = SpeechToText();
  final _alertService = EmergencyAlertService();
  final _emergencyAI = EmergencyAIService();

  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<User?>? _authSub;

  FallResponsePhase _phase = FallResponsePhase.idle;
  bool _started = false;
  bool _speechReady = false;
  bool _appResumed = true;
  bool _isDemoSession = false;
  bool _isListeningForVoice = false;
  String _heardVoicePreview = '';
  EmergencyAnalysisResult? _lastVoiceAnalysis;
  int _responseGeneration = 0;
  DateTime? _lastFallAt;
  DateTime? _freeFallStartedAt;
  bool _freeFallQualified = false;
  double _emaMagnitude = 9.8;
  double _lastMagnitude = 0;
  DateTime? _calmSince;

  FallResponsePhase get phase => _phase;
  bool get isResponding => _phase == FallResponsePhase.responding;
  bool get isDemoSession => _isDemoSession;
  bool get isListeningForVoice => _isListeningForVoice;
  String get heardVoicePreview => _heardVoicePreview;
  EmergencyAnalysisResult? get lastVoiceAnalysis => _lastVoiceAnalysis;

  void ensureStarted() {
    if (_started) {
      _syncMonitoring();
      return;
    }
    _started = true;
    _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
      _syncMonitoring();
    });
    AppSettingsService.instance.addListener(_onSettingsChanged);
    _syncMonitoring();
  }

  void stop() {
    _accelSub?.cancel();
    _accelSub = null;
    _authSub?.cancel();
    _authSub = null;
    AppSettingsService.instance.removeListener(_onSettingsChanged);
    unawaited(_cancelResponse());
    _started = false;
  }

  void setAppResumed(bool resumed) {
    if (_appResumed == resumed) return;
    _appResumed = resumed;
    _syncMonitoring();
  }

  void _onSettingsChanged() {
    if (!AppSettingsService.instance.settings.fallDetectionEnabled) {
      unawaited(_cancelResponse());
    }
    _syncMonitoring();
  }

  void _syncMonitoring() {
    if (!_started) return;
    final shouldMonitor = _canMonitor;
    if (shouldMonitor && _accelSub == null) {
      _accelSub = userAccelerometerEventStream().listen(
        _onAccelerometer,
        onError: (Object error) {
          debugPrint('FallDetectionCoordinator accelerometer error: $error');
        },
      );
    } else if (!shouldMonitor) {
      _accelSub?.cancel();
      _accelSub = null;
      _resetFallTracking();
    }
  }

  bool get _canMonitor {
    if (!_appResumed) return false;
    if (!AppExperienceService.instance.isPatientExperience) return false;
    if (FirebaseAuth.instance.currentUser == null) return false;
    if (!AppSettingsService.instance.settings.fallDetectionEnabled) return false;
    if (_phase != FallResponsePhase.idle) return false;
    if (_isInCooldown) return false;
    if (_isCallActive) return false;
    return true;
  }

  bool get _isInCooldown {
    final last = _lastFallAt;
    if (last == null) return false;
    return DateTime.now().difference(last) < const Duration(milliseconds: _cooldownMs);
  }

  bool get _isCallActive {
    final phase = PatientCallSession.instance.voiceCall.phase;
    return phase != VoiceCallPhase.idle;
  }

  void _onAccelerometer(UserAccelerometerEvent event) {
    if (!_canMonitor) return;

    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    final now = DateTime.now();

    _emaMagnitude = 0.25 * magnitude + 0.75 * _emaMagnitude;
    if (_emaMagnitude < _calmEmaThreshold) {
      _calmSince ??= now;
    } else {
      _calmSince = null;
    }

    final calmLongEnough = _calmSince != null &&
        now.difference(_calmSince!).inMilliseconds >= _calmMinMs;
    final suddenSpike = magnitude >= _spikeImpactThreshold &&
        _lastMagnitude < _spikeImpactThreshold * 0.55 &&
        calmLongEnough;

    if (suddenSpike) {
      _lastMagnitude = magnitude;
      _resetFallTracking();
      if (kDebugMode) {
        debugPrint(
          'FallDetection: sudden impact spike '
          '(mag=${magnitude.toStringAsFixed(1)}, ema=${_emaMagnitude.toStringAsFixed(1)})',
        );
      }
      unawaited(_onFallDetected());
      return;
    }

    _lastMagnitude = magnitude;

    if (magnitude < _freeFallThreshold) {
      _freeFallStartedAt ??= now;
      final elapsed = now.difference(_freeFallStartedAt!).inMilliseconds;
      if (elapsed >= _freeFallMinMs) {
        _freeFallQualified = true;
      }
      return;
    }

    if (_freeFallQualified && magnitude >= _impactThreshold) {
      final started = _freeFallStartedAt;
      if (started != null &&
          now.difference(started).inMilliseconds <= _impactWindowMs) {
        _resetFallTracking();
        if (kDebugMode) {
          debugPrint(
            'FallDetection: free-fall + impact '
            '(mag=${magnitude.toStringAsFixed(1)})',
          );
        }
        unawaited(_onFallDetected());
        return;
      }
    }

    if (magnitude >= _impactThreshold && _freeFallQualified) {
      _resetFallTracking();
      if (kDebugMode) {
        debugPrint(
          'FallDetection: impact after free-fall '
          '(mag=${magnitude.toStringAsFixed(1)})',
        );
      }
      unawaited(_onFallDetected());
      return;
    }

    if (magnitude >= _freeFallThreshold + 2) {
      _resetFallTracking();
    }
  }

  void _resetFallTracking() {
    _freeFallStartedAt = null;
    _freeFallQualified = false;
    _calmSince = null;
  }

  /// Runs the spoken check-in flow without waiting for sensor motion (for demos).
  Future<void> triggerDemoCheckIn() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    if (_phase != FallResponsePhase.idle) return;
    if (_isCallActive) return;

    _accelSub?.cancel();
    _accelSub = null;

    _isDemoSession = true;
    _heardVoicePreview = '';
    _lastVoiceAnalysis = null;
    _isListeningForVoice = false;
    _phase = FallResponsePhase.responding;
    notifyListeners();

    final generation = ++_responseGeneration;
    await _runResponseFlow(generation);
  }

  Future<void> _onFallDetected() async {
    if (!_canMonitor) return;

    _lastFallAt = DateTime.now();
    _accelSub?.cancel();
    _accelSub = null;

    try {
      final active = await _alertService.fetchActiveForCurrentPatient();
      if (active != null) return;
    } catch (_) {
      // Continue — better to offer check-in than skip on read failure.
    }

    if (_isCallActive) return;

    _isDemoSession = false;
    _heardVoicePreview = '';
    _lastVoiceAnalysis = null;
    _phase = FallResponsePhase.responding;
    notifyListeners();

    final generation = ++_responseGeneration;
    await _runResponseFlow(generation);
  }

  Future<void> dismissResponse() async {
    if (_isDemoSession) {
      await _finishDemoNoAlert(_responseGeneration);
    } else {
      await _finishResponse(dismissed: true, speakDismissed: true);
    }
  }

  Future<void> requestHelp() async {
    final generation = _responseGeneration;
    await _sendFallAlert(generation, announce: true);
  }

  Future<void> _runResponseFlow(int generation) async {
    await AppSettingsService.instance.stopSpeaking();
    await _emergencyAI.initialize();
    final promptKey = _isDemoSession
        ? 'fallDetectionDemoVoicePrompt'
        : 'fallDetectionVoicePrompt';
    await AppSettingsService.instance.speakAndAwaitCompletion(
      AppSettingsService.instance.localized(promptKey),
    );
    if (!_isResponseCurrent(generation)) return;

    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
    if (!micGranted) {
      if (_isDemoSession) {
        await _finishDemoNoAlert(generation);
      } else {
        await _sendFallAlert(generation, announce: true);
      }
      return;
    }

    if (!_speechReady) {
      final available = await _speech.initialize(
        onError: (error) {
          debugPrint('FallDetectionCoordinator STT error: $error');
        },
      );
      _speechReady = available;
      if (!available) {
        if (_isDemoSession) {
          await _finishDemoNoAlert(generation);
        } else {
          await _sendFallAlert(generation, announce: true);
        }
        return;
      }
    }

    _heardVoicePreview = '';
    _lastVoiceAnalysis = null;
    _isListeningForVoice = true;
    notifyListeners();

    final completer = Completer<_VoiceIntent>();
    try {
      await _speech.listen(
        listenFor: const Duration(seconds: _responseTimeoutSeconds),
        pauseFor: const Duration(seconds: 4),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
        onResult: (result) {
          unawaited(
            _handleSpeechResult(
              generation: generation,
              completer: completer,
              words: result.recognizedWords.trim(),
            ),
          );
        },
      );

      // Wait until speech recognition ends, or the emergency intent is captured
      while (_speech.isListening && _isResponseCurrent(generation) && !completer.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      
      if (!completer.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      
    } catch (e) {
      debugPrint('FallDetectionCoordinator listen failed: $e');
      _isListeningForVoice = false;
      notifyListeners();
      if (_isDemoSession) {
        await _finishDemoNoAlert(generation);
      } else {
        await _sendFallAlert(generation, announce: true);
      }
      return;
    }

    _VoiceIntent intent;
    if (completer.isCompleted) {
      intent = await completer.future;
    } else {
      if (_heardVoicePreview.isEmpty) {
        intent = _VoiceIntent.timeout;
      } else {
        intent = _VoiceIntent.fine;
      }
    }

    try {
      await _speech.stop();
    } catch (_) {}

    _isListeningForVoice = false;
    notifyListeners();

    if (!_isResponseCurrent(generation)) return;

    if (_isDemoSession) {
      switch (intent) {
        case _VoiceIntent.fine:
          await _finishDemoNoAlert(generation);
        case _VoiceIntent.help:
          await _sendFallAlert(generation, announce: true);
        case _VoiceIntent.timeout:
        case _VoiceIntent.unknown:
          await _finishDemoNoAlert(generation);
      }
      return;
    }

    switch (intent) {
      case _VoiceIntent.fine:
        await _finishResponse(dismissed: true, speakDismissed: true);
      case _VoiceIntent.help:
        await _sendFallAlert(generation, announce: true);
      case _VoiceIntent.timeout:
        await _sendFallAlert(generation, announce: true);
      case _VoiceIntent.unknown:
        await _sendFallAlert(generation, announce: true);
    }
  }

  Future<void> _handleSpeechResult({
    required int generation,
    required Completer<_VoiceIntent> completer,
    required String words,
  }) async {
    if (!_isResponseCurrent(generation) || completer.isCompleted) {
      if (!_isResponseCurrent(generation) && _speech.isListening) {
        unawaited(_speech.stop());
      }
      return;
    }
    if (words.isEmpty) return;

    if (words != _heardVoicePreview) {
      _heardVoicePreview = words;
      notifyListeners();
    }

    final analysis = await _emergencyAI.analyze(words);
    if (!_isResponseCurrent(generation) || completer.isCompleted) return;

    _lastVoiceAnalysis = analysis;
    notifyListeners();

    debugPrint(
      'Fall detection voice -> ${analysis.label} '
      '(${analysis.score.toStringAsFixed(3)}, ${analysis.source})',
    );

    if (analysis.isEmergency) {
      completer.complete(_VoiceIntent.help);
    }
  }

  bool _isResponseCurrent(int generation) {
    return generation == _responseGeneration &&
        _phase == FallResponsePhase.responding;
  }

  Future<void> _sendFallAlert(
    int generation, {
    required bool announce,
    String? voiceTranscript,
  }) async {
    if (_phase != FallResponsePhase.responding) return;

    _phase = FallResponsePhase.sending;
    notifyListeners();

    try {
      await _speech.stop();
    } catch (_) {}
    await AppSettingsService.instance.stopSpeaking();

    try {
      await _alertService.triggerSos(
        alertType: _isDemoSession
            ? EmergencyAlertEntity.alertTypeFallDetectionTest
            : EmergencyAlertEntity.alertTypeFallDetection,
        voiceTranscript: voiceTranscript ?? _heardVoicePreview,
      );
      if (announce) {
        final messageKey = _isDemoSession
            ? 'fallDetectionDemoAlertSent'
            : 'sosActiveMessage';
        await AppSettingsService.instance.speakAndAwaitCompletion(
          AppSettingsService.instance.localized(messageKey),
        );
      }
    } catch (e) {
      debugPrint('FallDetectionCoordinator alert failed: $e');
      await AppSettingsService.instance.speakAndAwaitCompletion(
        AppSettingsService.instance.localized('fallDetectionAlertFailed'),
      );
    } finally {
      await _finishResponse(dismissed: false);
    }
  }

  Future<void> _finishDemoNoAlert(int generation) async {
    if (!_isResponseCurrent(generation)) return;
    await _finishResponse(
      dismissed: true,
      speakMessageKey: 'fallDetectionDemoNoAlertSent',
    );
  }

  Future<void> _finishResponse({
    required bool dismissed,
    bool speakDismissed = false,
    String? speakMessageKey,
  }) async {
    _responseGeneration++;
    try {
      await _speech.stop();
    } catch (_) {}
    await AppSettingsService.instance.stopSpeaking();

    if (speakMessageKey != null) {
      await AppSettingsService.instance.speakAndAwaitCompletion(
        AppSettingsService.instance.localized(speakMessageKey),
      );
    } else if (speakDismissed) {
      await AppSettingsService.instance.speakAndAwaitCompletion(
        AppSettingsService.instance.localized('fallDetectionCheckCancelled'),
      );
    }

    _phase = FallResponsePhase.idle;
    _isDemoSession = false;
    _isListeningForVoice = false;
    _heardVoicePreview = '';
    _lastVoiceAnalysis = null;
    _resetFallTracking();
    notifyListeners();
    _syncMonitoring();
  }

  Future<void> _cancelResponse() async {
    if (_phase == FallResponsePhase.idle) return;
    await _finishResponse(dismissed: true);
  }
}

enum _VoiceIntent { fine, help, timeout, unknown }
