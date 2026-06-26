import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'l10n/app_localizations.dart';
import 'firebase_auth_helper.dart';
import 'models/voice_capture_result.dart';
import 'services/field_speech_input.dart';
import 'services/phone_number_service.dart';
import 'services/app_settings_service.dart';
import 'services/user_registration_service.dart';
import 'services/voice_embedding_service.dart';
import 'services/voice_auth_credentials_service.dart';
import 'services/voice_passphrase_controller.dart';
import 'services/voice_profile_service.dart';
import 'widgets/app_back_button.dart';
import 'widgets/listening_mic_button.dart';
import 'widgets/password_field_suffix.dart';
import 'widgets/voice_record_button.dart';
import 'utils/post_auth_navigation.dart';

class VoiceRegisterPage extends StatefulWidget {
  const VoiceRegisterPage({super.key});

  @override
  State<VoiceRegisterPage> createState() => _VoiceRegisterPageState();
}

class _VoiceRegisterPageState extends State<VoiceRegisterPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _voiceProfiles = VoiceProfileService();
  late final VoicePassphraseController _voiceController;
  final _registration = UserRegistrationService();
  final _fieldSpeech = FieldSpeechInput.instance;

  int _step = 0;
  bool _submitting = false;
  bool _isAutoSpeaking = false;

  static const Color _accent = Color(0xFF66C2BD);
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _fieldFill = Color(0xFF141414);
  static const Color _fieldBorder = Color(0xFF3A3A3A);

  static const int _steps = 4;
  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  @override
  void initState() {
    super.initState();
    _voiceController = VoicePassphraseController(
      onValidCapture: _onVoiceCaptured,
    );
    _fieldSpeech.addListener(_onFieldSpeechChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _autoStartVoiceRegistration();
    });
  }

  Future<void> _autoStartVoiceRegistration() async {
    final l10n = context.l10n;
    setState(() => _isAutoSpeaking = true);
    await AppSettingsService.instance.speakAndAwaitCompletion(l10n.t('voiceLoginPrompt'));
    if (!mounted) return;
    setState(() => _isAutoSpeaking = false);
    await _startRecording();
  }

  void _onFieldSpeechChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _dictateTo(
    TextEditingController controller, {
    ListenMode listenMode = ListenMode.dictation,
  }) async {
    final error = await _fieldSpeech.toggleForController(
      controller,
      listenMode: listenMode,
    );
    if (error != null && mounted) {
      _showValidation(error);
    }
  }

  Future<void> _onVoiceCaptured(VoiceCaptureResult result) async {
    await _saveVoiceProfileIfSignedIn(result);
    if (!mounted || _step != 0) return;

    // Give the success message time to finish, then move to the next step.
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!mounted || _step != 0 || !_voiceController.hasValidSample) return;
    setState(() => _step = 1);
  }

  Future<void> _saveVoiceProfileIfSignedIn(VoiceCaptureResult result) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;

    try {
      await _voiceProfiles.saveVoiceProfile(
        uid: uid,
        passphrase: result.phrase,
        voiceprintVector: result.voiceprintVector,
        voiceFeatures: result.voiceFeatures,
      );
    } catch (_) {
      // Profile is still saved when registration completes.
    }
  }

  Future<String> _detectRegistrationPhone() async {
    return await PhoneNumberService.instance.detectSimPhoneNumber() ?? '';
  }

  VoiceCaptureResult? get _captureResult => _voiceController.captureResult;

  String? _validateVoiceCapture(AppLocalizations l10n, VoiceCaptureResult? capture) {
    if (capture == null) {
      return l10n.t('pleaseRecordVoiceSample');
    }
    if (!VoiceEmbeddingService.isUsableVoiceprint(capture.voiceprintVector)) {
      return 'Voice profile was not captured. Please record your voice again.';
    }
    return null;
  }

  Future<void> _persistRegisteredVoiceProfile({
    required String uid,
    required VoiceCaptureResult capture,
  }) async {
    await _voiceProfiles.saveVoiceProfile(
      uid: uid,
      passphrase: capture.phrase,
      voiceprintVector: capture.voiceprintVector,
      voiceFeatures: capture.voiceFeatures,
    );
  }

  Future<void> _retakeVoiceSample() async {
    _voiceController.resetSample();
    await _startRecording();
  }

  Future<void> _startRecording() async {
    if (_voiceController.isRecording || _isAutoSpeaking) {
      if (_isAutoSpeaking) {
        await AppSettingsService.instance.stopSpeaking();
        setState(() => _isAutoSpeaking = false);
      } else {
        return;
      }
    }
    final error = await _voiceController.startRecording(
      allowOverwrite: !_voiceController.hasValidSample,
    );
    if (!mounted) return;
    if (error != null) {
      _showValidation(error);
    }
  }

  void _showValidation(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String? _validateName(String name) {
    if (name.isEmpty) return 'Please enter your name.';
    if (name.length > 100) return 'Name must be at most 100 characters.';
    return null;
  }

  String? _validateEmail(String email) {
    if (email.isEmpty) return 'Please enter your email.';
    if (email.length > 100) return 'Email must be at most 100 characters.';
    if (!_emailRegex.hasMatch(email)) return 'Please enter a valid email format.';
    return null;
  }

  String? _validatePassword(AppLocalizations l10n, String password) {
    if (password.isEmpty) return l10n.t('pleaseEnterPassword');
    if (!_hasMinLength(password)) return 'Password must be at least 8 characters.';
    if (password.length > 255) return 'Password must be at most 255 characters.';
    if (!_hasUppercase(password)) {
      return 'Password must include at least one uppercase letter.';
    }
    if (!_hasLowercase(password)) {
      return 'Password must include at least one lowercase letter.';
    }
    if (!_hasDigit(password)) {
      return 'Password must include at least one number.';
    }
    if (!_hasSpecialChar(password)) {
      return 'Password must include at least one special character.';
    }
    return null;
  }

  bool _hasMinLength(String password) => password.length >= 8;
  bool _hasUppercase(String password) => RegExp(r'[A-Z]').hasMatch(password);
  bool _hasLowercase(String password) => RegExp(r'[a-z]').hasMatch(password);
  bool _hasDigit(String password) => RegExp(r'\d').hasMatch(password);
  bool _hasSpecialChar(String password) =>
      RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\\/\[\];+=~`]').hasMatch(password);

  Future<void> _completeVoiceOnly() async {
    final l10n = context.l10n;
    if (!_voiceController.hasValidSample) {
      _showValidation(l10n.t('pleaseRecordVoiceSample'));
      return;
    }

    final nameError = _validateName(_nameController.text.trim());
    if (nameError != null) {
      _showValidation(nameError);
      return;
    }

    final capture = _captureResult;
    final captureError = _validateVoiceCapture(l10n, capture);
    if (captureError != null) {
      _showValidation(captureError);
      return;
    }

    setState(() => _submitting = true);
    try {
      final account =
          await VoiceAuthCredentialsService.instance.createVoiceOnlyAccount();
      final uid = account.uid;
      final phoneNumber = await _detectRegistrationPhone();

      await _registration.createUserProfile(
        uid: uid,
        name: _nameController.text.trim(),
        birthDate: DateTime(2000, 1, 1),
        email: account.profileEmail,
        voicePassphrase: capture!.phrase,
        voiceprintVector: capture.voiceprintVector,
        voiceFeatures: capture.voiceFeatures,
        phoneNumber: phoneNumber,
        accessibilityPreferences:
            AppSettingsService.instance.settings.toMap(),
      );
      await _persistRegisteredVoiceProfile(uid: uid, capture: capture);

      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('voiceRegistrationCompleted'))),
      );
      returnToRoleHome(context);
    } on FirebaseAuthException catch (e) {
      await _registration.deleteCurrentAuthUser();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() => _submitting = false);
      _showValidation(firebaseAuthErrorMessage(e));
    } catch (e) {
      await _registration.deleteCurrentAuthUser();
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      setState(() => _submitting = false);
      _showValidation(l10n.t('errorWithMessage', {'error': e}));
    }
  }

  Future<void> _submitWithEmailPassword() async {
    final l10n = context.l10n;
    if (!_voiceController.hasValidSample) {
      _showValidation(l10n.t('pleaseRecordVoiceSample'));
      return;
    }

    final nameError = _validateName(_nameController.text.trim());
    if (nameError != null) {
      _showValidation(nameError);
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final emailError = _validateEmail(email);
    if (emailError != null) {
      _showValidation(emailError);
      return;
    }

    final passwordError = _validatePassword(l10n, password);
    if (passwordError != null) {
      _showValidation(passwordError);
      return;
    }

    final capture = _captureResult;
    final captureError = _validateVoiceCapture(l10n, capture);
    if (captureError != null) {
      _showValidation(captureError);
      return;
    }

    setState(() => _submitting = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = cred.user?.uid;
      if (uid == null) throw StateError('No uid returned from Firebase Auth.');

      final phoneNumber = await _detectRegistrationPhone();

      await _registration.createUserProfile(
        uid: uid,
        name: _nameController.text.trim(),
        birthDate: DateTime(2000, 1, 1),
        email: email,
        voicePassphrase: capture!.phrase,
        voiceprintVector: capture.voiceprintVector,
        voiceFeatures: capture.voiceFeatures,
        phoneNumber: phoneNumber,
        accessibilityPreferences:
            AppSettingsService.instance.settings.toMap(),
      );
      await _persistRegisteredVoiceProfile(uid: uid, capture: capture);

      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('voiceRegistrationSetupCompleted'))),
      );
      returnToRoleHome(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showValidation(e.message ?? 'Voice registration failed.');
    } catch (e) {
      await _registration.deleteCurrentAuthUser();
      if (!mounted) return;
      setState(() => _submitting = false);
      _showValidation(l10n.t('voiceCaptureFailed', {'error': e}));
    }
  }

  @override
  void dispose() {
    _fieldSpeech.removeListener(_onFieldSpeechChanged);
    unawaited(_fieldSpeech.stop());
    _voiceController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          l10n.t('createAccount'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
        automaticallyImplyLeading: false,
        leadingWidth: AppBackButton.appBarLeadingWidth,
        leading: AppBackButton(
          onPressed: () {
            if (_step > 0) {
              setState(() => _step -= 1);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              child: _VoiceStepProgress(current: _step, total: _steps),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey<int>(_step),
                    child: _buildStepBody(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: 24,
                top: 8,
                right: 24,
                bottom: 16,
              ),
              child: ListenableBuilder(
                listenable: _voiceController,
                builder: (context, _) => _buildStepButton(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    final l10n = context.l10n;
    switch (_step) {
      case 0:
        return _buildRecordStep(l10n);
      case 1:
        return _buildNameStep(l10n);
      case 2:
        return _buildEmailChoiceStep(l10n);
      case 3:
        return _buildPasswordStep(l10n);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildRecordStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          l10n.t('voiceRegister'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          label:
              'Set up your voice profile to log in hands-free next time.',
          child: const Text(
            'Set up your voice profile to log in hands-free next time.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _subtext, fontSize: 15, height: 1.35),
          ),
        ),
        const SizedBox(height: 34),
        ListenableBuilder(
          listenable: _voiceController,
          builder: (context, _) {
            return VoiceRecordButton(
              isRecording: _voiceController.isRecording,
              hasValidSample: _voiceController.hasValidSample,
              heardPreview: _voiceController.heardPreview,
              accessibilityMessage: _voiceController.accessibilityMessage,
              onActivate: _startRecording,
              onStop: _voiceController.stopRecording,
              onRetake: _retakeVoiceSample,
              accent: _accent,
              subtext: _subtext,
            );
          },
        ),
      ],
    );
  }

  Widget _buildNameStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.t('whatIsYourName'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.t('enterFullNamePrompt'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _subtext, fontSize: 15, height: 1.35),
        ),
        const SizedBox(height: 32),
        _VoiceField(
          controller: _nameController,
          hintText: l10n.t('nameHint'),
          prefixIcon: Icons.person_outline,
          onMic: () => _dictateTo(_nameController),
          micListening: _fieldSpeech.isListeningFor(_nameController),
          keyboardType: TextInputType.name,
          textCapitalization: TextCapitalization.words,
        ),
      ],
    );
  }

  Widget _buildEmailChoiceStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.t('voiceRegister'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.t('addEmailSecurityPrompt'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _subtext, fontSize: 15, height: 1.35),
        ),
        const SizedBox(height: 32),
        _VoiceField(
          controller: _emailController,
          hintText: l10n.t('emailHint'),
          prefixIcon: Icons.mail_outline,
          onMic: () => _dictateTo(
            _emailController,
            listenMode: ListenMode.search,
          ),
          micListening: _fieldSpeech.isListeningFor(_emailController),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _submitting
              ? null
              : () {
                  final emailError =
                      _validateEmail(_emailController.text.trim());
                  if (emailError != null) {
                    _showValidation(emailError);
                    return;
                  }
                  setState(() => _step = 3);
                },
          style: _secondaryButtonStyle(),
          child: Text(
            l10n.t('addEmail'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _submitting ? null : _completeVoiceOnly,
          style: _filledStyle(),
          child: _submitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Text(
                  l10n.t('continueWithVoiceOnly'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPasswordStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.t('voiceRegister'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.t('createStrongPasswordNote'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _subtext, fontSize: 15, height: 1.35),
        ),
        const SizedBox(height: 32),
        _VoiceField(
          controller: _passwordController,
          hintText: l10n.t('createPassword'),
          prefixIcon: Icons.lock_outline,
          onMic: () => _dictateTo(_passwordController),
          micListening: _fieldSpeech.isListeningFor(_passwordController),
          obscureText: true,
          hintFontSize: 20,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 14),
        _PasswordRequirement(
          text: 'At least 8 characters',
          met: _hasMinLength(_passwordController.text),
        ),
        const SizedBox(height: 6),
        _PasswordRequirement(
          text: 'One uppercase and one lowercase letter',
          met: _hasUppercase(_passwordController.text) &&
              _hasLowercase(_passwordController.text),
        ),
        const SizedBox(height: 6),
        _PasswordRequirement(
          text: 'At least one number',
          met: _hasDigit(_passwordController.text),
        ),
        const SizedBox(height: 6),
        _PasswordRequirement(
          text: 'At least one special character',
          met: _hasSpecialChar(_passwordController.text),
        ),
      ],
    );
  }

  Widget _buildStepButton() {
    final l10n = context.l10n;
    if (_step == 0) {
      final canContinue = _voiceController.hasValidSample && !_submitting;
      return FilledButton(
        onPressed: canContinue
            ? () => setState(() => _step = 1)
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      l10n.t('pleaseRecordVoiceSample'),
                      style: const TextStyle(fontSize: 15),
                    ),
                  ),
                );
              },
        style: _filledStyle(),
        child: Text(
          _voiceController.hasValidSample
              ? l10n.t('continueLabel')
              : l10n.t('pleaseRecordVoiceSample'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      );
    }

    if (_step == 1) {
      return FilledButton(
        onPressed: _submitting
            ? null
            : () {
                final nameError = _validateName(_nameController.text.trim());
                if (nameError != null) {
                  _showValidation(nameError);
                  return;
                }
                setState(() => _step = 2);
              },
        style: _filledStyle(),
        child: Text(
          l10n.t('continueLabel'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      );
    }

    if (_step == 2) {
      return const SizedBox.shrink();
    }

    if (_step == 3) {
      return FilledButton(
        onPressed: _submitting ? null : _submitWithEmailPassword,
        style: _filledStyle(),
        child: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : Text(
                l10n.t('continueLabel'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
      );
    }

    return const SizedBox.shrink();
  }

  ButtonStyle _filledStyle() => FilledButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );

  ButtonStyle _secondaryButtonStyle() => FilledButton.styleFrom(
        backgroundColor: const Color(0xFF575C5F),
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );
}

class _VoiceField extends StatefulWidget {
  const _VoiceField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    required this.onMic,
    this.micListening = false,
    this.obscureText = false,
    this.keyboardType,
    this.hintFontSize = 16,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final VoidCallback onMic;
  final bool micListening;
  final bool obscureText;
  final TextInputType? keyboardType;
  final double hintFontSize;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;

  @override
  State<_VoiceField> createState() => _VoiceFieldState();
}

class _VoiceFieldState extends State<_VoiceField> {
  var _obscured = true;

  @override
  Widget build(BuildContext context) {
    final isPassword = widget.obscureText;

    return TextField(
      controller: widget.controller,
      obscureText: isPassword ? _obscured : false,
      keyboardType: widget.keyboardType,
      textCapitalization: widget.textCapitalization,
      onChanged: widget.onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        filled: true,
        fillColor: _VoiceRegisterPageState._fieldFill,
        hintText: widget.hintText,
        hintStyle: TextStyle(
          color: _VoiceRegisterPageState._subtext,
          fontSize: widget.hintFontSize,
        ),
        prefixIcon: Icon(widget.prefixIcon, color: Colors.white, size: 26),
        suffixIcon: isPassword
            ? PasswordFieldSuffix(
                obscured: _obscured,
                onToggleObscured: () => setState(() => _obscured = !_obscured),
                onMic: widget.onMic,
                micListening: widget.micListening,
              )
            : Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ListeningMicButton(
                  listening: widget.micListening,
                  onPressed: widget.onMic,
                  size: 44,
                ),
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: _VoiceRegisterPageState._fieldBorder,
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: _VoiceRegisterPageState._accent,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class _PasswordRequirement extends StatelessWidget {
  const _PasswordRequirement({
    required this.text,
    required this.met,
  });

  final String text;
  final bool met;

  @override
  Widget build(BuildContext context) {
    const unmetColor = Color(0xFF8F8F8F);
    const metColor = Color(0xFF4CAF6A);

    return Row(
      children: [
        Icon(
          Icons.circle,
          size: 8,
          color: met ? metColor : unmetColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: met ? metColor : unmetColor,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}

class _VoiceStepProgress extends StatelessWidget {
  const _VoiceStepProgress({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (index) {
        final active = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 26 : 6,
          height: 4,
          decoration: BoxDecoration(
            color: active
                ? _VoiceRegisterPageState._accent
                : const Color(0xFF4D4D4D),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
