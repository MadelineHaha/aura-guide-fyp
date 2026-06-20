import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'l10n/app_localizations.dart';
import 'widgets/app_back_button.dart';
import 'widgets/listening_mic_button.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_auth_helper.dart';
import 'main_menu_page.dart';
import 'password_recovery_page.dart';
import 'services/field_speech_input.dart';

class ManualLoginPage extends StatefulWidget {
  const ManualLoginPage({super.key});

  @override
  State<ManualLoginPage> createState() => _ManualLoginPageState();
}

class _ManualLoginPageState extends State<ManualLoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fieldSpeech = FieldSpeechInput.instance;
  int _step = 0;
  bool _submitting = false;

  static const Color _accent = Color(0xFF63C3C4);
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _fieldFill = Color(0xFF141414);
  static const Color _fieldBorder = Color(0xFF3A3A3A);

  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );

  @override
  void initState() {
    super.initState();
    _fieldSpeech.addListener(_onFieldSpeechChanged);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  String? _validateEmail(AppLocalizations l10n, String email) {
    if (email.isEmpty) return l10n.t('pleaseEnterRegisteredEmail');
    if (!_emailRegex.hasMatch(email)) {
      return l10n.t('pleaseEnterRegisteredEmail');
    }
    return null;
  }

  String? _validatePassword(AppLocalizations l10n, String password) {
    if (password.isEmpty) return l10n.t('pleaseEnterPassword');
    return null;
  }

  Future<void> _login() async {
    final l10n = context.l10n;
    final passwordError = _validatePassword(l10n, _passwordController.text);
    if (passwordError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(passwordError)));
      return;
    }

    setState(() => _submitting = true);
    try {
      await configureFirebaseAuth();
      final connectivity = await firebaseConnectivityWarning();
      if (connectivity != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(connectivity)));
        return;
      }
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('signedInSuccessfully'))),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (context) => const MainMenuPage(),
        ),
        (route) => false,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(firebaseAuthErrorMessage(e))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('errorWithMessage', {'error': e}))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _onContinue() {
    final l10n = context.l10n;
    final emailError = _validateEmail(l10n, _emailController.text.trim());
    if (emailError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(emailError)));
      return;
    }
    setState(() => _step = 1);
  }

  @override
  void dispose() {
    _fieldSpeech.removeListener(_onFieldSpeechChanged);
    unawaited(_fieldSpeech.stop());
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
          l10n.t('loginAccount'),
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
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              child: _StepProgress(current: _step),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey<int>(_step),
                    child: _step == 0 ? _buildEmailStep(l10n) : _buildPasswordStep(l10n),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
              child: FilledButton(
                onPressed: _submitting ? null : (_step == 0 ? _onContinue : _login),
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
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
                        _step == 0 ? l10n.t('continueLabel') : l10n.t('signIn'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmailStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.t('manualLogin'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.t('pleaseEnterRegisteredEmail'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _subtext, fontSize: 15, height: 1.35),
        ),
        const SizedBox(height: 32),
        _LoginInputField(
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
      ],
    );
  }

  Widget _buildPasswordStep(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.t('manualLogin'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          l10n.t('pleaseEnterPassword'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _subtext, fontSize: 15, height: 1.35),
        ),
        const SizedBox(height: 32),
        _LoginInputField(
          controller: _passwordController,
          hintText: l10n.t('enterPassword'),
          prefixIcon: Icons.lock_outline,
          onMic: () => _dictateTo(_passwordController),
          micListening: _fieldSpeech.isListeningFor(_passwordController),
          obscureText: true,
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const PasswordRecoveryPage(),
                ),
              );
            },
            style: TextButton.styleFrom(
              foregroundColor: _accent,
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              l10n.t('forgotPasswordUseRecovery'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginInputField extends StatelessWidget {
  const _LoginInputField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    required this.onMic,
    this.micListening = false,
    this.keyboardType,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final VoidCallback onMic;
  final bool micListening;
  final TextInputType? keyboardType;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        filled: true,
        fillColor: _ManualLoginPageState._fieldFill,
        hintText: hintText,
        hintStyle: const TextStyle(color: _ManualLoginPageState._subtext, fontSize: 15),
        prefixIcon: Icon(prefixIcon, color: Colors.white, size: 26),
        suffixIcon: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ListeningMicButton(
            listening: micListening,
            onPressed: onMic,
            size: 44,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 4),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: _ManualLoginPageState._fieldBorder,
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: _ManualLoginPageState._accent,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class _StepProgress extends StatelessWidget {
  const _StepProgress({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(2, (index) {
        final active = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 26 : 6,
          height: 4,
          decoration: BoxDecoration(
            color: active
                ? _ManualLoginPageState._accent
                : const Color(0xFF4D4D4D),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
