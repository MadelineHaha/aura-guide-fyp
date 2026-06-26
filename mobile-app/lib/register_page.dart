import 'package:flutter/material.dart';
import 'l10n/app_localizations.dart';
import 'manual_register_page.dart';
import 'voice_register_page.dart';
import 'widgets/accessible_focus_region.dart';
import 'widgets/app_back_button.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  static const Color _accent = Color(0xFF63C3C4);
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _cardBorderMuted = Color(0xFF3A3A3A);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final brandingA11y = l10n.t('menuCardA11y', {
      'title': l10n.t('appName'),
      'subtitle': l10n.t('appTagline'),
    });

    void openVoiceRegister() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'VoiceRegisterPage'),
          builder: (context) => const VoiceRegisterPage(),
        ),
      );
    }

    void openManualRegister() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'ManualRegisterPage'),
          builder: (context) => const ManualRegisterPage(),
        ),
      );
    }

    void goToSignIn() => Navigator.of(context).pop();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: AppBackButton.appBarLeadingWidth,
        leading: const AppBackButton(),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              AccessibleFocusRegion(
                label: brandingA11y,
                child: Column(
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/logo.png',
                        height: 112,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      l10n.t('appName'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.t('appTagline'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              AccessibleFocusRegion(
                label: l10n.t('howWouldYouLikeToRegister'),
                child: Text(
                  l10n.t('howWouldYouLikeToRegister'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _VoiceRegisterCard(onTap: openVoiceRegister),
              const SizedBox(height: 16),
              _ManualRegisterCard(onTap: openManualRegister),
              const SizedBox(height: 36),
              AccessibleFocusRegion(
                label: l10n.t('alreadyHaveAccountSignIn'),
                onActivate: goToSignIn,
                child: TextButton(
                  onPressed: goToSignIn,
                  child: Text(
                    l10n.t('alreadyHaveAccountSignIn'),
                    style: const TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceRegisterCard extends StatelessWidget {
  const _VoiceRegisterCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AccessibleFocusRegion(
      label: l10n.t('menuCardA11y', {
        'title': l10n.t('voiceRegister'),
        'subtitle': l10n.t('voiceLoginPrompt'),
      }),
      onActivate: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: RegisterPage._accent, width: 1.5),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 20),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: RegisterPage._accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mic,
                      color: Colors.black,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.t('voiceRegister'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.t('voiceLoginPrompt'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: RegisterPage._subtext,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ManualRegisterCard extends StatelessWidget {
  const _ManualRegisterCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AccessibleFocusRegion(
      label: l10n.t('menuCardA11y', {
        'title': l10n.t('manualRegister'),
        'subtitle': l10n.t('enterEmailAndPassword'),
      }),
      onActivate: onTap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: RegisterPage._cardBorderMuted, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      color: RegisterPage._accent,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.t('manualRegister'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.t('enterEmailAndPassword'),
                          style: const TextStyle(
                            color: RegisterPage._subtext,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    color: Colors.white,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
