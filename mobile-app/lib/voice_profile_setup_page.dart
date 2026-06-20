import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'auth_session.dart';
import 'models/voice_capture_result.dart';
import 'services/voice_passphrase_controller.dart';
import 'services/voice_profile_service.dart';
import 'widgets/app_back_button.dart';
import 'widgets/voice_record_button.dart';

/// Lets a signed-in user record and save a voice profile to Firestore.
class VoiceProfileSetupPage extends StatefulWidget {
  const VoiceProfileSetupPage({super.key});

  @override
  State<VoiceProfileSetupPage> createState() => _VoiceProfileSetupPageState();
}

class _VoiceProfileSetupPageState extends State<VoiceProfileSetupPage> {
  final _voiceProfiles = VoiceProfileService();
  late final VoicePassphraseController _controller;
  bool _saving = false;
  String? _statusMessage;

  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  void initState() {
    super.initState();
    _controller = VoicePassphraseController(onValidCapture: _saveVoiceProfile);
  }

  Future<void> _saveVoiceProfile(VoiceCaptureResult result) async {
    final l10n = context.l10n;
    final uid = AuthSession.resolveUser()?.uid ??
        FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      if (!mounted) return;
      setState(() => _statusMessage =
          'You must be signed in to save a voice profile.');
      return;
    }

    setState(() {
      _saving = true;
      _statusMessage = l10n.t('voiceLoginChecking');
    });

    try {
      await _voiceProfiles.saveVoiceProfile(
        uid: uid,
        passphrase: result.phrase,
        voiceprintVector: result.voiceprintVector,
        voiceFeatures: result.voiceFeatures,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _statusMessage = l10n.t('voiceRegistrationSetupCompleted');
      });
    } catch (e) {
      if (!mounted) return;
      _controller.resetSample();
      setState(() {
        _saving = false;
        _statusMessage = l10n.t('voiceCaptureFailed', {'error': e});
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('couldNotSaveProfile', {'error': e}))),
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
    const instructions =
        'Double tap the button below and say Sign me in. Your voice profile will be saved to your account.';

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
          l10n.t('voiceLogin'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 36),
              Semantics(
                header: true,
                label: l10n.t('voiceLogin'),
                child: Text(
                  l10n.t('voiceLogin'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: instructions,
                child: Text(
                  instructions,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _subtext, fontSize: 15, height: 1.35),
                ),
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
                  );
                },
              ),
              const SizedBox(height: 20),
              if (_saving)
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFF63C3C4)),
                )
              else if (_statusMessage != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _statusMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _subtext, fontSize: 15),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
