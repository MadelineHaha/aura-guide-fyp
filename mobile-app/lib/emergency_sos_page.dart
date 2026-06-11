import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'models/emergency_alert_entity.dart';
import 'services/device_permissions_service.dart';
import 'services/emergency_alert_service.dart';
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
  static const Color _gpsCard = Color(0xFF1A1A1A);

  final _speech = SpeechToText();
  final _alertService = EmergencyAlertService();
  StreamSubscription<EmergencyAlertEntity?>? _activeAlertSub;

  bool _listening = false;
  bool _sosActive = false;
  bool _holdingSos = false;
  bool _submitting = false;
  EmergencyAlertEntity? _activeAlert;
  String? _locationLine;

  @override
  void initState() {
    super.initState();
    _activeAlertSub =
        _alertService.watchActiveForCurrentPatient().listen(_onActiveAlert);
    _startVoiceListen();
  }

  @override
  void dispose() {
    _activeAlertSub?.cancel();
    _speech.stop();
    super.dispose();
  }

  void _onActiveAlert(EmergencyAlertEntity? alert) {
    if (!mounted) return;
    setState(() {
      _activeAlert = alert;
      _sosActive = alert != null;
      _locationLine = alert?.location;
    });
    if (alert != null) {
      _speech.stop();
      setState(() => _listening = false);
    } else if (!_submitting && !_holdingSos) {
      _restartListen();
    }
  }

  Future<void> _startVoiceListen() async {
    if (_sosActive) return;
    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
    if (!micGranted || !mounted) return;
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' && mounted && !_sosActive && !_submitting) {
          _restartListen();
        }
      },
    );
    if (!available || !mounted || _sosActive) return;
    await _listenForHelpPhrase();
  }

  Future<void> _restartListen() async {
    if (!mounted || _sosActive || _holdingSos || _submitting) return;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted || _sosActive) return;
    await _listenForHelpPhrase();
  }

  Future<void> _listenForHelpPhrase() async {
    if (!mounted || _sosActive || _holdingSos || _submitting) return;
    setState(() => _listening = true);
    await _speech.listen(
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: (result) {
        final words = result.recognizedWords.toLowerCase();
        if (words.contains('help me')) {
          _triggerSos(fromVoice: true);
        }
      },
    );
  }

  Future<void> _triggerSos({bool fromVoice = false}) async {
    if (_sosActive || _submitting) return;
    await _speech.stop();
    if (!mounted) return;

    setState(() {
      _submitting = true;
      _listening = false;
      _holdingSos = false;
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

      final createdNow = alert.alertId;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fromVoice
                ? 'Voice alert $createdNow sent. Location shared with healthcare staff.'
                : 'Emergency alert $createdNow sent. Location shared with healthcare staff.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send emergency alert: $e')),
      );
      _restartListen();
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _onSosHoldStart() {
    if (_sosActive || _submitting) return;
    setState(() => _holdingSos = true);
    _speech.stop();
  }

  void _onSosHoldEnd() {
    if (_holdingSos) {
      _triggerSos();
    }
    setState(() => _holdingSos = false);
  }

  void _onSosHoldCancel() {
    setState(() => _holdingSos = false);
    if (!_sosActive) _restartListen();
  }

  @override
  Widget build(BuildContext context) {
    final gpsText = _sosActive
        ? (_locationLine != null && _locationLine!.isNotEmpty
            ? 'GPS location shared: $_locationLine'
            : 'GPS location is being shared with healthcare staff')
        : 'GPS location will be shared with healthcare staff';

    return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            foregroundColor: Colors.white,
            elevation: 0,
            automaticallyImplyLeading: false,
            leadingWidth: AppBackButton.appBarLeadingWidth,
            leading: const AppBackButton(),
            title: const Text(
              'Emergency SOS',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
            ),
            centerTitle: true,
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  AccessibleFocusRegion(
                    label: _sosActive
                        ? 'Emergency alert is active. Healthcare staff have been notified.'
                        : 'In an emergency, press and hold the SOS button or say Help me',
                    child: Text(
                      _sosActive
                          ? 'Emergency alert is active. Healthcare staff have been notified.'
                          : 'In an emergency, press and hold the SOS button or say \'Help me\'',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (_activeAlert != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Alert ${_activeAlert!.alertId} · ${_activeAlert!.alertType}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _accent, fontSize: 14),
                    ),
                  ],
                  const Spacer(flex: 2),
                  GestureDetector(
                    onLongPressStart: (_) => _onSosHoldStart(),
                    onLongPressEnd: (_) => _onSosHoldEnd(),
                    onLongPressCancel: _onSosHoldCancel,
                    child: AnimatedScale(
                      scale: _holdingSos ? 0.94 : 1.0,
                      duration: const Duration(milliseconds: 120),
                      child: Container(
                        width: 220,
                        height: 220,
                        decoration: BoxDecoration(
                          color: _sosActive ? _sosRed.withValues(alpha: 0.7) : _sosRed,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _sosRed.withValues(alpha: 0.45),
                              blurRadius: _holdingSos ? 28 : 16,
                              spreadRadius: _holdingSos ? 4 : 0,
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
                                  Icon(
                                    Icons.info_outline,
                                    color: Colors.white,
                                    size: _holdingSos ? 52 : 48,
                                  ),
                                  const SizedBox(height: 14),
                                  const Text(
                                    's o s',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 28,
                                      letterSpacing: 10,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const Spacer(flex: 2),
                  const Text(
                    'Location sharing will be enabled automatically',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
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
                            gpsText,
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
                      'Listening for "Help me"...',
                      style: TextStyle(
                        color: _accent.withValues(alpha: 0.9),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
    );
  }
}
