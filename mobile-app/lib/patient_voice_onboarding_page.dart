import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'models/voice_capture_result.dart';
import 'models/voice_pin_capture_result.dart';
import 'services/patient_onboarding_service.dart';
import 'services/voice_passphrase_controller.dart';
import 'widgets/app_back_button.dart';
import 'widgets/voice_record_button.dart';

class PatientVoiceOnboardingPage extends StatefulWidget {
  const PatientVoiceOnboardingPage({
    super.key,
    required this.userId,
    required this.pin,
    required this.name,
  });

  final String userId;
  final String pin;
  final String name;

  @override
  State<PatientVoiceOnboardingPage> createState() =>
      _PatientVoiceOnboardingPageState();
}

class _PatientVoiceOnboardingPageState extends State<PatientVoiceOnboardingPage> {
  final _onboarding = PatientOnboardingService();
  late final VoicePassphraseController _controller;
  bool _saving = false;
  String? _statusMessage;

  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  void initState() {
    super.initState();
    _controller = VoicePassphraseController(onValidCapture: _activateWithVoice);
  }

  Future<void> _activateWithVoice(VoiceCaptureResult result) async {
    final l10n = context.l10n;
    setState(() {
      _saving = true;
      _statusMessage = l10n.t('voiceLoginChecking');
    });

    try {
      await _onboarding.signInWithSpokenPin(
        pin: widget.pin,
        voiceCapture: VoicePinCaptureResult(
          pin: widget.pin,
          voiceprintVector: result.voiceprintVector,
          voiceFeatures: result.voiceFeatures,
        ),
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _statusMessage = l10n.t('patientOnboardingVoiceComplete');
      });
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      _controller.resetSample();
      setState(() {
        _saving = false;
        _statusMessage = l10n.t('voiceCaptureFailed', {'error': error});
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(patientOnboardingErrorMessage(error))),
      );
    }
  }

  Future<void> _startRecording() async {
    if (_saving || _controller.isRecording) return;
    setState(() => _statusMessage = null);
    final error = await _controller.startRecording();
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = l10n.t('patientOnboardingVoiceTitle');

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: AppBackButton.appBarLeadingWidth,
        leading: const AppBackButton(),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.name.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  l10n.t('patientOnboardingWelcome', {'name': widget.name}),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 36),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.t('patientOnboardingVoicePrompt'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _subtext, fontSize: 15, height: 1.35),
              ),
              const SizedBox(height: 34),
              ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  return VoiceRecordButton(
                    isRecording: _controller.isRecording,
                    hasValidSample: _controller.hasValidSample,
                    heardPreview: _controller.heardPreview,
                    accessibilityMessage: _controller.accessibilityMessage,
                    onActivate: _startRecording,
                    onStop: _controller.stopRecording,
                  );
                },
              ),
              const SizedBox(height: 20),
              if (_saving)
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFF63C3C4)),
                )
              else if (_statusMessage != null)
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _subtext, fontSize: 15),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
