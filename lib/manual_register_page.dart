import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'models/user_entity.dart';
import 'services/user_registration_service.dart';

/// Manual registration: 4-step "Create Account" flow (name, date of birth, email, password).
class ManualRegisterPage extends StatefulWidget {
  const ManualRegisterPage({super.key});

  @override
  State<ManualRegisterPage> createState() => _ManualRegisterPageState();
}

class _ManualRegisterPageState extends State<ManualRegisterPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  /// Selected calendar date of birth (age is derived when needed, not stored separately).
  DateTime? _birthDate;

  final _registration = UserRegistrationService();
  int _step = 0;
  bool _submitting = false;

  static const Color _accent = Color(0xFF66C2BD);
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);

  static const int _totalSteps = 4;

  void _voiceFieldHint(String field) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Voice input for $field will be available soon.')),
    );
  }

  String? _validateStep0() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return 'Please enter your name.';
    if (name.length > 100) return 'Name must be at most 100 characters.';
    return null;
  }

  String? _validateStep1() {
    if (_birthDate == null) return 'Please select your date of birth.';
    final age = UserEntity.computeAge(_birthDate!);
    if (age < 0 || age > 120) return 'Please choose a valid date of birth.';
    return null;
  }

  String? _validateStep2() {
    final email = _emailController.text.trim();
    if (email.isEmpty) return 'Please enter your email.';
    if (email.length > 100) return 'Email must be at most 100 characters.';
    if (!email.contains('@')) return 'Please enter a valid email address.';
    return null;
  }

  String? _validateStep3() {
    final password = _passwordController.text;
    if (password.isEmpty) return 'Please enter a password.';
    if (password.length > 255) return 'Password must be at most 255 characters.';
    return null;
  }

  void _onContinue() {
    FocusScope.of(context).unfocus();
    String? err;
    switch (_step) {
      case 0:
        err = _validateStep0();
        break;
      case 1:
        err = _validateStep1();
        break;
      case 2:
        err = _validateStep2();
        break;
      case 3:
        err = _validateStep3();
        if (err != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(err)),
          );
          return;
        }
        _register();
        return;
      default:
        return;
    }
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    setState(() => _step += 1);
  }

  Future<void> _register() async {
    final err = _validateStep3();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }

    setState(() => _submitting = true);
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      final uid = cred.user?.uid;
      if (uid == null) throw StateError('No user uid after registration.');

      try {
        await _registration.createUserProfile(
          uid: uid,
          name: _nameController.text.trim(),
          birthDate: _birthDate!,
          email: _emailController.text.trim(),
        );
      } catch (e) {
        await _registration.deleteCurrentAuthUser();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save profile: $e')),
        );
        return;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account created')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Registration failed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();
    final first = DateTime(now.year - 120, 1, 1);
    final last = DateTime(now.year, now.month, now.day);
    final initial = _clampDate(
      _birthDate ?? DateTime(now.year - 25, now.month, now.day),
      first,
      last,
    );

    // Custom dialog with bounded height + scroll so the calendar (and year list)
    // lay out correctly; the stock showDatePicker can clip or block scrolling on
    // some devices when heavily themed.
    final picked = await showDialog<DateTime>(
      context: context,
      barrierDismissible: true,
      builder: (context) => _DateOfBirthPickerDialog(
        initialDate: initial,
        firstDate: first,
        lastDate: last,
        accent: _accent,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _birthDate = picked);
    }
  }

  DateTime _clampDate(DateTime d, DateTime min, DateTime max) {
    if (d.isBefore(min)) return min;
    if (d.isAfter(max)) return max;
    return d;
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
          style: TextStyle(fontWeight: FontWeight.bold),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              child: _StepProgress(current: _step, total: _totalSteps),
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
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: _buildContinueButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return _buildNameStep();
      case 1:
        return _buildBirthDateStep();
      case 2:
        return _buildEmailStep();
      case 3:
        return _buildPasswordStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildNameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'What is your name?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Enter your full name so your care team can identify you.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _subtext, fontSize: 15, height: 1.35),
        ),
        const SizedBox(height: 28),
        _DarkLabeledField(
          controller: _nameController,
          hintText: 'e.g. Madeline Ong',
          prefixIcon: Icons.person_outline,
          onMic: () => _voiceFieldHint('name'),
        ),
      ],
    );
  }

  Widget _buildBirthDateStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'What is your date of birth?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'We use this to personalize care; your age updates automatically.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _subtext, fontSize: 15, height: 1.35),
        ),
        const SizedBox(height: 28),
        _BirthDateField(
          birthDate: _birthDate,
          onTap: _pickBirthDate,
          onMic: () => _voiceFieldHint('date of birth'),
        ),
      ],
    );
  }

  Widget _buildEmailStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Your Email',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Used for account security and health notifications.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _subtext, fontSize: 15, height: 1.35),
        ),
        const SizedBox(height: 28),
        _DarkLabeledField(
          controller: _emailController,
          hintText: 'name@example.com',
          prefixIcon: Icons.mail_outline,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          onMic: () => _voiceFieldHint('email'),
        ),
      ],
    );
  }

  Widget _buildPasswordStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Secure Your Account',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Create a strong password for your health data.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _subtext, fontSize: 15, height: 1.35),
        ),
        const SizedBox(height: 28),
        _DarkLabeledField(
          controller: _passwordController,
          hintText: 'Create password',
          prefixIcon: Icons.lock_outline,
          obscureText: true,
          autofillHints: const [AutofillHints.newPassword],
          micBorderOnly: true,
          onMic: () => _voiceFieldHint('password'),
        ),
        const SizedBox(height: 20),
        _PrivacyNotice(
          accent: _accent,
          onPrivacyTap: () {
            showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: const Color(0xFF1E1E1E),
                title: const Text(
                  'Privacy Policy',
                  style: TextStyle(color: Colors.white),
                ),
                content: const Text(
                  'Privacy policy content will appear here.',
                  style: TextStyle(color: _subtext),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildContinueButton() {
    return FilledButton(
      onPressed: _submitting ? null : _onContinue,
      style: FilledButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      child: _submitting
          ? const SizedBox(
              height: 22,
              width: 22,
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
}

/// Dark date picker with explicit bounds + scrollable shell so month grid / year
/// lists are not clipped and can scroll when space is tight.
class _DateOfBirthPickerDialog extends StatefulWidget {
  const _DateOfBirthPickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.accent,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Color accent;

  @override
  State<_DateOfBirthPickerDialog> createState() =>
      _DateOfBirthPickerDialogState();
}

class _DateOfBirthPickerDialogState extends State<_DateOfBirthPickerDialog> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.92;

    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: widget.accent,
        onPrimary: Colors.black,
        surface: const Color(0xFF1E1E1E),
        onSurface: Colors.white,
        surfaceContainerHighest: const Color(0xFF2A2A2A),
      ),
    );

    return Theme(
      data: theme,
      child: Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        clipBehavior: Clip.none,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: maxH,
          ),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: true,
              physics: const ClampingScrollPhysics(),
            ),
            child: SingleChildScrollView(
              primary: true,
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Date of birth',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Fixed height gives [CalendarDatePicker] bounded constraints so its
                    // internal year list / grid can scroll instead of overflowing.
                    SizedBox(
                      height: 360,
                      width: double.infinity,
                      child: CalendarDatePicker(
                        initialDate: _selected,
                        firstDate: widget.firstDate,
                        lastDate: widget.lastDate,
                        onDateChanged: (d) => setState(() => _selected = d),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(_selected),
                          style: FilledButton.styleFrom(
                            backgroundColor: widget.accent,
                            foregroundColor: Colors.black,
                          ),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BirthDateField extends StatelessWidget {
  const _BirthDateField({
    required this.birthDate,
    required this.onTap,
    required this.onMic,
  });

  final DateTime? birthDate;
  final VoidCallback onTap;
  final VoidCallback onMic;

  static const Color _fieldFill = Color(0xFF141414);
  static const Color _fieldBorder = Color(0xFF3A3A3A);
  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final label = birthDate == null
        ? 'Select Date'
        : loc.formatFullDate(birthDate!);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: _fieldFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _fieldBorder, width: 1),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              color: Colors.white70,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: birthDate == null ? _subtext : Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _MicButton(onPressed: onMic, borderOnly: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.current, required this.total});

  final int current;
  final int total;

  static const Color _accent = Color(0xFF66C2BD);
  static const Color _inactive = Color(0xFF444444);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == current;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            width: active ? 44 : 8,
            height: active ? 4 : 8,
            decoration: BoxDecoration(
              color: active ? _accent : _inactive,
              borderRadius: BorderRadius.circular(active ? 2 : 4),
            ),
          ),
        );
      }),
    );
  }
}

class _DarkLabeledField extends StatelessWidget {
  const _DarkLabeledField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    required this.onMic,
    this.keyboardType,
    this.obscureText = false,
    this.autofillHints,
    this.micBorderOnly = false,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final VoidCallback onMic;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Iterable<String>? autofillHints;
  /// Password step: teal ring around mic (per mock).
  final bool micBorderOnly;

  static const Color _accent = Color(0xFF66C2BD);
  static const Color _fieldFill = Color(0xFF141414);
  static const Color _fieldBorder = Color(0xFF3A3A3A);
  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        filled: true,
        fillColor: _fieldFill,
        hintText: hintText,
        hintStyle: const TextStyle(color: _subtext, fontSize: 15),
        prefixIcon: Icon(prefixIcon, color: Colors.white70, size: 22),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 10),
          child: _MicButton(
            onPressed: onMic,
            borderOnly: micBorderOnly,
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minHeight: 48, minWidth: 52),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _fieldBorder, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _accent, width: 1.5),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.onPressed, this.borderOnly = false});

  final VoidCallback onPressed;
  final bool borderOnly;

  static const Color _accent = Color(0xFF66C2BD);

  @override
  Widget build(BuildContext context) {
    if (borderOnly) {
      const inner = Icon(
        Icons.mic,
        size: 20,
        color: Colors.white,
      );

      return Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _accent, width: 1.5),
              color: const Color(0xFF141414),
            ),
            child: inner,
          ),
        ),
      );
    }

    return Material(
      color: _accent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.mic, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice({required this.accent, required this.onPrivacyTap});

  final Color accent;
  final VoidCallback onPrivacyTap;

  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _border = Color(0xFF2D5A3D);
  static const Color _fill = Color(0xFF0A120A);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border, width: 1),
      ),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            color: _subtext,
            fontSize: 13,
            height: 1.45,
          ),
          children: [
            const TextSpan(text: 'By registering, you agree to our '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: onPrivacyTap,
                child: Text(
                  'Privacy Policy',
                  style: TextStyle(
                    color: accent,
                    decoration: TextDecoration.underline,
                    decorationColor: accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const TextSpan(text: ' regarding your sensitive health data.'),
          ],
        ),
      ),
    );
  }
}
