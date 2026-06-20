import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'models/emergency_alert_entity.dart';
import 'services/app_settings_service.dart';
import 'services/device_permissions_service.dart';
import 'services/emergency_alert_service.dart';
import 'services/emergency_alert_sound_service.dart';
import 'services/emergency_ai_service.dart';
import 'l10n/app_localizations.dart';
import 'utils/accessibility_announcement.dart';
import 'widgets/accessible_focus_region.dart';
import 'widgets/app_back_button.dart';


class EmergencySosPage extends StatefulWidget {
  const EmergencySosPage({super.key});

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
  EmergencyAlertEntity? _activeAlert;
  String? _locationLine;
  DateTime? _lastCancelTapAt;

  @override
  void initState() {
    super.initState();
    unawaited(_initializePage());
  }

  @override
  void dispose() {
    _cancelCountdown();
    _activeAlertSub?.cancel();
    _speech.stop();
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
      unawaited(_startVoiceListen());
      _startCountdown();
    }

    setState(() {
      _checkingActiveAlert = false;
      _pageInitialized = true;
    });

    _activeAlertSub ??=
        _alertService.watchActiveForCurrentPatient().listen(_onActiveAlert);
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

  Future<void> _announceCountdownIntro(int generation) async {
    if (!_isCountdownActive(generation)) return;

    await AppSettingsService.instance.stopSpeaking();
    unawaited(AppSettingsService.instance.speak(_l10n('sosCountdownIntro')));
  }

  Future<void> _speakToUser(String message) async {
    if (!mounted || message.trim().isEmpty) return;

    await AppSettingsService.instance.stopSpeaking();
    await AppSettingsService.instance.speakAndAwaitCompletion(message);
  }

  void _announceToUser(String message) {
    unawaited(_speakToUser(message));
  }

  Future<void> _playCountdownTick(int generation, int seconds) async {
    if (!_isCountdownActive(generation)) return;

    setState(() => _countdownSeconds = seconds);
    await WidgetsBinding.instance.endOfFrame;
    await EmergencyAlertSoundService.instance.playCountdownAlert();
  }

  void _startCountdown() {
    if (_checkingActiveAlert ||
        _sosActive ||
        _submitting ||
        _countdownCancelled ||
        _countdownRunning) {
      return;
    }

    _speech.stop();
    unawaited(AppSettingsService.instance.stopSpeaking());
    final generation = ++_countdownGeneration;
    unawaited(_runCountdownLoop(generation));
  }

  Future<void> _runCountdownLoop(int generation) async {
    if (!_isCountdownActive(generation)) return;

    setState(() {
      _listening = false;
      _countdownRunning = true;
      _countdownSeconds = _countdownStart;
    });

    await EmergencyAlertSoundService.instance.prepare();

    unawaited(_announceCountdownIntro(generation));
    if (!_isCountdownActive(generation)) return;

    for (var seconds = _countdownStart; seconds >= 1; seconds--) {
      if (!_isCountdownActive(generation)) return;

      await _playCountdownTick(generation, seconds);
      if (!_isCountdownActive(generation)) return;

      await Future<void>.delayed(const Duration(seconds: 1));
    }

    if (!_isCountdownActive(generation)) return;

    setState(() {
      _countdownSeconds = null;
      _countdownRunning = false;
    });
    await _triggerSos(announceSent: true);
  }

  void _cancelCountdown() {
    _countdownGeneration++;
    _countdownRunning = false;
    unawaited(AppSettingsService.instance.stopSpeaking());
    unawaited(EmergencyAlertSoundService.instance.stop());
    if (_countdownSeconds != null) {
      setState(() => _countdownSeconds = null);
    } else if (mounted) {
      setState(() {});
    }
  }

  void _onCancelCountdown() {
    if (!_countdownRunning) return;
    _countdownCancelled = true;
    _cancelCountdown();
    unawaited(_speech.stop());
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _handleCancelAttempt() {
    if (!_countdownRunning) return;

    final now = DateTime.now();
    if (_lastCancelTapAt != null &&
        now.difference(_lastCancelTapAt!) <= const Duration(milliseconds: 650)) {
      _lastCancelTapAt = null;
      _onCancelCountdown();
      return;
    }

    _lastCancelTapAt = now;
    unawaited(AccessibilityAnnouncement.announce(_l10n('sosCancelTapAgain')));
  }

  Future<void> _startVoiceListen() async {
    if (_sosActive || _countdownRunning) return;
    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
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
      listenOptions: SpeechListenOptions(
        partialResults: false,
      ),
      onResult: (result) async {

        if (!result.finalResult) return;

        final words = result.recognizedWords.trim();

        if (words.isEmpty) return;

        print("User said: $words");

        try {

          final prediction =
          await _emergencyAI.classify(words);

          print("AI Prediction: $prediction");

          if (prediction == "EMERGENCY") {

            _cancelCountdown();
            _countdownCancelled = true;

            await _triggerSos(
              fromVoice: true,
            );

          } else {

            _cancelCountdown();

            setState(() {
              _countdownCancelled = true;
            });

            _announceToUser(_l10n('sosEmergencyVoiceCancelled'));

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(_l10n('sosEmergencyCancelledSnackbar')),
              ),
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
        _announceToUser(_l10n('sosAlertSentVoice'));
      }

      final createdNow = alert.alertId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _l10n('sosSentSnackbar', {'id': createdNow}),
          ),
        ),
      );
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
      return _l10n('sosCountdownIntro');
    }
    if (_countdownSeconds != null) {
      return _l10n('sosCountdownTick', {'seconds': '$_countdownSeconds'});
    }
    if (_countdownCancelled) {
      return _l10n('sosCountdownStopped');
    }
    return _l10n('sosOpeningMessage');
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
                            ] else if (countdownActive && !showingNumber) ...[
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
                  label: _l10n('sosCancelA11yLabel'),
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
              if (_listening && !_sosActive && !_submitting && !countdownActive) ...[
                const SizedBox(height: 12),
                Text(
                  context.l10n.t('listeningForHelpMe'),
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
