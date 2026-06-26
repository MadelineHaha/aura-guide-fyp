import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'models/voice_pin_capture_result.dart';
import 'services/patient_onboarding_service.dart';
import 'services/voice_pin_controller.dart';
import 'widgets/app_back_button.dart';
import 'widgets/voice_record_button.dart';

class PinOnboardingPage extends StatefulWidget {
  const PinOnboardingPage({super.key});

  @override
  State<PinOnboardingPage> createState() => _PinOnboardingPageState();
}

class _PinOnboardingPageState extends State<PinOnboardingPage> {
  final _onboarding = PatientOnboardingService();
  late final VoicePinController _pinController;
  bool _submitting = false;
  String? _statusMessage;

  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  void initState() {
    super.initState();
    _pinController = VoicePinController(onValidCapture: _activateWithSpokenPin);
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _activateWithSpokenPin(VoicePinCaptureResult capture) async {
    final l10n = context.l10n;

    setState(() {
      _submitting = true;
      _statusMessage = l10n.t('patientOnboardingPinVerifying');
    });

    try {
      await _onboarding.signInWithSpokenPin(
        pin: capture.pin,
        voiceCapture: capture,
      );
      if (!mounted) return;
      _showMessage(l10n.t('patientOnboardingVoiceComplete'));
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) return;
      _pinController.resetSample();
      final message = patientOnboardingErrorMessage(error);
      setState(() {
        _statusMessage = message;
      });
      _showMessage(message);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _startPinRecording() async {
    if (_submitting || _pinController.isRecording || _pinController.isAnalyzing) {
      return;
    }
    setState(() => _statusMessage = null);
    final error = await _pinController.startRecording();
    if (!mounted) return;
    if (error != null) {
      _showMessage(error);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: AppBackButton.appBarLeadingWidth,
        leading: const AppBackButton(),
        title: Text(
          l10n.t('patientOnboardingTitle'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                l10n.t('patientOnboardingPinVoicePrompt'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.t('patientOnboardingPinVoiceHint'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _subtext, fontSize: 15, height: 1.4),
              ),
              const SizedBox(height: 34),
              ListenableBuilder(
                listenable: _pinController,
                builder: (context, _) {
                  return VoiceRecordButton(
                    isRecording: _pinController.isRecording,
                    isAnalyzing: _pinController.isAnalyzing || _submitting,
                    hasValidSample: _pinController.hasValidSample,
                    prompt: l10n.t('patientOnboardingPinVoiceRecordPrompt'),
                    heardPreview: _pinController.heardPreview.isNotEmpty
                        ? _pinController.heardPreview
                        : null,
                    accessibilityMessage: _pinController.accessibilityMessage,
                    onActivate: _startPinRecording,
                    onStop: _pinController.stopRecording,
                    onRetake: _submitting || _pinController.isAnalyzing
                        ? null
                        : () => _pinController.startRecording(allowOverwrite: true),
                  );
                },
              ),
              const SizedBox(height: 20),
              if (_statusMessage != null &&
                  !_pinController.isRecording &&
                  !_pinController.isAnalyzing &&
                  !_submitting)
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
