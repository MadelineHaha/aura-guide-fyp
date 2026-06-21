import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../auth_session.dart';
import '../appointments_page.dart';
import '../book_appointment_page.dart';
import '../communication_page.dart';
import '../app_navigator.dart';
import '../medications_page.dart';
import '../navigation_page.dart';
import '../settings_page.dart';
import 'app_settings_service.dart';
import 'device_permissions_service.dart';
import 'fall_detection_coordinator.dart';
import 'patient_call_session.dart';
import 'silent_mic_monitor_service.dart';
import 'voice_call_service.dart';

enum VoiceAssistantPhase {
  idle,
  greeting,
  awaitingCommand,
  processing,
}

/// Foreground wake-word assistant: listens for "Hey AuraGuide", greets back,
/// then captures a short voice command.
class VoiceAssistantCoordinator extends ChangeNotifier {
  VoiceAssistantCoordinator._();

  static final VoiceAssistantCoordinator instance = VoiceAssistantCoordinator._();

  static const _voiceSttSeconds = 25;
  static const _commandListenSeconds = 12;
  static const _sttHandoffDelayMs = 200;
  static const _resumeSilentDelayMs = 400;

  final _speech = SpeechToText();
  final _silentMonitor = SilentMicMonitorService();
  final navigatorObserver = _VoiceAssistantNavigatorObserver();

  VoiceAssistantPhase _phase = VoiceAssistantPhase.idle;
  bool _started = false;
  bool _speechReady = false;
  bool _appResumed = true;
  int _micLockCount = 0;
  int _sessionGeneration = 0;
  String? _topRouteLabel;
  String? _lastUserCommand;
  String _assistantMessage = '';
  String? _speechLocaleId;
  bool _voiceSttActive = false;
  bool _wakeHandledInSession = false;
  Completer<void>? _listenSessionCompleter;
  String _lastCommandPartial = '';
  bool _finalizingCommand = false;

  VoiceAssistantPhase get phase => _phase;
  bool get isAwaitingCommand => _phase == VoiceAssistantPhase.awaitingCommand;
  String? get lastUserCommand => _lastUserCommand;
  String get assistantMessage => _assistantMessage;
  bool get isActive => _phase != VoiceAssistantPhase.idle;

  void ensureStarted() {
    if (_started) {
      _ensureListening();
      return;
    }
    _started = true;
    FirebaseAuth.instance.authStateChanges().listen((_) => _ensureListening());
    AppSettingsService.instance.addListener(_onSettingsChanged);
    FallDetectionCoordinator.instance.addListener(_onFallDetectionChanged);
    PatientCallSession.instance.ensureStarted();
    PatientCallSession.instance.voiceCall.stateStream.listen((_) {
      _ensureListening();
    });
    _ensureListening();
  }

  void _onFallDetectionChanged() {
    if (FallDetectionCoordinator.instance.isResponding) {
      unawaited(_stopListening());
    } else {
      _ensureListening();
    }
  }

  void setAppResumed(bool resumed) {
    if (_appResumed == resumed) return;
    _appResumed = resumed;
    if (!resumed) {
      unawaited(_stopListening());
    } else {
      _ensureListening();
    }
  }

  void setTopRouteLabel(String? label) {
    if (_topRouteLabel == label) return;
    _topRouteLabel = label;
    if (!_canRun) {
      unawaited(_stopListening());
      return;
    }
    _ensureListening();
  }

  void acquireMicLock() {
    _micLockCount++;
    if (_micLockCount == 1) {
      unawaited(_stopListening());
    }
  }

  void releaseMicLock() {
    if (_micLockCount <= 0) return;
    _micLockCount--;
    _ensureListening();
  }

  void _onSettingsChanged() {
    if (!AppSettingsService.instance.settings.voiceAssistantEnabled) {
      unawaited(_stopListening());
    } else {
      _ensureListening();
    }
  }

  bool get _canRun {
    if (!_started || !_appResumed) return false;
    if (FirebaseAuth.instance.currentUser == null &&
        AuthSession.resolveUser() == null) {
      return false;
    }
    if (!AppSettingsService.instance.settings.voiceAssistantEnabled) return false;
    if (_micLockCount > 0) return false;
    if (_routeBlocksAssistant(_topRouteLabel)) return false;
    if (FallDetectionCoordinator.instance.isResponding) return false;
    if (_isCallActive) return false;
    return true;
  }

  void _ensureListening() {
    if (!_canRun) return;
    if (_voiceSttActive || _speech.isListening) return;

    if (_phase == VoiceAssistantPhase.awaitingCommand) {
      unawaited(_listenForCommand(_sessionGeneration));
      return;
    }

    if (_phase != VoiceAssistantPhase.idle) return;
    if (_silentMonitor.isRunning) return;

    unawaited(_startSilentMonitoring());
  }

  bool _routeBlocksAssistant(String? routeLabel) {
    if (routeLabel == null || routeLabel.isEmpty) return false;
    const blocked = <String>[
      'EmergencySosPage',
      'VoiceLoginPage',
      'VoiceRegisterPage',
      'VoiceProfileSetupPage',
      'NavigationArPage',
    ];
    return blocked.any(routeLabel.contains);
  }

  bool get _isCallActive {
    final phase = PatientCallSession.instance.voiceCall.phase;
    return phase != VoiceCallPhase.idle;
  }

  Future<void> _startSilentMonitoring() async {
    if (!_canRun || _phase != VoiceAssistantPhase.idle) return;
    if (_voiceSttActive ||
        _speech.isListening ||
        _silentMonitor.isRunning) {
      return;
    }

    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
    if (!micGranted || !_canRun || _phase != VoiceAssistantPhase.idle) return;

    try {
      await _silentMonitor.start(() {
        if (!_canRun ||
            _phase != VoiceAssistantPhase.idle ||
            _voiceSttActive) {
          return;
        }
        unawaited(_startWakeWordSttSession());
      });
    } catch (error) {
      debugPrint('VoiceAssistantCoordinator silent monitor failed: $error');
      await Future<void>.delayed(
        const Duration(milliseconds: _resumeSilentDelayMs),
      );
      _ensureListening();
    }
  }

  /// Speech-to-text only while the user is speaking — avoids idle beeping.
  Future<void> _startWakeWordSttSession() async {
    if (!_canRun || _phase != VoiceAssistantPhase.idle || _voiceSttActive) {
      return;
    }

    _voiceSttActive = true;
    _wakeHandledInSession = false;
    final generation = ++_sessionGeneration;
    _listenSessionCompleter = Completer<void>();

    await _silentMonitor.stop();
    await Future<void>.delayed(
      const Duration(milliseconds: _sttHandoffDelayMs),
    );

    if (!_canRun || _phase != VoiceAssistantPhase.idle) {
      await _endVoiceSttSession(resumeSilent: true);
      return;
    }

    await _ensureSpeechReady();
    if (!_speechReady || !_canRun || _phase != VoiceAssistantPhase.idle) {
      await _endVoiceSttSession(resumeSilent: true);
      return;
    }

    try {
      await _speech.listen(
        listenFor: const Duration(seconds: _voiceSttSeconds),
        pauseFor: const Duration(seconds: 5),
        localeId: await _resolveListenLocale(),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
        onResult: (result) {
          if (!_isGenerationCurrent(generation)) return;
          if (_wakeHandledInSession || _phase != VoiceAssistantPhase.idle) {
            return;
          }

          final heard = result.recognizedWords.trim();
          if (heard.isEmpty) return;

          debugPrint(
            'VoiceAssistantCoordinator heard: "$heard" '
            '(final=${result.finalResult})',
          );

          if (!containsWakePhrase(heard)) return;

          _wakeHandledInSession = true;
          final trailingCommand = stripWakePhrase(heard);
          unawaited(
            _onWakeDetected(
              generation,
              prefilledCommand:
                  trailingCommand.isNotEmpty ? trailingCommand : null,
            ),
          );
        },
      );

      await _listenSessionCompleter!.future.timeout(
        Duration(seconds: _voiceSttSeconds + 3),
        onTimeout: () {},
      );
    } catch (error) {
      debugPrint('VoiceAssistantCoordinator wake STT failed: $error');
    } finally {
      await _endVoiceSttSession(
        resumeSilent: _phase == VoiceAssistantPhase.idle &&
            _canRun &&
            !_wakeHandledInSession,
      );
    }
  }

  Future<void> _endVoiceSttSession({required bool resumeSilent}) async {
    _listenSessionCompleter = null;
    _voiceSttActive = false;

    if (_speech.isListening) {
      try {
        await _speech.stop();
      } catch (_) {}
    }

    if (resumeSilent) {
      await Future<void>.delayed(
        const Duration(milliseconds: _resumeSilentDelayMs),
      );
      _ensureListening();
    }
  }

  Future<void> _ensureSpeechReady() async {
    if (_speechReady) return;

    final available = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: (error) {
        debugPrint('VoiceAssistantCoordinator STT error: $error');
      },
    );
    _speechReady = available;
  }

  void _onSpeechStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      final sessionCompleter = _listenSessionCompleter;
      if (sessionCompleter != null && !sessionCompleter.isCompleted) {
        sessionCompleter.complete();
      }

      if (_phase == VoiceAssistantPhase.awaitingCommand &&
          _lastCommandPartial.trim().isNotEmpty &&
          !_finalizingCommand) {
        unawaited(
          _finalizeCommand(
            _sessionGeneration,
            _lastCommandPartial.trim(),
          ),
        );
      }

      if (_phase == VoiceAssistantPhase.idle &&
          !_voiceSttActive &&
          !_speech.isListening &&
          !_silentMonitor.isRunning &&
          _canRun) {
        _ensureListening();
      }
    }
  }

  Future<void> _listenForCommand(int generation) async {
    if (!_isGenerationCurrent(generation)) return;
    if (_phase != VoiceAssistantPhase.awaitingCommand) return;
    if (_voiceSttActive || _speech.isListening) return;

    _voiceSttActive = true;
    _lastCommandPartial = '';
    _listenSessionCompleter = Completer<void>();

    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
    if (!micGranted || !_isGenerationCurrent(generation)) {
      await _endVoiceSttSession(resumeSilent: false);
      await _resetToIdle();
      _ensureListening();
      return;
    }

    await Future<void>.delayed(
      const Duration(milliseconds: _sttHandoffDelayMs),
    );
    if (!_isGenerationCurrent(generation)) {
      await _endVoiceSttSession(resumeSilent: false);
      await _resetToIdle();
      _ensureListening();
      return;
    }

    try {
      await _speech.listen(
        listenFor: const Duration(seconds: _commandListenSeconds),
        pauseFor: const Duration(seconds: 4),
        localeId: await _resolveListenLocale(),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.confirmation,
        ),
        onResult: (result) {
          if (!_isGenerationCurrent(generation)) return;
          if (_phase != VoiceAssistantPhase.awaitingCommand) return;

          final text = stripWakePhrase(result.recognizedWords);
          if (text.isNotEmpty) {
            _lastCommandPartial = text;
            _lastUserCommand = text;
            notifyListeners();
          }

          if (!result.finalResult || _finalizingCommand) return;

          unawaited(
            _finalizeCommand(
              generation,
              text.trim().isEmpty ? null : text.trim(),
            ),
          );
        },
      );

      await _listenSessionCompleter!.future.timeout(
        Duration(seconds: _commandListenSeconds + 2),
        onTimeout: () {},
      );
    } catch (error) {
      debugPrint('VoiceAssistantCoordinator command listen failed: $error');
    }

    if (!_finalizingCommand &&
        _isGenerationCurrent(generation) &&
        _phase == VoiceAssistantPhase.awaitingCommand) {
      await _finalizeCommand(
        generation,
        _lastCommandPartial.trim().isEmpty ? null : _lastCommandPartial.trim(),
      );
    } else {
      await _endVoiceSttSession(resumeSilent: false);
    }
  }

  Future<void> _finalizeCommand(int generation, String? command) async {
    if (_finalizingCommand) return;
    if (!_isGenerationCurrent(generation)) return;
    if (_phase != VoiceAssistantPhase.awaitingCommand) return;

    _finalizingCommand = true;
    try {
      final resolved = command ?? _lastCommandPartial.trim();
      _lastCommandPartial = '';

      await _endVoiceSttSession(resumeSilent: false);
      if (!_isGenerationCurrent(generation)) return;

      await _handleCommand(
        resolved.isEmpty ? null : resolved,
        generation,
      );
      await _resetToIdle();
      _ensureListening();
    } finally {
      _finalizingCommand = false;
    }
  }

  Future<void> _onWakeDetected(
    int generation, {
    String? prefilledCommand,
  }) async {
    if (!_isGenerationCurrent(generation)) return;

    _lastUserCommand = null;
    _phase = VoiceAssistantPhase.greeting;
    _setAssistantMessageKey('voiceAssistantGreeting');
    notifyListeners();

    await _speech.stop();
    await Future<void>.delayed(
      const Duration(milliseconds: _sttHandoffDelayMs),
    );
    await AppSettingsService.instance.stopSpeaking();
    await _speak('voiceAssistantGreeting');

    if (!_isGenerationCurrent(generation)) {
      await _resetToIdle();
      return;
    }

    final command = prefilledCommand?.trim();
    if (command != null && command.isNotEmpty) {
      await _handleCommand(command, generation);
      await _resetToIdle();
      _ensureListening();
      return;
    }

    _phase = VoiceAssistantPhase.awaitingCommand;
    _lastCommandPartial = '';
    _setAssistantMessageKey('voiceAssistantListening');
    notifyListeners();

    await _listenForCommand(generation);
  }

  Future<String?> _resolveListenLocale() async {
    if (_speechLocaleId != null) return _speechLocaleId;
    const preferred = ['en_US', 'en_GB', 'en_AU', 'en_SG', 'en'];
    try {
      final locales = await _speech.locales();
      for (final id in preferred) {
        if (locales.any((locale) => locale.localeId == id)) {
          _speechLocaleId = id;
          return id;
        }
      }
      if (locales.isNotEmpty) {
        _speechLocaleId = locales.first.localeId;
        return _speechLocaleId;
      }
    } catch (error) {
      debugPrint('VoiceAssistantCoordinator locale lookup failed: $error');
    }
    _speechLocaleId = 'en_US';
    return _speechLocaleId;
  }

  Future<void> _resetToIdle() async {
    _phase = VoiceAssistantPhase.idle;
    _lastUserCommand = null;
    _lastCommandPartial = '';
    _assistantMessage = '';
    notifyListeners();
  }

  Future<void> _stopListening() async {
    _sessionGeneration++;
    _wakeHandledInSession = false;
    _lastCommandPartial = '';
    final sessionCompleter = _listenSessionCompleter;
    if (sessionCompleter != null && !sessionCompleter.isCompleted) {
      sessionCompleter.complete();
    }
    _listenSessionCompleter = null;
    _voiceSttActive = false;
    await _silentMonitor.stop();
    if (_speech.isListening) {
      try {
        await _speech.stop();
      } catch (_) {}
    }
    if (_phase != VoiceAssistantPhase.idle) {
      _phase = VoiceAssistantPhase.idle;
      _lastUserCommand = null;
      _assistantMessage = '';
      notifyListeners();
    }
  }

  Future<void> _handleCommand(String? command, int generation) async {
    if (!_isGenerationCurrent(generation)) return;

    _phase = VoiceAssistantPhase.processing;
    _setAssistantMessageKey('voiceAssistantProcessing');
    notifyListeners();

    if (command == null || command.trim().isEmpty) {
      await _speak('voiceAssistantNoCommand');
      return;
    }

    _lastUserCommand = command.trim();
    notifyListeners();

    final normalized = _normalizeSpeech(command);
    if (_matchesNavigationCommand(normalized)) {
      await _speak('voiceAssistantOpeningNavigation');
      _openPage(const NavigationPage());
      return;
    }
    if (_matchesSettingsCommand(normalized)) {
      await _speak('voiceAssistantOpeningSettings');
      _openPage(const SettingsPage());
      return;
    }
    if (_matchesAppointmentsCommand(normalized)) {
      await _speak('voiceAssistantOpeningAppointments');
      _openPage(const AppointmentsPage());
      return;
    }
    if (_matchesBookAppointmentCommand(normalized)) {
      await _speak('voiceAssistantOpeningBookAppointment');
      _openPage(const BookAppointmentPage());
      return;
    }
    if (_matchesMedicationsCommand(normalized)) {
      await _speak('voiceAssistantOpeningMedications');
      _openPage(const MedicationsPage());
      return;
    }
    if (_matchesCommunicationCommand(normalized)) {
      await _speak('voiceAssistantOpeningCommunication');
      _openPage(const CommunicationPage());
      return;
    }
    if (_matchesHomeCommand(normalized)) {
      await _speak('voiceAssistantOpeningHome');
      _openMainMenu();
      return;
    }

    await _speak(
      'voiceAssistantCommandNotUnderstood',
      params: {'command': command},
    );
  }

  bool _matchesAny(String normalized, List<String> phrases) {
    return phrases.any(
      (phrase) => normalized == phrase || normalized.contains(phrase),
    );
  }

  bool _matchesAppointmentsCommand(String normalized) {
    return _matchesAny(normalized, const [
      'appointments',
      'my appointments',
      'show appointments',
      'open appointments',
    ]);
  }

  bool _matchesBookAppointmentCommand(String normalized) {
    return _matchesAny(normalized, const [
      'book appointment',
      'book an appointment',
      'make appointment',
      'schedule appointment',
    ]);
  }

  bool _matchesMedicationsCommand(String normalized) {
    return _matchesAny(normalized, const [
      'medication',
      'medications',
      'medicine',
      'my medicine',
      'open medications',
    ]);
  }

  bool _matchesCommunicationCommand(String normalized) {
    return _matchesAny(normalized, const [
      'communication',
      'messages',
      'message',
      'chat',
    ]);
  }

  bool _matchesHomeCommand(String normalized) {
    return _matchesAny(normalized, const [
      'main menu',
      'home',
      'go home',
      'open home',
    ]);
  }

  bool _matchesNavigationCommand(String normalized) {
    const phrases = <String>[
      'navigation',
      'navigate',
      'open navigation',
      'start navigation',
      'where to',
      'directions',
    ];
    return phrases.any(
      (phrase) => normalized == phrase || normalized.contains(phrase),
    );
  }

  bool _matchesSettingsCommand(String normalized) {
    const phrases = <String>[
      'settings',
      'open settings',
      'app settings',
    ];
    return phrases.any(
      (phrase) => normalized == phrase || normalized.contains(phrase),
    );
  }

  void _openPage(Widget page) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(builder: (context) => page),
      ),
    );
  }

  void _openMainMenu() {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.popUntil((route) => route.isFirst);
  }

  void _setAssistantMessageKey(
    String key, {
    Map<String, Object?> params = const {},
  }) {
    _assistantMessage = AppSettingsService.instance.localized(key, params);
  }

  bool _isGenerationCurrent(int generation) => generation == _sessionGeneration;

  Future<void> _speak(
    String key, {
    Map<String, Object?> params = const {},
  }) async {
    _setAssistantMessageKey(key, params: params);
    notifyListeners();
    final text = AppSettingsService.instance.localized(key, params);
    await AppSettingsService.instance.stopSpeaking();
    await AppSettingsService.instance.speakAndAwaitCompletion(text);
  }

  static bool containsWakePhrase(String text) {
    final normalized = _normalizeSpeech(text);
    if (normalized.isEmpty) return false;

    if (_hasWakePrefixAndAuraGuide(normalized)) return true;

    const directMatches = [
      'hey auraguide',
      'hey aura guide',
      'hi auraguide',
      'hi aura guide',
      'hello auraguide',
      'hello aura guide',
      'hey oral guide',
      'hey auto guide',
      'hey our guide',
      'hey aura guy',
      'hey aura guard',
      'hey awra guide',
      'hay aura guide',
      'hey ora guide',
      'a aura guide',
      'a auraguide',
    ];
    if (directMatches.any(normalized.contains)) return true;

    return RegExp(r'(hey|hi|hello|hay)\s+aura\s*guide').hasMatch(normalized);
  }

  static bool _hasWakePrefixAndAuraGuide(String normalized) {
    const wakePrefixes = ['hey', 'hi', 'hello', 'hay'];
    final hasPrefix = wakePrefixes.any(normalized.contains);
    if (!hasPrefix) return false;

    const auraHints = [
      'auraguide',
      'aura guide',
      'oral guide',
      'auto guide',
      'our guide',
      'aura guy',
      'aura gide',
      'aura guard',
      'awra guide',
      'ora guide',
    ];
    return auraHints.any(normalized.contains) ||
        RegExp(r'aura\s*guide').hasMatch(normalized);
  }

  static String _normalizeSpeech(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String stripWakePhrase(String text) {
    var normalized = _normalizeSpeech(text);
    normalized = normalized
        .replaceAll(
          RegExp(
            r'(hey|hi|hello|hay)\s+(aura|oral|auto|our|awra|ora)\s*(guide|guy|guard|gide)',
          ),
          '',
        )
        .replaceAll(RegExp(r'(hey|hi|hello|hay)\s+aura\s*guide'), '')
        .replaceAll(RegExp(r'\baura\s*guide\b'), '')
        .replaceAll('auraguide', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized;
  }
}

class _VoiceAssistantNavigatorObserver extends NavigatorObserver {
  void _notify(Route<dynamic>? route) {
    final label = route?.settings.name ?? route?.runtimeType.toString();
    VoiceAssistantCoordinator.instance.setTopRouteLabel(label);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notify(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notify(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _notify(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notify(previousRoute);
  }
}
