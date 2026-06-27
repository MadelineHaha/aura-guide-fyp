import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'models/emergency_alert_entity.dart';
import 'services/app_settings_service.dart';
import 'services/device_permissions_service.dart';
import 'services/emergency_alert_service.dart';
import 'services/emergency_alert_sound_service.dart';
import 'services/emergency_ai_service.dart';
import 'services/voice_assistant_coordinator.dart';
import 'l10n/app_localizations.dart';
import 'widgets/accessible_focus_region.dart';
import 'widgets/app_back_button.dart';

class EmergencySosPage extends StatefulWidget {
  const EmergencySosPage({super.key, this.voiceTriggered = false});

  /// When true, skip idle help listening and start the 5-second alert countdown.
  final bool voiceTriggered;

  @override
  State<EmergencySosPage> createState() => _EmergencySosPageState();
}

class _EmergencySosPageState extends State<EmergencySosPage> {
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _accent = Color(0xFF63C3C4);
  static const Color _sosRed = Color(0xFFE13636);
  static const Color _sosSentGreen = Color(0xFF2ECC71);
  static const Color _gpsCard = Color(0xFF1A1A1A);
  static const int _countdownStart = 5;

  /// Quiet window for the user to say "cancel" between countdown beeps.
  static const Duration _tickListenWindow = Duration(milliseconds: 2000);

  /// Time to wait after a beep before resuming the microphone.
  static const Duration _beepTailDelay = Duration(milliseconds: 450);

  bool _countdownListenPaused = false;

  String _l10n(String key, [Map<String, Object?> params = const {}]) =>
      AppSettingsService.instance.localized(key, params);

  final _speech = SpeechToText();
  final _alertService = EmergencyAlertService();
  final _emergencyAI = EmergencyAIService();
  StreamSubscription<EmergencyAlertEntity?>? _activeAlertSub;

  bool _listening = false;
  bool _sosActive = false;
  bool _submitting = false;
  bool _countdownCancelled = false;
  bool _countdownRunning = false;
  int? _countdownSeconds;
  int _countdownGeneration = 0;
  bool _checkingActiveAlert = true;
  bool _pageInitialized = false;
  bool _speechReady = false;
  EmergencyAlertEntity? _activeAlert;
  String? _locationLine;

  @override
  void initState() {
    super.initState();
    VoiceAssistantCoordinator.instance.acquireMicLock();
    unawaited(_initializePage());
  }

  @override
  void dispose() {
    _cancelCountdown(notify: false);
    _activeAlertSub?.cancel();
    _speech.stop();
    VoiceAssistantCoordinator.instance.releaseMicLock();
    unawaited(EmergencyAlertSoundService.instance.dispose());
    super.dispose();
  }

  Future<void> _initializePage() async {
    EmergencyAlertEntity? active;
    try {
      active = await _alertService.fetchActiveForCurrentPatient();
    } catch (_) {
      active = null;
    }

    if (!mounted) return;

    if (active != null) {
      _applyActiveAlert(active);
    } else {
      setState(() {
        _activeAlert = null;
        _sosActive = false;
        _locationLine = null;
      });
      if (widget.voiceTriggered) {
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (!mounted) return;
        _startCountdown();
      } else {
        _startCountdown();
      }
    }

    setState(() {
      _checkingActiveAlert = false;
      _pageInitialized = true;
    });

    _activeAlertSub ??= _alertService.watchActiveForCurrentPatient().listen(
      _onActiveAlert,
    );
  }

  void _applyActiveAlert(EmergencyAlertEntity alert) {
    _cancelCountdown();
    _speech.stop();
    setState(() {
      _activeAlert = alert;
      _sosActive = true;
      _locationLine = alert.location;
      _listening = false;
    });
  }

  void _onActiveAlert(EmergencyAlertEntity? alert) {
    if (!mounted || !_pageInitialized) return;

    if (alert != null) {
      _applyActiveAlert(alert);
      return;
    }

    setState(() {
      _activeAlert = null;
      _sosActive = false;
      _locationLine = null;
    });

    if (!_submitting && !_countdownRunning && !_countdownCancelled) {
      _restartListen();
      _startCountdown();
    } else if (!_submitting && !_countdownRunning) {
      _restartListen();
    }
  }

  bool _isCountdownActive(int generation) {
    return mounted &&
        generation == _countdownGeneration &&
        !_countdownCancelled &&
        !_sosActive &&
        !_submitting;
  }

  bool get _isVoiceOnlyEmergencyUi =>
      AppSettingsService.instance.isVoiceConversationEnabled;

  String _countdownIntroKey() => _isVoiceOnlyEmergencyUi
      ? 'sosCountdownIntroVoice'
      : 'sosCountdownIntroTouch';

  String _countdownTickKey() => _isVoiceOnlyEmergencyUi
      ? 'sosCountdownTickVoice'
      : 'sosCountdownTickTouch';

  String _openingMessageKey() => _isVoiceOnlyEmergencyUi
      ? 'sosOpeningMessageVoice'
      : 'sosOpeningMessageTouch';

  String _cancelA11yKey() => _isVoiceOnlyEmergencyUi
      ? 'sosCancelA11yLabelVoice'
      : 'sosCancelA11yLabelTouch';

  bool _matchesCancelPhrase(String text) {
    final normalized = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s\u4e00-\u9fff]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (normalized.isEmpty) return false;
    const phrases = [
      'cancel',
      'stop',
      'abort',
      'never mind',
      'no',
      'batal',
      'henti',
      '取消',
      '不要',
      '停止',
      '撤销',
    ];
    return phrases.any(
      (phrase) => normalized == phrase || normalized.contains(phrase),
    );
  }

  Future<void> _announceCountdownIntro(int generation) async {
    if (!_isCountdownActive(generation)) return;

    final intro = _l10n(_countdownIntroKey());
    await AppSettingsService.instance.speakEmergencyAndAwait(intro);
  }

  Future<void> _pauseCountdownListen() async {
    _countdownListenPaused = true;
    if (_speech.isListening) {
      try {
        await _speech.stop();
      } catch (_) {}
    }
  }

  void _resumeCountdownListen() {
    _countdownListenPaused = false;
  }

  void _stopCountdownVoiceListen() {
    _countdownListenPaused = true;
    unawaited(_speech.stop());
  }

  Future<void> _listenForCountdownCancel(int generation) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));

    while (_isCountdownActive(generation) && mounted) {
      while (_countdownListenPaused &&
          _isCountdownActive(generation) &&
          mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      if (!_isCountdownActive(generation) || !mounted) return;

      final micGranted = await DevicePermissionsService.instance
          .ensureMicrophone();
      final speechGranted = await DevicePermissionsService.instance
          .ensureSpeechRecognition();
      if (!micGranted ||
          !speechGranted ||
          !_isCountdownActive(generation) ||
          !mounted) {
        return;
      }

      if (!_speechReady) {
        _speechReady = await _speech.initialize(
          onError: (error) {
            debugPrint('EmergencySosPage STT error: $error');
          },
        );
        if (!_speechReady) return;
      }

      if (mounted) {
        setState(() => _listening = true);
      }

      var heardCancel = false;

      try {
        await _speech.listen(
          listenFor: const Duration(seconds: 12),
          pauseFor: const Duration(seconds: 5),
          localeId: await _resolveListenLocale(),
          listenOptions: SpeechListenOptions(
            partialResults: true,
            cancelOnError: false,
            listenMode: ListenMode.dictation,
          ),
          onResult: (result) {
            if (_countdownListenPaused) return;
            final words = result.recognizedWords.trim();
            if (words.isEmpty || !_matchesCancelPhrase(words)) return;
            heardCancel = true;
            unawaited(_speech.stop());
          },
        );

        while (_speech.isListening &&
            _isCountdownActive(generation) &&
            !heardCancel &&
            mounted) {
          if (_countdownListenPaused) {
            try {
              await _speech.stop();
            } catch (_) {}
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      } catch (error) {
        debugPrint('EmergencySosPage cancel listen failed: $error');
      }

      if (heardCancel && _countdownRunning) {
        if (mounted) setState(() => _listening = false);
        await _onCancelCountdown();
        return;
      }

      if (!_isCountdownActive(generation) || !mounted) {
        if (mounted) setState(() => _listening = false);
        return;
      }

      await Future<void>.delayed(const Duration(milliseconds: 80));
    }

    if (mounted) setState(() => _listening = false);
  }

  Future<String?> _resolveListenLocale() async {
    final lang = AppSettingsService.instance.settings.languageCode;
    final preferred = switch (lang) {
      'ms' => 'ms_MY',
      'zh' => 'zh_CN',
      _ => 'en_US',
    };
    final locales = await _speech.locales();
    if (locales.any((locale) => locale.localeId == preferred)) {
      return preferred;
    }
    return locales.isNotEmpty ? locales.first.localeId : null;
  }

  Future<void> _speakToUser(String message) async {
    if (!mounted || message.trim().isEmpty) return;

    await AppSettingsService.instance.stopSpeaking();
    await AppSettingsService.instance.speakEmergencyAndAwait(message);
  }

  void _announceToUser(String message) {
    unawaited(_speakToUser(message));
  }

  Future<void> _playCountdownTick(int generation, int seconds) async {
    if (!_isCountdownActive(generation)) return;

    setState(() => _countdownSeconds = seconds);
    await WidgetsBinding.instance.endOfFrame;

    await _pauseCountdownListen();
    await EmergencyAlertSoundService.instance.playCountdownAlert(soft: true);
    await Future<void>.delayed(_beepTailDelay);
    _resumeCountdownListen();
  }

  void _startCountdown() {
    if (_checkingActiveAlert ||
        _sosActive ||
        _submitting ||
        _countdownCancelled ||
        _countdownRunning) {
      return;
    }

    unawaited(AppSettingsService.instance.stopSpeaking());
    final generation = ++_countdownGeneration;
    unawaited(_runCountdownLoop(generation));
  }

  /// Duration of the voice-cancel window after the intro speech.
  static const int _cancelWindowSeconds = 5;

  Future<void> _runCountdownLoop(int generation) async {
    if (!_isCountdownActive(generation)) return;

    setState(() {
      _listening = false;
      _countdownRunning = true;
      _countdownSeconds = null;
      _countdownListenPaused = false;
    });

    await EmergencyAlertSoundService.instance.prepare();

    // ── Phase 1: Speak warning, then listen for "cancel" for 5 seconds ──
    await _announceCountdownIntro(generation);
    if (!_isCountdownActive(generation)) return;

    // Listen for 5 seconds — if user says "cancel", abort the alert
    final cancelled = await _listenForCancelWindow(generation);
    if (!_isCountdownActive(generation)) return;

    if (cancelled) {
      await _onCancelCountdown();
      return;
    }

    // ── Phase 2: Loud beeping countdown 5→1, then send alert ──
    for (var seconds = _countdownStart; seconds >= 1; seconds--) {
      if (!_isCountdownActive(generation)) return;

      // Loud beep (soft: false) + show number
      setState(() => _countdownSeconds = seconds);
      await WidgetsBinding.instance.endOfFrame;

      await EmergencyAlertSoundService.instance.playCountdownAlert(soft: false);
      if (!_isCountdownActive(generation)) return;

      // Wait 1 second per tick
      await Future<void>.delayed(const Duration(seconds: 1));
    }

    setState(() {
      _countdownSeconds = null;
      _countdownRunning = false;
    });
    await _triggerSos(announceSent: true);
  }

  /// Listens for [_cancelWindowSeconds] seconds. Returns true if "cancel" was heard.
  Future<bool> _listenForCancelWindow(int generation) async {
    if (!_isCountdownActive(generation) || !mounted) return false;

    final micGranted = await DevicePermissionsService.instance
        .ensureMicrophone();
    final speechGranted = await DevicePermissionsService.instance
        .ensureSpeechRecognition();
    if (!micGranted || !speechGranted || !_isCountdownActive(generation)) {
      return false;
    }

    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onError: (error) {
          debugPrint('EmergencySosPage STT error: $error');
        },
      );
      if (!_speechReady) return false;
    }

    if (mounted) setState(() => _listening = true);

    var heardCancel = false;

    try {
      await _speech.listen(
        listenFor: Duration(seconds: _cancelWindowSeconds + 2),
        pauseFor: Duration(seconds: _cancelWindowSeconds + 1),
        localeId: await _resolveListenLocale(),
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
        ),
        onResult: (result) {
          final words = result.recognizedWords.trim();
          if (words.isEmpty) return;
          if (_matchesCancelPhrase(words)) {
            heardCancel = true;
            unawaited(_speech.stop());
          }
        },
      );

      // Wait for the cancel window duration or until cancel is heard
      final deadline = DateTime.now().add(
        Duration(seconds: _cancelWindowSeconds),
      );
      while (DateTime.now().isBefore(deadline) &&
          !heardCancel &&
          _isCountdownActive(generation) &&
          mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      // Stop listening regardless
      try {
        await _speech.stop();
      } catch (_) {}
    } catch (error) {
      debugPrint('EmergencySosPage cancel window listen failed: $error');
    }

    if (mounted) setState(() => _listening = false);
    return heardCancel;
  }

  void _cancelCountdown({bool notify = true}) {
    _countdownGeneration++;
    _countdownRunning = false;
    _countdownListenPaused = false;
    _stopCountdownVoiceListen();
    unawaited(AppSettingsService.instance.stopSpeaking());
    unawaited(EmergencyAlertSoundService.instance.stop());
    if (!notify || !mounted) return;
    if (_countdownSeconds != null) {
      setState(() => _countdownSeconds = null);
    } else {
      setState(() {});
    }
  }

  Future<void> _onCancelCountdown() async {
    if (!_countdownRunning) return;
    _countdownCancelled = true;
    _cancelCountdown();
    unawaited(_speech.stop());
    if (!mounted) return;
    // Announce cancellation to the user via voice
    await _speakToUser(_l10n('sosCountdownStopped'));
    if (!mounted) return;
    Navigator.of(context).pop();
    unawaited(VoiceAssistantCoordinator.instance.promptMainMenuAfterReturn());
  }

  void _handleCancelAttempt() {
    if (!_countdownRunning) return;
    unawaited(_onCancelCountdown());
  }

  Future<void> _startVoiceListen() async {
    if (_sosActive || _countdownRunning) return;
    final micGranted = await DevicePermissionsService.instance
        .ensureMicrophone();
    if (!micGranted || !mounted) return;
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' &&
            mounted &&
            !_sosActive &&
            !_submitting &&
            _countdownRunning == false) {
          _restartListen();
        }
      },
    );
    if (!available || !mounted || _sosActive || _countdownRunning) {
      return;
    }
    await _listenForHelpPhrase();
  }

  Future<void> _restartListen() async {
    if (!mounted ||
        _sosActive ||
        _submitting ||
        _countdownRunning ||
        _countdownCancelled) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted || _sosActive || _countdownRunning) return;
    await _listenForHelpPhrase();
  }

  Future<void> _listenForHelpPhrase() async {
    if (!mounted ||
        _sosActive ||
        _submitting ||
        _countdownRunning ||
        _countdownCancelled) {
      return;
    }

    setState(() => _listening = true);

    await _speech.listen(
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(partialResults: false),
      onResult: (result) async {
        if (!result.finalResult) return;

        final words = result.recognizedWords.trim();

        if (words.isEmpty) return;

        print("User said: $words");

        try {
          final prediction = await _emergencyAI.classify(words);

          print("AI Prediction: $prediction");

          if (prediction == "EMERGENCY") {
            _cancelCountdown();
            _countdownCancelled = true;

            await _triggerSos(fromVoice: true);
          } else {
            _cancelCountdown();

            setState(() {
              _countdownCancelled = true;
            });

            _announceToUser(_l10n('sosEmergencyVoiceCancelled'));

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_l10n('sosEmergencyCancelledSnackbar'))),
            );
          }
        } catch (e) {
          print(e);
        }
      },
    );
  }

  Future<void> _triggerSos({
    bool fromVoice = false,
    bool announceSent = false,
  }) async {
    if (_sosActive || _submitting) return;
    _cancelCountdown();
    await _speech.stop();
    if (!mounted) return;

    setState(() {
      _submitting = true;
      _listening = false;
    });

    try {
      final alert = await _alertService.triggerSos(
        alertType: EmergencyAlertEntity.alertTypeManualSos,
      );
      if (!mounted) return;
      setState(() {
        _activeAlert = alert;
        _sosActive = true;
        _locationLine = alert.location;
      });

      if (announceSent || fromVoice) {
        // Wait for the announcement to finish before navigating back
        await AppSettingsService.instance.speakEmergencyAndAwait(
          _l10n('sosAlertSentVoice'),
        );
      }

      if (!mounted) return;

      // Navigate back to main menu after alert is sent
      Navigator.of(context).pop();
      unawaited(VoiceAssistantCoordinator.instance.promptMainMenuAfterReturn());
    } catch (e) {
      if (!mounted) return;
      _announceToUser(_l10n('couldNotSendEmergencyAlert', {'error': '$e'}));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_l10n('couldNotSendEmergencyAlert', {'error': '$e'})),
        ),
      );
      _countdownCancelled = false;
      _restartListen();
      _startCountdown();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  String get _instructionText {
    if (_sosActive) {
      if (_activeAlert?.status == EmergencyAlertEntity.statusResponded) {
        return _l10n('sosStaffResponding');
      }
      return _l10n('sosStaffNotified');
    }
    if (_countdownRunning && _countdownSeconds == null) {
      return _l10n(_countdownIntroKey());
    }
    if (_countdownSeconds != null) {
      return _l10n(_countdownTickKey(), {'seconds': '$_countdownSeconds'});
    }
    if (_countdownCancelled) {
      return _l10n('sosCountdownStopped');
    }
    return _l10n(_openingMessageKey());
  }

  String get _sentAccessibilityLabel {
    final id = _activeAlert?.alertId ?? '';
    final location = _locationLine?.trim() ?? '';
    final idPart = id.isNotEmpty ? ' Alert $id.' : '';
    final locationPart = location.isNotEmpty
        ? ' ${_l10n('gpsSharedWithLocation', {'location': location})}'
        : ' ${_l10n('gpsBeingShared')}';
    final statusPart =
        _activeAlert?.status == EmergencyAlertEntity.statusResponded
        ? ' ${_l10n('sosStaffResponding')}'
        : ' ${_l10n('sosStaffNotified')}';
    return _l10n('sosSentA11y', {
      'idPart': idPart,
      'statusPart': statusPart,
      'locationPart': locationPart,
    });
  }

  String get _locationCardText {
    if (_sosActive) {
      final coords = _locationLine?.trim();
      if (coords != null && coords.isNotEmpty) return coords;
      return _l10n('sharingLocationWithStaff');
    }
    return _l10n('gpsWillBeShared');
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingActiveAlert) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          leadingWidth: AppBackButton.appBarLeadingWidth,
          leading: const AppBackButton(),
          title: Text(
            context.l10n.t('emergencySos'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
          ),
          centerTitle: true,
        ),
        body: Center(
          child: AccessibleFocusRegion(
            label: _l10n('sosCheckingStatus'),
            child: CircularProgressIndicator(color: _accent),
          ),
        ),
      );
    }

    final countdownActive = _countdownRunning;
    final showingNumber = _countdownSeconds != null;
    final circleColor = _sosActive ? _sosSentGreen : _sosRed;

    return PopScope(
      canPop: !countdownActive,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: Colors.white,
          elevation: 0,
          automaticallyImplyLeading: false,
          leadingWidth: AppBackButton.appBarLeadingWidth,
          leading: countdownActive
              ? const SizedBox.shrink()
              : const AppBackButton(),
          title: ExcludeSemantics(
            excluding: countdownActive,
            child: Text(
              context.l10n.t('emergencySos'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
            ),
          ),
          centerTitle: true,
          bottom: countdownActive
              ? PreferredSize(
                  preferredSize: Size.fromHeight(
                    _countdownSeconds == null ? 52 : 44,
                  ),
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                      child: Text(
                        _instructionText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.92),
                          fontSize: _countdownSeconds == null ? 15 : 14,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ),
                )
              : null,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const SizedBox(height: 8),
                if (!countdownActive && !_sosActive)
                  AccessibleFocusRegion(
                    label: _instructionText,
                    child: Text(
                      _instructionText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                if (_sosActive && !countdownActive) ...[
                  AccessibleFocusRegion(
                    label: _sentAccessibilityLabel,
                    child: Column(
                      children: [
                        Text(
                          _instructionText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        if (_activeAlert != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _activeAlert!.alertId,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: _accent,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const Spacer(flex: 2),
                ExcludeSemantics(
                  excluding: countdownActive,
                  child: AnimatedScale(
                    scale: countdownActive ? 1.04 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        color: circleColor,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: circleColor.withValues(
                              alpha: countdownActive ? 0.6 : 0.45,
                            ),
                            blurRadius: countdownActive ? 32 : 16,
                            spreadRadius: countdownActive ? 6 : 0,
                          ),
                        ],
                      ),
                      child: _submitting
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (showingNumber) ...[
                                  Text(
                                    '$_countdownSeconds',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 72,
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _l10n('sosSending'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 16,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ] else if (countdownActive &&
                                    !showingNumber) ...[
                                  const Icon(
                                    Icons.notifications_active_outlined,
                                    color: Colors.white,
                                    size: 52,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _l10n('sosLabelSpaced'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 44,
                                      letterSpacing: 2,
                                      height: 1,
                                    ),
                                  ),
                                ] else if (_sosActive) ...[
                                  const Icon(
                                    Icons.check_circle_outline,
                                    color: Colors.white,
                                    size: 52,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _l10n('sosSent'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 26,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ] else ...[
                                  const Icon(
                                    Icons.notifications_active_outlined,
                                    color: Colors.white,
                                    size: 52,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    _l10n('sosLabelSpaced'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 44,
                                      letterSpacing: 2,
                                      height: 1,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ),
                ),
                if (countdownActive) ...[
                  const SizedBox(height: 20),
                  Semantics(
                    button: true,
                    label: _l10n(_cancelA11yKey()),
                    excludeSemantics: true,
                    onTap: _handleCancelAttempt,
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _handleCancelAttempt,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          context.l10n.t('cancel'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                const Spacer(flex: 2),
                ExcludeSemantics(
                  excluding: countdownActive,
                  child: Column(
                    children: [
                      if (!_sosActive) ...[
                        Text(
                          context.l10n.t('locationSharingAuto'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: _gpsCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF333333)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              color: _accent,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _locationCardText,
                                style: const TextStyle(
                                  color: _subtext,
                                  fontSize: 14,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_listening && !_sosActive && !_submitting) ...[
                        const SizedBox(height: 12),
                        Text(
                          countdownActive
                              ? _l10n(_cancelA11yKey())
                              : context.l10n.t('listeningForHelpMe'),
                          style: TextStyle(
                            color: _accent.withValues(alpha: 0.9),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
