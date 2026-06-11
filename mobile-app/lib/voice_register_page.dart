import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'firebase_auth_helper.dart';
import 'main_menu_page.dart';
import 'models/voice_capture_result.dart';
import 'services/phone_number_service.dart';
import 'services/user_registration_service.dart';
import 'services/voice_auth_credentials_service.dart';
import 'services/voice_passphrase_controller.dart';
import 'services/voice_profile_service.dart';
import 'widgets/app_back_button.dart';
import 'widgets/voice_record_button.dart';

class VoiceRegisterPage extends StatefulWidget {
  const VoiceRegisterPage({super.key});

  @override
  State<VoiceRegisterPage> createState() => _VoiceRegisterPageState();
}

class _VoiceRegisterPageState extends State<VoiceRegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _voiceProfiles = VoiceProfileService();
  late final VoicePassphraseController _voiceController;
  final _registration = UserRegistrationService();

  int _step = 0;
  bool _submitting = false;

  static const Color _accent = Color(0xFF66C2BD);
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _fieldFill = Color(0xFF141414);
  static const Color _fieldBorder = Color(0xFF3A3A3A);

  static const int _steps = 3;
  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  @override
  void initState() {
    super.initState();
    _voiceController = VoicePassphraseController(
      onValidCapture: _onVoiceCaptured,
    );
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

  Future<void> _retakeVoiceSample() async {
    _voiceController.resetSample();
    await _startRecording();
  }

  Future<void> _startRecording() async {
    if (_voiceController.isRecording) return;
    final error = await _voiceController.startRecording(
      allowOverwrite: !_voiceController.hasValidSample,
    );
    if (!mounted) return;
    if (error != null) {
      _showValidation(error);
    }
  }

  void _showVoiceHint(String field) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Voice input for $field will be available soon.')),
    );
  }

  void _showValidation(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String? _validateEmail(String email) {
    if (email.isEmpty) return 'Please enter your email.';
    if (email.length > 100) return 'Email must be at most 100 characters.';
    if (!_emailRegex.hasMatch(email)) return 'Please enter a valid email format.';
    return null;
  }

  String? _validatePassword(String password) {
    if (password.isEmpty) return 'Please enter a password.';
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
    if (!_voiceController.hasValidSample) {
      _showValidation('Please record your voice sample first.');
      return;
    }

    final capture = _captureResult;
    if (capture == null) {
      _showValidation('Please record your voice sample first.');
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
        name: 'Voice User',
        birthDate: DateTime(2000, 1, 1),
        email: account.profileEmail,
        voicePassphrase: capture.phrase,
        voiceprintVector: capture.voiceprintVector,
        voiceFeatures: capture.voiceFeatures,
        phoneNumber: phoneNumber,
      );

      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice registration completed.')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (context) => const MainMenuPage()),
        (route) => false,
      );
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
      _showValidation('Could not complete voice registration: $e');
    }
  }

  Future<void> _submitWithEmailPassword() async {
    if (!_voiceController.hasValidSample) {
      _showValidation('Please record your voice sample first.');
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final emailError = _validateEmail(email);
    if (emailError != null) {
      _showValidation(emailError);
      return;
    }

    final passwordError = _validatePassword(password);
    if (passwordError != null) {
      _showValidation(passwordError);
      return;
    }

    final capture = _captureResult;
    if (capture == null) {
      _showValidation('Please record your voice sample first.');
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
        name: 'Voice User',
        birthDate: DateTime(2000, 1, 1),
        email: email,
        voicePassphrase: capture.phrase,
        voiceprintVector: capture.voiceprintVector,
        voiceFeatures: capture.voiceFeatures,
        phoneNumber: phoneNumber,
      );

      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice registration setup completed.')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (context) => const MainMenuPage()),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showValidation(e.message ?? 'Voice registration failed.');
    } catch (e) {
      await _registration.deleteCurrentAuthUser();
      if (!mounted) return;
      setState(() => _submitting = false);
      _showValidation('Could not save voice profile: $e');
    }
  }

  @override
  void dispose() {
    _voiceController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Create Account',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
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
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              child: _VoiceStepProgress(current: _step, total: _steps),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildStepBody(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _step == 0 ? 16 : 24,
            8,
            _step == 0 ? 16 : 24,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ListenableBuilder(
            listenable: _voiceController,
            builder: (context, _) => _buildStepButton(),
          ),
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return _buildRecordStep();
      case 1:
        return _buildEmailChoiceStep();
      case 2:
        return _buildPasswordStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildRecordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          'Voice Register',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Set up your voice profile to log in hands-free next time.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _subtext, fontSize: 15, height: 1.35),
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
              onRetake: _retakeVoiceSample,
              accent: _accent,
              subtext: _subtext,
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmailChoiceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Voice Register',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Would you like to add an email and password for extra security?',
          textAlign: TextAlign.center,
          style: TextStyle(color: _subtext, fontSize: 15, height: 1.35),
        ),
        const SizedBox(height: 32),
        _VoiceField(
          controller: _emailController,
          hintText: 'name@example.com',
          prefixIcon: Icons.mail_outline,
          onMic: () => _showVoiceHint('email'),
          keyboardType: TextInputType.emailAddress,
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Voice Register',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Create a strong password for your health data.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _subtext, fontSize: 15, height: 1.35),
        ),
        const SizedBox(height: 32),
        _VoiceField(
          controller: _passwordController,
          hintText: 'Create password',
          prefixIcon: Icons.lock_outline,
          onMic: () => _showVoiceHint('password'),
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
    if (_step == 0) {
      final canContinue = _voiceController.hasValidSample && !_submitting;
      return FilledButton(
        onPressed: canContinue
            ? () => setState(() => _step = 1)
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Please record your voice sample first.',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                );
              },
        style: _filledStyle(),
        child: Text(
          _voiceController.hasValidSample ? 'Continue' : 'Record voice first',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      );
    }

    if (_step == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                    setState(() => _step = 2);
                  },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF575C5F),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Add Email',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                : const Text(
                    'Continue with Voice Only',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
          ),
        ],
      );
    }

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
          : const Text(
              'Continue',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
    );
  }

  ButtonStyle _filledStyle() => FilledButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );
}

class _VoiceField extends StatelessWidget {
  const _VoiceField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    required this.onMic,
    this.obscureText = false,
    this.keyboardType,
    this.hintFontSize = 16,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final VoidCallback onMic;
  final bool obscureText;
  final TextInputType? keyboardType;
  final double hintFontSize;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        filled: true,
        fillColor: _VoiceRegisterPageState._fieldFill,
        hintText: hintText,
        hintStyle: TextStyle(
          color: _VoiceRegisterPageState._subtext,
          fontSize: hintFontSize,
        ),
        prefixIcon: Icon(prefixIcon, color: Colors.white, size: 26),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Material(
            color: const Color(0xFF1D7278),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onMic,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.mic, color: Colors.white, size: 20),
              ),
            ),
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
