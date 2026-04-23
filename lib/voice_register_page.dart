import 'package:flutter/material.dart';

class VoiceRegisterPage extends StatefulWidget {
  const VoiceRegisterPage({super.key});

  @override
  State<VoiceRegisterPage> createState() => _VoiceRegisterPageState();
}

class _VoiceRegisterPageState extends State<VoiceRegisterPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  int _step = 0;
  bool _isRecording = false;
  bool _hasSample = false;
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

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
      if (!_isRecording) {
        _hasSample = true;
      }
    });
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
    setState(() => _submitting = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice registration completed.')),
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _submitWithEmailPassword() async {
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

    setState(() => _submitting = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Voice registration setup completed.')),
    );
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  void dispose() {
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step > 0) {
              setState(() => _step -= 1);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
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
            Padding(
              padding: EdgeInsets.fromLTRB(
                _step == 0 ? 16 : 24,
                _step == 0 ? 6 : 12,
                _step == 0 ? 16 : 24,
                24,
              ),
              child: _buildStepButton(),
            ),
          ],
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
        GestureDetector(
          onTap: _toggleRecording,
          child: Container(
            width: 112,
            height: 112,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _accent,
            ),
            child: const Icon(
              Icons.mic,
              color: Colors.white,
              size: 48,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          _isRecording ? 'Recording...' : 'Tap to Record',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Please say: "Sign me in"',
          textAlign: TextAlign.center,
          style: TextStyle(color: _subtext, fontSize: 15),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(4, (i) {
            final active = _hasSample || (_isRecording && i < 2);
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: active ? _accent : const Color(0xFF4D4D4D),
                shape: BoxShape.circle,
              ),
            );
          }),
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
      return FilledButton(
        onPressed: _submitting
            ? null
            : () {
                if (!_hasSample) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Please record your voice sample first.',
                        style: TextStyle(fontSize: 15),
                      ),
                    ),
                  );
                  return;
                }
                setState(() => _step = 1);
              },
        style: _filledStyle(),
        child: const Text(
          'Complete Registration',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
