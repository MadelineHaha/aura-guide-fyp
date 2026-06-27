import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../emergency_sos_page.dart';
import '../health_records_page.dart';
import '../notifications_page.dart';
import '../appointments_page.dart';
import '../app_navigator.dart';
import '../auth_session.dart';
import '../communication_page.dart';
import '../login_page.dart';
import '../manual_register_page.dart';
import '../medications_page.dart';
import '../navigation_page.dart';
import '../settings_page.dart';
import '../voice_register_page.dart';
import '../utils/main_menu_voice.dart';
import 'app_settings_service.dart';
import 'app_experience_service.dart';
import 'device_permissions_service.dart';
import 'voice_flow_coordinator.dart';
import 'voice_flows/appointments_voice_flow.dart';
import 'voice_flows/communication_voice_flow.dart';
import 'voice_flows/health_records_voice_flow.dart';
import 'voice_flows/medications_voice_flow.dart';
import 'voice_flows/navigation_voice_flow.dart';
import 'fall_detection_coordinator.dart';
import 'patient_call_session.dart';
import 'silent_mic_monitor_service.dart';
import 'voice_call_service.dart';

enum VoiceAssistantPhase { idle, greeting, awaitingCommand, processing }

/// Foreground wake-word assistant: listens for "Hey AuraGuide", greets back,
/// then captures a short voice command.
class VoiceAssistantCoordinator extends ChangeNotifier {
  VoiceAssistantCoordinator._();

  static final VoiceAssistantCoordinator instance =
      VoiceAssistantCoordinator._();

  static const _voiceSttSeconds = 25;
  static const _commandListenSeconds = 10;
  static const _sttHandoffDelayMs = 450;
  static const _postTtsListenDelayMs = 400;
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
  Completer<void>? _speechInitCompleter;
  String _lastCommandPartial = '';
  bool _finalizingCommand = false;
  bool _lastVoiceConversationEnabled = false;

  VoiceAssistantPhase get phase => _phase;
  bool get isAwaitingCommand => _phase == VoiceAssistantPhase.awaitingCommand;
  String? get topRouteLabel => _topRouteLabel;
  String? get lastUserCommand => _lastUserCommand;
  String get assistantMessage => _assistantMessage;
  bool get isActive => _phase != VoiceAssistantPhase.idle;
  bool get isWelcomeSessionActive => _welcomeSessionActive;

  bool get _showsVoiceConversation =>
      AppSettingsService.instance.isVoiceConversationEnabled;

  void ensureStarted() {
    if (_started) {
      _ensureListening();
      return;
    }
    _started = true;
    _lastVoiceConversationEnabled = _showsVoiceConversation;
    FirebaseAuth.instance.authStateChanges().listen((_) => _ensureListening());
    AppSettingsService.instance.addListener(_onSettingsChanged);
    AppExperienceService.instance.addListener(_onExperienceChanged);
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
    if (_phase != VoiceAssistantPhase.awaitingCommand && !_voiceDialogActive) {
      _sessionGeneration++; // Cancel pending auto-prompts or idle wake sessions
    }
    if (!_canRun) {
      unawaited(_stopListening());
    } else {
      _ensureListening();
    }
    _autoPromptForCurrentRoute();
  }

  void _autoPromptForCurrentRoute() async {
    final generation = _sessionGeneration;

    // Small delay to allow page transition to finish
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (_topRouteLabel == null || !_isGenerationCurrent(generation)) return;
    if (!_showsVoiceConversation) return;

    final promptKey = _getPromptKeyForCurrentRoute();

    if (promptKey == null) return;

    if (_topRouteLabel!.contains('SettingsPage')) {
      if (!_voiceDialogActive && !VoiceFlowCoordinator.instance.isActive) {
        unawaited(VoiceFlowCoordinator.instance.startSettingsFlow());
      }
      return;
    }

    if (_topRouteLabel!.contains('MedicationsPage')) {
      if (!_voiceDialogActive && !VoiceFlowCoordinator.instance.isActive) {
        unawaited(_promptMedicationsPage(generation));
      }
      return;
    }

    if (_topRouteLabel!.contains('HealthRecordsPage')) {
      if (!_voiceDialogActive && !VoiceFlowCoordinator.instance.isActive) {
        unawaited(_promptHealthRecordsPage(generation));
      }
      return;
    }

    if (_topRouteLabel!.contains('AppointmentsPage')) {
      if (!_voiceDialogActive && !VoiceFlowCoordinator.instance.isActive) {
        unawaited(_promptAppointmentsPage(generation));
      }
      return;
    }

    if (_topRouteLabel!.contains('NavigationPage')) {
      if (!_voiceDialogActive && !VoiceFlowCoordinator.instance.isActive) {
        unawaited(_promptNavigationPage(generation));
      }
      return;
    }

    if (_topRouteLabel!.contains('CommunicationPage')) {
      if (!_voiceDialogActive && !VoiceFlowCoordinator.instance.isActive) {
        unawaited(_promptCommunicationPage(generation));
      }
      return;
    }

    if (!_voiceDialogActive && !VoiceFlowCoordinator.instance.isActive) {
      unawaited(_onWakeDetected(generation, customGreetingKey: promptKey));
    }
  }

  Future<void> _promptMedicationsPage(int generation) async {
    if (!_isGenerationCurrent(generation)) return;
    if (_voiceDialogActive || VoiceFlowCoordinator.instance.isActive) return;

    _voiceDialogActive = true;
    notifyListeners();
    try {
      await MedicationsVoiceFlow().run();
    } finally {
      _voiceDialogActive = false;
      notifyListeners();
    }
  }

  Future<void> _promptHealthRecordsPage(int generation) async {
    if (!_isGenerationCurrent(generation)) return;
    if (_voiceDialogActive || VoiceFlowCoordinator.instance.isActive) return;

    _voiceDialogActive = true;
    notifyListeners();
    try {
      await HealthRecordsVoiceFlow().run();
    } finally {
      _voiceDialogActive = false;
      notifyListeners();
    }
  }

  Future<void> _promptAppointmentsPage(int generation) async {
    if (!_isGenerationCurrent(generation)) return;
    if (_voiceDialogActive || VoiceFlowCoordinator.instance.isActive) return;

    _voiceDialogActive = true;
    notifyListeners();
    try {
      await AppointmentsVoiceFlow().run();
    } finally {
      _voiceDialogActive = false;
      notifyListeners();
    }
  }

  Future<void> _promptNavigationPage(int generation) async {
    if (!_isGenerationCurrent(generation)) return;
    if (_voiceDialogActive || VoiceFlowCoordinator.instance.isActive) return;

    _voiceDialogActive = true;
    notifyListeners();
    try {
      await NavigationVoiceFlow().run();
    } finally {
      _voiceDialogActive = false;
      notifyListeners();
    }
  }

  Future<void> _promptCommunicationPage(int generation) async {
    if (!_isGenerationCurrent(generation)) return;
    if (_voiceDialogActive || VoiceFlowCoordinator.instance.isActive) return;

    _voiceDialogActive = true;
    notifyListeners();
    try {
      await CommunicationVoiceFlow().run();
    } finally {
      _voiceDialogActive = false;
      notifyListeners();
    }
  }

  String? _getPromptKeyForCurrentRoute() {
    if (_topRouteLabel == null) return null;
    final routes = <String, String>{
      'MainMenuPage': 'pagePromptMainMenu',
      'AppointmentsPage': 'pagePromptAppointments',
      'MedicationsPage': 'pagePromptMedications',
      'CommunicationPage': 'pagePromptCommunication',
      'NavigationPage': 'pagePromptNavigation',
      'SettingsPage': 'pagePromptSettings',
      'RegisterPage': 'pagePromptRegister',
      'ManualRegisterPage': 'pagePromptManualRegister',
      'LoginPage': 'pagePromptLogin',
      'HealthRecordsPage': 'pagePromptHealthRecords',
      'NotificationsPage': 'pagePromptNotifications',
      'ProfilePage': 'pagePromptProfile',
      'MyProfilePage': 'pagePromptProfile',
      'EmergencySosPage': 'pagePromptEmergency',
      'CaregiverHomePage': 'pagePromptCaregiverHome',
      'DoctorHomePage': 'pagePromptDoctorHome',
    };

    return routes.entries
            .where((e) => _topRouteLabel!.contains(e.key))
            .map((e) => e.value)
            .firstOrNull ??
        'voiceFlowMenuPrompt';
  }

  void acquireMicLock() {
    _micLockCount++;
    if (_micLockCount == 1) {
      _sessionGeneration++;
      unawaited(_stopListening());
    }
  }

  void releaseMicLock() {
    if (_micLockCount <= 0) return;
    _micLockCount--;
    if (_canRun) {
      _ensureListening();
    }
  }

  void _onSettingsChanged() {
    _speechLocaleId = null;
    if (!AppExperienceService.instance.isPatientExperience) {
      unawaited(_stopListening());
      return;
    }

    final voiceConversation = _showsVoiceConversation;
    if (!voiceConversation) {
      _lastVoiceConversationEnabled = false;
      unawaited(_stopListening());
      unawaited(AppSettingsService.instance.stopSpeaking());
      _assistantMessage = '';
      _lastUserCommand = null;
      VoiceFlowCoordinator.instance.cancelActiveFlow();
      notifyListeners();
      return;
    }

    if (!_lastVoiceConversationEnabled) {
      _lastVoiceConversationEnabled = true;
      notifyListeners();
      unawaited(resumeVoiceOnlyExperience());
      return;
    }

    if (AppSettingsService.instance.settings.voiceAssistantEnabled) {
      _ensureListening();
    } else {
      unawaited(_stopListening());
    }
    notifyListeners();
  }

  /// Starts the voice-only workflow after the user turns voice-only back on.
  Future<void> resumeVoiceOnlyExperience() async {
    if (!_canRun || !_showsVoiceConversation) return;
    if (_voiceDialogActive) return;

    if (VoiceFlowCoordinator.instance.isActive ||
        VoiceFlowCoordinator.instance.isWelcomeActive) {
      await _speak('voiceOnlyModeEnabledAnnouncement');
      _setAssistantMessageKey('voiceAssistantListening');
      notifyListeners();
      _ensureListening();
      return;
    }

    await AppSettingsService.instance.stopSpeaking();
    await _stopListening();
    final generation = _sessionGeneration;

    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!_isGenerationCurrent(generation) || !_showsVoiceConversation) return;

    await _speak('voiceOnlyModeEnabledAnnouncement');
    if (!_isGenerationCurrent(generation)) return;

    if (_topRouteLabel?.contains('SettingsPage') ?? false) {
      if (!VoiceFlowCoordinator.instance.isActive) {
        await VoiceFlowCoordinator.instance.startSettingsFlow(openPage: false);
      }
      return;
    }

    if (_topRouteLabel?.contains('MedicationsPage') ?? false) {
      await _promptMedicationsPage(generation);
      return;
    }

    if (_topRouteLabel?.contains('HealthRecordsPage') ?? false) {
      await _promptHealthRecordsPage(generation);
      return;
    }

    if (_topRouteLabel?.contains('AppointmentsPage') ?? false) {
      await _promptAppointmentsPage(generation);
      return;
    }

    if (_topRouteLabel?.contains('NavigationPage') ?? false) {
      await _promptNavigationPage(generation);
      return;
    }

    if (_topRouteLabel?.contains('CommunicationPage') ?? false) {
      await _promptCommunicationPage(generation);
      return;
    }

    final promptKey = _getPromptKeyForCurrentRoute() ?? 'voiceFlowMenuPrompt';
    await _onWakeDetected(generation, customGreetingKey: promptKey);
  }

  void _onExperienceChanged() {
    if (!AppExperienceService.instance.isPatientExperience) {
      unawaited(stopForNonPatientApp());
    } else {
      _ensureListening();
    }
  }

  /// Stops wake-word listening and TTS when staff/caregiver apps are active.
  Future<void> stopForNonPatientApp() async {
    await _stopListening();
    await AppSettingsService.instance.stopSpeaking();
    await _resetToIdle();
  }

  bool get _canRun {
    if (!_started || !_appResumed) return false;
    if (!AppExperienceService.instance.isPatientExperience) return false;
    if (FirebaseAuth.instance.currentUser == null &&
        AuthSession.resolveUser() == null) {
      return false;
    }
    if (!AppSettingsService.instance.settings.voiceAssistantEnabled) {
      return false;
    }
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
    if (_voiceSttActive || _speech.isListening || _silentMonitor.isRunning) {
      return;
    }

    final micGranted = await DevicePermissionsService.instance
        .ensureMicrophone();
    final speechGranted = await DevicePermissionsService.instance
        .ensureSpeechRecognition();
    if (!micGranted ||
        !speechGranted ||
        !_canRun ||
        _phase != VoiceAssistantPhase.idle) {
      return;
    }

    try {
      await _silentMonitor.start(() {
        if (!_canRun || _phase != VoiceAssistantPhase.idle || _voiceSttActive) {
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

          if (containsWakePhrase(heard)) {
            _wakeHandledInSession = true;
            final trailingCommand = stripWakePhrase(heard);
            unawaited(
              _onWakeDetected(
                generation,
                prefilledCommand: trailingCommand.isNotEmpty
                    ? trailingCommand
                    : null,
              ),
            );
            return;
          }

          if (!_showsVoiceConversation || !result.finalResult) return;

          final directCommand = stripWakePhrase(heard).trim();
          if (directCommand.isEmpty) return;
          if (!matchesGlobalNavigationCommand(directCommand)) return;

          _wakeHandledInSession = true;
          unawaited(_handleDirectGlobalNavigation(directCommand, generation));
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
        resumeSilent:
            _phase == VoiceAssistantPhase.idle &&
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

    if (_speechInitCompleter != null) {
      await _speechInitCompleter!.future;
      return;
    }
    _speechInitCompleter = Completer<void>();

    try {
      final available = await _speech.initialize(
        onStatus: _onSpeechStatus,
        onError: (error) {
          debugPrint('VoiceAssistantCoordinator STT error: $error');
        },
      );
      _speechReady = available;
    } finally {
      final completer = _speechInitCompleter;
      _speechInitCompleter = null;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }
  }

  void _onSpeechStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      final sessionCompleter = _listenSessionCompleter;
      if (sessionCompleter != null && !sessionCompleter.isCompleted) {
        sessionCompleter.complete();
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
    await _silentMonitor.stop();

    final micGranted = await DevicePermissionsService.instance
        .ensureMicrophone();
    final speechGranted = await DevicePermissionsService.instance
        .ensureSpeechRecognition();
    if (!micGranted || !speechGranted || !_isGenerationCurrent(generation)) {
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

    await _ensureSpeechReady();
    if (!_speechReady || !_isGenerationCurrent(generation)) {
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
          listenMode: ListenMode.dictation,
        ),
        onResult: (result) {
          if (!_isGenerationCurrent(generation)) {
            unawaited(_speech.stop());
            return;
          }
          if (_phase != VoiceAssistantPhase.awaitingCommand) return;

          final text = stripWakePhrase(result.recognizedWords).trim();
          if (text.isEmpty) return;

          debugPrint(
            'VoiceAssistantCoordinator command heard: "$text" '
            'final=${result.finalResult}',
          );
          _lastCommandPartial = text;
          _lastUserCommand = text;
          notifyListeners();
        },
      );

      while (_speech.isListening && _isGenerationCurrent(generation)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      await Future<void>.delayed(const Duration(milliseconds: 200));
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

      final handled = await _handleCommand(
        resolved.isEmpty ? null : resolved,
        generation,
      );

      if (!_isGenerationCurrent(generation)) return;

      if (handled) {
        await _resetToIdle();
        if (_canRun) {
          _ensureListening();
        }
      } else {
        _phase = VoiceAssistantPhase.awaitingCommand;
        _lastCommandPartial = '';
        _setAssistantMessageKey('voiceAssistantListening');
        notifyListeners();
        unawaited(_listenForCommand(generation));
      }
    } finally {
      _finalizingCommand = false;
    }
  }

  Future<void> _onWakeDetected(
    int generation, {
    String? prefilledCommand,
    String customGreetingKey = 'voiceAssistantGreeting',
    String? customGreetingText,
  }) async {
    if (!_isGenerationCurrent(generation)) return;

    _lastUserCommand = null;
    _phase = VoiceAssistantPhase.greeting;
    if (customGreetingText != null && customGreetingText.trim().isNotEmpty) {
      _assistantMessage = customGreetingText.trim();
    } else {
      _setAssistantMessageKey(customGreetingKey);
    }
    notifyListeners();

    await _silentMonitor.stop();
    await _speech.stop();
    await Future<void>.delayed(
      const Duration(milliseconds: _sttHandoffDelayMs),
    );
    await AppSettingsService.instance.stopSpeaking();
    if (customGreetingText != null && customGreetingText.trim().isNotEmpty) {
      if (!_showsVoiceConversation) return;
      await AppSettingsService.instance.speakAndAwaitCompletion(
        customGreetingText.trim(),
      );
      await Future<void>.delayed(
        const Duration(milliseconds: _postTtsListenDelayMs),
      );
    } else {
      await _speak(customGreetingKey);
    }

    if (!_isGenerationCurrent(generation)) {
      await _resetToIdle();
      return;
    }

    await Future<void>.delayed(
      const Duration(milliseconds: _postTtsListenDelayMs),
    );
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
    final lang = AppSettingsService.instance.settings.languageCode;
    final preferred = switch (lang) {
      'zh' => const ['zh_CN', 'zh_TW', 'zh_HK', 'zh_SG', 'zh'],
      'ms' => const ['ms_MY', 'ms'],
      // Malaysian English first — better for local accents than en_GB.
      _ => const ['en_MY', 'en_SG', 'en_US', 'en_AU', 'en_GB', 'en'],
    };

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
    _speechLocaleId = preferred.last;
    return _speechLocaleId;
  }

  Future<void> _resetToIdle() async {
    _phase = VoiceAssistantPhase.idle;
    _lastUserCommand = null;
    _lastCommandPartial = '';
    if (_showsVoiceConversation) {
      _setAssistantMessageKey('voiceAssistantListening');
    } else {
      _assistantMessage = '';
    }
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

  Future<bool> _handleCommand(String? command, int generation) async {
    if (!_isGenerationCurrent(generation)) return true;

    _phase = VoiceAssistantPhase.processing;
    _setAssistantMessageKey('voiceAssistantProcessing');
    notifyListeners();

    if (command == null || command.trim().isEmpty) {
      await _speak('voiceAssistantNoCommand');
      final promptKey = _getPromptKeyForCurrentRoute();
      if (promptKey != null) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await _speak(promptKey);
      }
      return false;
    }

    if (_showsVoiceConversation) {
      _lastUserCommand = command.trim();
      notifyListeners();
    }

    final normalized = _normalizeSpeech(command);
    if (_matchesDisableVoiceOnlyCommand(normalized)) {
      await AppSettingsService.instance.setVoiceOnlyModeEnabled(false);
      return true;
    }
    if (_matchesBookAppointmentCommand(normalized)) {
      if (_showsVoiceConversation) {
        await _speak('voiceAssistantOpeningBookAppointment');
        unawaited(VoiceFlowCoordinator.instance.startBookAppointmentFlow());
      } else {
        _openPage(const AppointmentsPage());
      }
      return true;
    }

    if (_isOnMainMenuPage()) {
      // Handle "list" command — read out all available options
      if (MainMenuVoice.matchesListCommand(command)) {
        await _speak('mainMenuVoiceListOptions');
        return false; // Keep listening for the user's actual choice
      }

      final menuCommand = MainMenuVoice.parseCommand(command);
      if (menuCommand != null) {
        return _handleMainMenuCommand(menuCommand, generation);
      }
    }

    if (MainMenuVoice.parseCommand(command) == MainMenuVoiceCommand.emergency) {
      await _handoffMicForEmergency();
      _openEmergencySosPage(voiceTriggered: true);
      return true;
    }

    if (_matchesGoBackCommand(normalized)) {
      await _speak('voiceAssistantOpeningGoBack');
      _goBack();
      return true;
    }
    if (_matchesNavigationCommand(normalized)) {
      await _speak('voiceAssistantOpeningNavigation');
      _openPage(const NavigationPage());
      return true;
    }
    if (_matchesSettingsCommand(normalized)) {
      if (_showsVoiceConversation) {
        await _speak('voiceAssistantOpeningSettings');
        unawaited(
          VoiceFlowCoordinator.instance.startSettingsFlow(openPage: true),
        );
      } else {
        _openPage(const SettingsPage());
      }
      return true;
    }
    if (_matchesAppointmentsCommand(normalized)) {
      await _speak('voiceAssistantOpeningAppointments');
      _openPage(const AppointmentsPage());
      return true;
    }
    if (_matchesMedicationsCommand(normalized)) {
      await _speak('voiceAssistantOpeningMedications');
      _openPage(const MedicationsPage());
      return true;
    }
    if (_matchesCommunicationCommand(normalized)) {
      await _speak('voiceAssistantOpeningCommunication');
      _openPage(const CommunicationPage());
      return true;
    }
    if (_matchesHomeCommand(normalized)) {
      await _speak('voiceAssistantOpeningHome');
      _openMainMenu();
      return true;
    }
    if (_matchesSignOutCommand(normalized)) {
      _openPage(const LoginPage());
      return true;
    }
    if (_matchesCancelCommand(normalized)) {
      await _speak('sosEmergencyVoiceCancelled');
      return true; // Handled by standard cancellation logic actually
    }
    if (_matchesVoiceRegisterCommand(normalized)) {
      _openPage(const VoiceRegisterPage());
      return true;
    }
    if (_matchesManualRegisterCommand(normalized)) {
      _openPage(const ManualRegisterPage());
      return true;
    }
    if (_matchesLoginCommand(normalized)) {
      _openPage(const LoginPage());
      return true;
    }

    await _speak(
      'voiceAssistantCommandNotUnderstood',
      params: {'command': command},
    );
    final promptKey = _getPromptKeyForCurrentRoute();
    if (promptKey != null) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _speak(promptKey);
    }
    return false;
  }

  bool _matchesAny(String normalized, List<String> phrases) {
    return phrases.any(
      (phrase) => normalized == phrase || normalized.contains(phrase),
    );
  }

  bool _matchesDisableVoiceOnlyCommand(String normalized) {
    return _matchesAny(normalized, const [
      'enable touch',
      'touch mode',
      'disable voice only',
      'turn off voice only',
      'turn off voice only mode',
    ]);
  }

  bool _isOnMainMenuPage() {
    final label = _topRouteLabel;
    return label != null && label.contains('MainMenuPage');
  }

  Future<bool> _handleMainMenuCommand(
    MainMenuVoiceCommand command,
    int generation,
  ) async {
    if (!_isGenerationCurrent(generation)) return true;

    switch (command) {
      case MainMenuVoiceCommand.emergency:
        await _handoffMicForEmergency();
        _openEmergencySosPage(voiceTriggered: true);
        return true;
      case MainMenuVoiceCommand.medications:
        await _speak('voiceAssistantOpeningMedications');
        _openPage(const MedicationsPage());
        return true;
      case MainMenuVoiceCommand.appointments:
        await _speak('voiceAssistantOpeningAppointments');
        _openPage(const AppointmentsPage());
        return true;
      case MainMenuVoiceCommand.healthRecords:
        await _speak('voiceAssistantOpeningHealthRecords');
        _openPage(const HealthRecordsPage());
        return true;
      case MainMenuVoiceCommand.navigation:
        await _speak('voiceAssistantOpeningNavigation');
        _openPage(const NavigationPage());
        return true;
      case MainMenuVoiceCommand.communication:
        await _speak('voiceAssistantOpeningCommunication');
        _openPage(const CommunicationPage());
        return true;
      case MainMenuVoiceCommand.settings:
        if (_showsVoiceConversation) {
          await _speak('voiceAssistantOpeningSettings');
          unawaited(
            VoiceFlowCoordinator.instance.startSettingsFlow(openPage: true),
          );
        } else {
          _openPage(const SettingsPage());
        }
        return true;
      case MainMenuVoiceCommand.notifications:
        await _speak('voiceAssistantOpeningNotifications');
        _openPage(const NotificationsPage());
        return true;
    }
  }

  Future<void> _handoffMicForEmergency() async {
    _sessionGeneration++;
    await _stopListening();
    await AppSettingsService.instance.stopSpeaking();
    await Future<void>.delayed(
      const Duration(milliseconds: _sttHandoffDelayMs),
    );
  }

  void _openEmergencySosPage({bool voiceTriggered = false}) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    unawaited(
      navigator.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'EmergencySosPage'),
          builder: (context) =>
              EmergencySosPage(voiceTriggered: voiceTriggered),
        ),
      ),
    );
  }

  bool _matchesGoBackCommand(String normalized) {
    return matchesGlobalGoBack(normalized);
  }

  static bool matchesGlobalGoBack(String speech) {
    final normalized = _normalizeSpeech(speech);
    return _matchesAnyStatic(normalized, const [
      'go back',
      'back',
      'previous page',
      'return',
      'go backward',
      'step back',
      'kembali',
      'balik',
      '返回',
      '回去',
      '上一页',
    ]);
  }

  static bool matchesGlobalGoHome(String speech) {
    final normalized = _normalizeSpeech(speech);
    return _matchesAnyStatic(normalized, const [
      'main menu',
      'home',
      'go home',
      'open home',
      'menu utama',
      '主页',
      '首页',
    ]);
  }

  static bool matchesGlobalNavigationCommand(String speech) {
    final normalized = _normalizeSpeech(speech);
    if (normalized.isEmpty) return false;
    return matchesGlobalGoBack(normalized) || matchesGlobalGoHome(normalized);
  }

  static bool _matchesAnyStatic(String normalized, List<String> phrases) {
    return phrases.any(
      (phrase) => normalized == phrase || normalized.contains(phrase),
    );
  }

  Future<void> _handleDirectGlobalNavigation(
    String command,
    int generation,
  ) async {
    if (!_isGenerationCurrent(generation)) return;

    await _endVoiceSttSession(resumeSilent: false);
    if (!_isGenerationCurrent(generation)) return;

    await tryHandleGlobalNavigationCommand(command);
    await _resetToIdle();
    _ensureListening();
  }

  /// Global escape hatch: "go back" / "go home" work even when not spoken as
  /// an option in the current voice prompt.
  Future<bool> tryHandleGlobalNavigationCommand(String? command) async {
    if (command == null || command.trim().isEmpty) return false;

    final normalized = _normalizeSpeech(command);
    if (_matchesGoBackCommand(normalized)) {
      VoiceFlowCoordinator.instance.cancelActiveFlow();
      await cancelActiveDialog();
      await _speak('voiceAssistantOpeningGoBack');
      _goBack();
      return true;
    }
    if (_matchesHomeCommand(normalized)) {
      VoiceFlowCoordinator.instance.cancelActiveFlow();
      await cancelActiveDialog();
      await _speak('voiceAssistantOpeningHome');
      _openMainMenu();
      return true;
    }
    return false;
  }

  bool _matchesAppointmentsCommand(String normalized) {
    if (_matchesBookAppointmentCommand(normalized)) return false;
    return _matchesAny(normalized, const [
      'appointment',
      'my appointment',
      'show appointment',
      'open appointment',
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

  bool _matchesSignOutCommand(String normalized) {
    return _matchesAny(normalized, const [
      'sign out',
      'log out',
      'logout',
      'signout',
    ]);
  }

  bool _matchesCancelCommand(String normalized) {
    return _matchesAny(normalized, const ['cancel', 'stop', 'abort']);
  }

  bool _matchesVoiceRegisterCommand(String normalized) {
    return _matchesAny(normalized, const [
      'voice register',
      'register with voice',
      'use voice',
    ]);
  }

  bool _matchesManualRegisterCommand(String normalized) {
    return _matchesAny(normalized, const [
      'manual register',
      'register manually',
      'use keyboard',
      'type it',
    ]);
  }

  bool _matchesLoginCommand(String normalized) {
    return _matchesAny(normalized, const ['sign in', 'login', 'log in']);
  }

  bool _matchesMedicationsCommand(String normalized) {
    return _matchesAny(normalized, const [
      'medication',
      'my medication',
      'show medication',
      'open medication',
      'pill',
      'medicine',
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
    return matchesGlobalGoHome(normalized);
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
      'setting',
      'settings',
      'open setting',
      'open settings',
      'app setting',
      'my settings',
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
        MaterialPageRoute<void>(
          settings: RouteSettings(name: page.runtimeType.toString()),
          builder: (context) => page,
        ),
      ),
    );
  }

  void _goBack() {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    if (navigator.canPop()) {
      navigator.pop();
    }
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
    if (!_showsVoiceConversation) return;
    _assistantMessage = AppSettingsService.instance.localized(key, params);
  }

  bool _isGenerationCurrent(int generation) => generation == _sessionGeneration;

  Future<void> _speak(
    String key, {
    Map<String, Object?> params = const {},
  }) async {
    if (!_showsVoiceConversation) return;
    _setAssistantMessageKey(key, params: params);
    notifyListeners();
    final text = AppSettingsService.instance.localized(key, params);
    await AppSettingsService.instance.stopSpeaking();
    await AppSettingsService.instance.speakAndAwaitCompletion(text);
    await Future<void>.delayed(
      const Duration(milliseconds: _postTtsListenDelayMs),
    );
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
  // --- VOICE FLOW SUPPORT ---

  int _dialogGeneration = 0;
  bool _voiceDialogActive = false;
  bool _welcomeSessionActive = false;

  bool _isDialogGenerationCurrent(int generation) {
    return _dialogGeneration == generation && _voiceDialogActive;
  }

  void beginWelcomeSession() {
    _welcomeSessionActive = true;
    notifyListeners();
  }

  void endWelcomeSession() {
    _welcomeSessionActive = false;
    notifyListeners();
  }

  Future<void> speakPrompt(
    String key, {
    Map<String, Object?> params = const {},
  }) async {
    await _speak(key, params: params);
  }

  Future<void> speakText(String text) async {
    if (!_showsVoiceConversation) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _assistantMessage = trimmed;
    notifyListeners();
    await AppSettingsService.instance.stopSpeaking();
    await AppSettingsService.instance.speakAndAwaitCompletion(trimmed);
    await Future<void>.delayed(
      const Duration(milliseconds: _postTtsListenDelayMs),
    );
  }

  Future<bool> confirmPrompt(
    String promptKey, {
    Map<String, Object?> params = const {},
  }) async {
    final answer = await promptAndListen(promptKey, params: params);
    if (answer == null) return false;
    final normalized = normalizeSpeech(answer);
    if (normalized == 'yes' ||
        normalized == 'yeah' ||
        normalized == 'yep' ||
        normalized == 'ok') {
      return true;
    }
    return false;
  }

  /// Listens for one utterance while a managed voice session is active.
  Future<String?> listenForUtterance({
    Duration listenFor = const Duration(seconds: 16),
    String listeningMessageKey = 'voiceAssistantListening',
  }) async {
    if (!_voiceDialogActive) return null;

    final generation = ++_dialogGeneration;
    _phase = VoiceAssistantPhase.awaitingCommand;
    _setAssistantMessageKey(listeningMessageKey);
    notifyListeners();

    await _endVoiceSttSession(resumeSilent: false);
    final heard = await _captureUtterance(generation, listenFor: listenFor);
    if (heard != null && await tryHandleGlobalNavigationCommand(heard)) {
      throw const VoiceFlowNavigationException();
    }
    return heard;
  }

  /// Speaks a short not-captured prompt, then listens again without repeating
  /// the prior menu or action instructions.
  Future<String?> listenAfterNotCaptured({
    Duration listenFor = const Duration(seconds: 16),
    String listeningMessageKey = 'voiceAssistantListening',
    String notCapturedPromptKey = 'voiceCaptureNotHeard',
  }) async {
    await speakPrompt(notCapturedPromptKey);
    return listenForUtterance(
      listenFor: listenFor,
      listeningMessageKey: listeningMessageKey,
    );
  }

  /// Keeps listening until speech is captured or navigation cancels the flow.
  Future<String> listenUntilCaptured({
    Duration listenFor = const Duration(seconds: 16),
    String listeningMessageKey = 'voiceAssistantListening',
    String notCapturedPromptKey = 'voiceCaptureNotHeard',
  }) async {
    while (true) {
      final answer = await listenForUtterance(
        listenFor: listenFor,
        listeningMessageKey: listeningMessageKey,
      );
      if (answer != null && answer.trim().isNotEmpty) {
        return answer.trim();
      }
      await speakPrompt(notCapturedPromptKey);
    }
  }

  Future<String?> speakPromptAndListen(
    String promptKey, {
    Map<String, Object?> params = const {},
    Duration listenFor = const Duration(seconds: 16),
  }) async {
    _voiceDialogActive = true;
    final generation = ++_dialogGeneration;
    _sessionGeneration++;
    _phase = VoiceAssistantPhase.processing;
    _setAssistantMessageKey(promptKey, params: params);
    notifyListeners();

    try {
      await _endVoiceSttSession(resumeSilent: false);
      await AppSettingsService.instance.stopSpeaking();
      await _speak(promptKey, params: params);
      if (!_isDialogGenerationCurrent(generation)) return null;

      final resolved = await _captureUtterance(
        generation,
        listenFor: listenFor,
      );
      if (resolved != null &&
          await tryHandleGlobalNavigationCommand(resolved)) {
        throw const VoiceFlowNavigationException();
      }
      return resolved;
    } on VoiceFlowNavigationException {
      rethrow;
    } finally {
      _voiceDialogActive = false;
      _lastCommandPartial = '';
      notifyListeners();
    }
  }

  Future<String?> promptAndListen(
    String promptKey, {
    Map<String, Object?> params = const {},
    Duration listenFor = const Duration(seconds: 16),
  }) async {
    _voiceDialogActive = true;
    final generation = ++_dialogGeneration;
    _sessionGeneration++;
    _phase = VoiceAssistantPhase.processing;
    _setAssistantMessageKey(promptKey, params: params);
    notifyListeners();

    try {
      await _endVoiceSttSession(resumeSilent: false);
      await AppSettingsService.instance.stopSpeaking();
      await _speak(promptKey, params: params);
      if (!_isDialogGenerationCurrent(generation)) return null;

      final resolved = await _captureUtterance(
        generation,
        listenFor: listenFor,
      );
      if (resolved != null &&
          await tryHandleGlobalNavigationCommand(resolved)) {
        throw const VoiceFlowNavigationException();
      }
      return resolved;
    } on VoiceFlowNavigationException {
      rethrow;
    } finally {
      _voiceDialogActive = false;
      _lastCommandPartial = '';
      notifyListeners();
    }
  }

  Future<String?> _captureUtterance(
    int generation, {
    Duration listenFor = const Duration(seconds: 16),
  }) async {
    await _silentMonitor.stop();
    final micGranted = await DevicePermissionsService.instance
        .ensureMicrophone();
    final speechGranted = await DevicePermissionsService.instance
        .ensureSpeechRecognition();
    if (!micGranted ||
        !speechGranted ||
        !_isDialogGenerationCurrent(generation)) {
      return null;
    }

    await _ensureSpeechReady();
    if (!_speechReady || !_isDialogGenerationCurrent(generation)) return null;

    var heard = '';
    String? finalHeard;

    try {
      await _speech.listen(
        listenFor: listenFor,
        pauseFor: const Duration(seconds: 4),
        localeId: await _resolveListenLocale(),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
        onResult: (result) {
          if (!_isDialogGenerationCurrent(generation)) {
            unawaited(_speech.stop());
            return;
          }

          final text = stripWakePhrase(result.recognizedWords).trim();
          if (text.isEmpty) return;

          heard = text;
          if (result.finalResult) {
            finalHeard = text;
          }
        },
      );

      while (_speech.isListening && _isDialogGenerationCurrent(generation)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      await Future<void>.delayed(const Duration(milliseconds: 200));
    } catch (error) {
      debugPrint('VoiceAssistantCoordinator capture failed: $error');
    }

    if (!_isDialogGenerationCurrent(generation)) return null;

    final resolved = (finalHeard ?? heard).trim();
    return resolved.isEmpty ? null : resolved;
  }

  void resumeAfterVoiceFlow() {
    _ensureListening();
  }

  /// Re-enters the main-menu voice prompt after a page returns to the root.
  ///
  /// Emergency SOS holds the microphone while it is visible, so this waits for
  /// the pop/dispose cycle to release that lock before speaking and listening.
  Future<void> promptMainMenuAfterReturn() async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (!_canRun || !_showsVoiceConversation || !_isOnMainMenuPage()) {
      _ensureListening();
      return;
    }
    if (_voiceDialogActive || VoiceFlowCoordinator.instance.isActive) return;

    final generation = ++_sessionGeneration;
    await _onWakeDetected(generation, customGreetingKey: 'pagePromptMainMenu');
  }

  Future<void> cancelActiveDialog() async {
    _dialogGeneration++;
    _sessionGeneration++;
    _voiceDialogActive = false;
    _finalizingCommand = false;
    _lastCommandPartial = '';
    await _stopListening();
    await AppSettingsService.instance.stopSpeaking();
    notifyListeners();
  }

  static String normalizeSpeech(String speech) {
    return _normalizeSpeech(speech);
  }
}

class VoiceFlowCancelledException implements Exception {
  const VoiceFlowCancelledException();
}

/// Thrown after [tryHandleGlobalNavigationCommand] already navigated away.
class VoiceFlowNavigationException implements Exception {
  const VoiceFlowNavigationException();
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
