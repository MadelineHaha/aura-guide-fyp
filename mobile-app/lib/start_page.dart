import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'login_page.dart';
import 'register_page.dart';
import 'widgets/accessible_focus_region.dart';

class StartPage extends StatelessWidget {
  const StartPage({super.key});

  static const Color _accent = Color(0xFF63C3C4);
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final brandingA11y = l10n.t('menuCardA11y', {
      'title': l10n.t('appName'),
      'subtitle': l10n.t('appTagline'),
    });

    void openLogin() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => const LoginPage(),
        ),
      );
    }

    void openRegister() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => const RegisterPage(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              AccessibleFocusRegion(
                label: brandingA11y,
                child: Column(
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/logo.png',
                        height: 130,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      l10n.t('appName'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.t('appTagline'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _subtext,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              AccessibleFocusRegion(
                label: l10n.t('signIn'),
                onActivate: openLogin,
                child: FilledButton(
                  onPressed: openLogin,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    l10n.t('signIn'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              AccessibleFocusRegion(
                label: l10n.t('createAccount'),
                onActivate: openRegister,
                child: OutlinedButton(
                  onPressed: openRegister,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: _accent, width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    l10n.t('createAccount'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
