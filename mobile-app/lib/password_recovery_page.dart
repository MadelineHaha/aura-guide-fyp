import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'widgets/app_back_button.dart';

class PasswordRecoveryPage extends StatefulWidget {
  const PasswordRecoveryPage({super.key});

  @override
  State<PasswordRecoveryPage> createState() => _PasswordRecoveryPageState();
}

class _PasswordRecoveryPageState extends State<PasswordRecoveryPage> {
  final _newPasswordController = TextEditingController();
  final _repeatPasswordController = TextEditingController();

  int _step = 0;
  bool _submitting = false;

  static const Color _accent = Color(0xFF63C3C4);
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _fieldFill = Color(0xFF141414);
  static const Color _fieldBorder = Color(0xFF3A3A3A);

  String? _validateNewPassword(String password) {
    final l10n = context.l10n;
    if (password.isEmpty) return l10n.t('pleaseEnterNewPassword');
    if (!_hasMinLength(password)) return l10n.t('passwordMustMinLength');
    if (password.length > 255) return l10n.t('passwordMustMaxLength');
    if (!_hasUppercase(password)) return l10n.t('passwordMustUppercase');
    if (!_hasLowercase(password)) return l10n.t('passwordMustLowercase');
    if (!_hasDigit(password)) return l10n.t('passwordMustDigit');
    if (!_hasSpecialChar(password)) return l10n.t('passwordMustSpecial');
    return null;
  }

  bool _hasMinLength(String password) => password.length >= 8;
  bool _hasUppercase(String password) => RegExp(r'[A-Z]').hasMatch(password);
  bool _hasLowercase(String password) => RegExp(r'[a-z]').hasMatch(password);
  bool _hasDigit(String password) => RegExp(r'\d').hasMatch(password);
  bool _hasSpecialChar(String password) =>
      RegExp(r'[!@#$%^&*(),.?":{}|<>_\-\\/\[\];+=~`]').hasMatch(password);

  String? _validateRepeat(String confirm) {
    final l10n = context.l10n;
    if (confirm.isEmpty) return l10n.t('pleaseRepeatPassword');
    if (confirm != _newPasswordController.text) {
      return l10n.t('passwordsDoNotMatch');
    }
    return null;
  }

  void _onContinue() {
    final error = _validateNewPassword(_newPasswordController.text);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() => _step = 1);
  }

  Future<void> _resetPassword() async {
    final error = _validateRepeat(_repeatPasswordController.text);
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    setState(() => _submitting = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    setState(() => _submitting = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('passwordResetSubmitted'))),
    );
    Navigator.of(context).pop();
  }

  void _showVoiceHint(String fieldKey) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('voiceInputForFieldSoon', {'field': fieldKey}))),
    );
  }

  @override
  void dispose() {
    _newPasswordController.dispose();
    _repeatPasswordController.dispose();
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
          l10n.t('passwordRecovery'),
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
              child: _RecoveryProgress(current: _step),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _step == 0 ? _buildStep1() : _buildStep2(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 24),
              child: FilledButton(
                onPressed: _submitting ? null : (_step == 0 ? _onContinue : _resetPassword),
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
                        _step == 0
                            ? l10n.t('continueLabel')
                            : l10n.t('resetPasswordTitle'),
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

  Widget _buildStep1() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          l10n.t('pleaseEnterNewPassword'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _subtext, fontSize: 15, height: 1.35),
        ),
        const SizedBox(height: 32),
        _RecoveryInputField(
          controller: _newPasswordController,
          hintText: l10n.t('newPassword'),
          prefixIcon: Icons.lock_outline,
          obscureText: true,
          onChanged: (_) => setState(() {}),
          onMic: () => _showVoiceHint(l10n.t('newPassword')),
        ),
        const SizedBox(height: 14),
        _PasswordRequirement(
          text: l10n.t('passwordReqMinLength'),
          met: _hasMinLength(_newPasswordController.text),
        ),
        const SizedBox(height: 6),
        _PasswordRequirement(
          text: l10n.t('passwordReqUpperLower'),
          met: _hasUppercase(_newPasswordController.text) &&
              _hasLowercase(_newPasswordController.text),
        ),
        const SizedBox(height: 6),
        _PasswordRequirement(
          text: l10n.t('passwordReqDigit'),
          met: _hasDigit(_newPasswordController.text),
        ),
        const SizedBox(height: 6),
        _PasswordRequirement(
          text: l10n.t('passwordReqSpecial'),
          met: _hasSpecialChar(_newPasswordController.text),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          l10n.t('pleaseEnterNewPasswordAgain'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _subtext, fontSize: 15, height: 1.35),
        ),
        const SizedBox(height: 32),
        _RecoveryInputField(
          controller: _repeatPasswordController,
          hintText: l10n.t('repeatPassword'),
          prefixIcon: Icons.lock_outline,
          obscureText: true,
          onMic: () => _showVoiceHint(l10n.t('repeatPassword')),
        ),
      ],
    );
  }
}

class _RecoveryInputField extends StatelessWidget {
  const _RecoveryInputField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    required this.onMic,
    this.obscureText = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final VoidCallback onMic;
  final bool obscureText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 16),
      decoration: InputDecoration(
        filled: true,
        fillColor: _PasswordRecoveryPageState._fieldFill,
        hintText: hintText,
        hintStyle: const TextStyle(
          color: _PasswordRecoveryPageState._subtext,
          fontSize: 15,
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
            color: _PasswordRecoveryPageState._fieldBorder,
            width: 1.2,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: _PasswordRecoveryPageState._accent,
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

class _RecoveryProgress extends StatelessWidget {
  const _RecoveryProgress({required this.current});

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
            color:
                active ? _PasswordRecoveryPageState._accent : const Color(0xFF4D4D4D),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
