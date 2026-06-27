import 'package:flutter/material.dart';

import 'app_route_observer.dart';
import 'l10n/app_localizations.dart';
import 'login_page.dart';
import 'pin_onboarding_page.dart';
import 'register_page.dart';
import 'services/app_settings_service.dart';
import 'services/voice_flow_coordinator.dart';
import 'widgets/accessible_focus_region.dart';

class StartPage extends StatefulWidget {
  const StartPage({super.key});

  static const Color accent = Color(0xFF63C3C4);
  static const Color bg = Color(0xFF000000);
  static const Color subtext = Color(0xFFB0B0B0);

  @override
  State<StartPage> createState() => _StartPageState();
}

class _StartPageState extends State<StartPage> with RouteAware {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (AppSettingsService.instance.isVoiceConversationEnabled) {
        VoiceFlowCoordinator.instance.startWelcomeFlow();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    VoiceFlowCoordinator.instance.cancelWelcomeFlow();
    super.dispose();
  }

  @override
  void didPopNext() {
    if (AppSettingsService.instance.isVoiceConversationEnabled) {
      VoiceFlowCoordinator.instance.startWelcomeFlow();
    }
  }

  @override
  void didPushNext() {
    // Intentionally do not cancel the welcome flow here. 
    // This allows the VoiceFlowCoordinator to guide the user 
    // through the LoginPage and RegisterPage via voice!
  }

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
          settings: const RouteSettings(name: 'LoginPage'),
          builder: (context) => const LoginPage(),
        ),
      );
    }

    void openRegister() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'RegisterPage'),
          builder: (context) => const RegisterPage(),
        ),
      );
    }

    void openPinOnboarding() {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'PinOnboardingPage'),
          builder: (context) => const PinOnboardingPage(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: StartPage.bg,
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
                        color: StartPage.subtext,
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
                    backgroundColor: StartPage.accent,
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
                label: l10n.t('patientOnboardingStartAction'),
                onActivate: openPinOnboarding,
                child: OutlinedButton(
                  onPressed: openPinOnboarding,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: StartPage.accent, width: 1.4),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    l10n.t('patientOnboardingStartAction'),
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
                    side: const BorderSide(color: StartPage.accent, width: 1.4),
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
