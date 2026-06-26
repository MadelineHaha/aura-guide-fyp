import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'firebase_auth_helper.dart';
import 'services/activity_log_actions.dart';
import 'services/activity_log_service.dart';
import 'services/phone_number_service.dart';
import 'services/app_settings_service.dart';
import 'services/voice_auth_credentials_service.dart';
import 'services/voice_passphrase_controller.dart';
import 'services/voice_profile_service.dart';
import 'widgets/app_back_button.dart';
import 'widgets/voice_record_button.dart';
import 'utils/post_auth_navigation.dart';

class VoiceLoginPage extends StatefulWidget {
  const VoiceLoginPage({super.key});

  @override
  State<VoiceLoginPage> createState() => _VoiceLoginPageState();
}

class _VoiceLoginPageState extends State<VoiceLoginPage> {
  final _controller = VoicePassphraseController();
  final _voiceProfile = VoiceProfileService();

  bool _enteringDashboard = false;
  bool _showPhoneBackup = false;
  bool _isAutoSpeaking = false;
  String? _statusMessage;
  List<Map<String, dynamic>> _phoneBackupCandidates = const [];

  static const Color _bg = Color(0xFF000000);
  static const Color _accent = Color(0xFF63C3C4);
  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onRecordingChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _autoStartVoiceLogin();
    });
  }

  Future<void> _autoStartVoiceLogin() async {
    final l10n = context.l10n;
    setState(() => _isAutoSpeaking = true);
    await AppSettingsService.instance.speakAndAwaitCompletion(l10n.t('voiceLoginPrompt'));
    if (!mounted) return;
    setState(() => _isAutoSpeaking = false);
    await _startRecording();
  }

  void _onRecordingChanged() {
    if (!_controller.hasValidSample || _enteringDashboard) return;
    _attemptVoiceLogin();
  }

  Future<void> _startRecording() async {
    if (_enteringDashboard || _controller.isRecording || _isAutoSpeaking) {
      if (_isAutoSpeaking) {
        // If they managed to tap while speaking, stop the TTS and allow recording
        await AppSettingsService.instance.stopSpeaking();
        setState(() => _isAutoSpeaking = false);
      } else {
        return;
      }
    }

    setState(() {
      _statusMessage = null;
      _showPhoneBackup = false;
      _phoneBackupCandidates = const [];
    });
    final error = await _controller.startRecording();
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  Future<void> _attemptVoiceLogin() async {
    if (_enteringDashboard) return;
    final l10n = context.l10n;

    setState(() {
      _enteringDashboard = true;
      _statusMessage = l10n.t('voiceLoginChecking');
      _showPhoneBackup = false;
    });

    try {
      final verification = await _voiceProfile.verifyVoiceLogin(
        passphrase: _controller.capturedPhrase,
        probeVector: _controller.voiceprintVector,
      );

      if (verification.status == VoiceVerificationStatus.phraseNotFound) {
        if (!mounted) return;
        _controller.resetSample();
        setState(() {
          _enteringDashboard = false;
          _statusMessage = l10n.t('voiceNoMatch');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('voiceNoMatch'))),
        );
        return;
      }

      if (verification.status == VoiceVerificationStatus.voiceMismatch) {
        if (!mounted) return;
        _controller.resetSample();
        setState(() {
          _enteringDashboard = false;
          _showPhoneBackup = true;
          _phoneBackupCandidates = verification.candidates;
          _statusMessage =
              'Your voice does not match the voice profile on this account. '
              'Only the registered owner can sign in with voice.';
        });
        return;
      }

      final matched = verification.profile;
      if (matched == null) {
        throw StateError('Voice verification succeeded without a profile.');
      }

      await _signInWithProfile(matched);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _controller.resetSample();
      setState(() {
        _enteringDashboard = false;
        _statusMessage = firebaseLoginErrorMessage(e);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(firebaseLoginErrorMessage(e))),
      );
    } catch (e) {
      if (!mounted) return;
      _controller.resetSample();
      setState(() {
        _enteringDashboard = false;
        _statusMessage = context.l10n.t('voiceLoginFailed', {'error': e});
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('voiceLoginFailed', {'error': e}))),
      );
    }
  }

  Future<void> _verifyWithPhone() async {
    final l10n = context.l10n;
    setState(() {
      _enteringDashboard = true;
      _statusMessage = l10n.t('voiceLoginChecking');
    });

    try {
      final simPhone = await PhoneNumberService.instance.detectSimPhoneNumber();
      if (simPhone == null || simPhone.isEmpty) {
        if (!mounted) return;
        setState(() {
          _enteringDashboard = false;
          _statusMessage =
              'Could not verify your registered phone number. Allow phone permission and try again.';
        });
        return;
      }

      Map<String, dynamic>? matched;
      for (final candidate in _phoneBackupCandidates) {
        final storedPhone = candidate['phoneNumber']?.toString();
        if (PhoneNumberService.numbersMatch(storedPhone, simPhone)) {
          matched = candidate;
          break;
        }
      }

      matched ??= await _voiceProfile.findProfileByPhone(simPhone);
      if (matched == null) {
        if (!mounted) return;
        setState(() {
          _enteringDashboard = false;
          _statusMessage =
              'This phone number does not match your registered account.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Phone number verification failed.'),
          ),
        );
        return;
      }

      await _signInWithProfile(matched);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _enteringDashboard = false;
        _statusMessage = firebaseLoginErrorMessage(e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enteringDashboard = false;
        _statusMessage = context.l10n.t('voiceLoginFailed', {'error': e});
      });
    }
  }

  Future<void> _signInWithProfile(Map<String, dynamic> matched) async {
    final l10n = context.l10n;
    final matchedUid = (matched['authUid'] as String?)?.trim() ?? '';
    if (matchedUid.isEmpty) {
      throw StateError('Matched profile is missing an account id.');
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != matchedUid) {
      final credentials =
          await VoiceAuthCredentialsService.instance.load(matchedUid);
      if (credentials == null) {
        if (!mounted) return;
        _controller.resetSample();
        setState(() {
          _enteringDashboard = false;
          _showPhoneBackup = false;
          _statusMessage =
              'Account found, but this device cannot sign in automatically. '
              'Use email login instead.';
        });
        return;
      }

      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: credentials.email,
        password: credentials.password,
      );
    }

    unawaited(
      ActivityLogService.instance.log(
        action: ActivityLogActions.login,
        details: 'Successful voice login to mobile app.',
        userName: matched['name']?.toString(),
        userId: matched['userId']?.toString(),
      ),
    );

    if (!mounted) return;
    final name = matched['name']?.toString().trim();
    setState(() {
      _enteringDashboard = false;
      _showPhoneBackup = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.t('voiceVerifiedWelcome', {
          'name': (name != null && name.isNotEmpty)
              ? name
              : l10n.t('userFallback'),
        })),
      ),
    );
    returnToRoleHome(context);
  }

  @override
  void dispose() {
    _controller.removeListener(_onRecordingChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    const instructions =
        'Double tap the button below and say Sign me in. Your voiceprint will be verified.';

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
          l10n.t('loginAccount'),
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
                    onStop: _controller.stopRecording,
                  );
                },
              ),
              const SizedBox(height: 20),
              if (_enteringDashboard)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: CircularProgressIndicator(color: _accent),
                  ),
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
              if (_showPhoneBackup && !_enteringDashboard) ...[
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _verifyWithPhone,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    'Verify with Registered Phone Number',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
