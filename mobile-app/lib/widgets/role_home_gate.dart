import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth_session.dart';
import '../caregiver/caregiver_shell_page.dart';
import '../doctor/doctor_shell_page.dart';
import '../main_menu_page.dart';
import '../services/app_experience_service.dart';
import '../services/role_resolution_service.dart';
import '../start_page.dart';
import '../therapist/therapist_shell_page.dart';
import '../theme/app_colors.dart';
import '../voice_profile_setup_page.dart';

class RoleHomeGate extends StatelessWidget {
  const RoleHomeGate({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final resolver = RoleResolutionService();
    return StreamBuilder<AccountResolution>(
      stream: resolver.watchAccount(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorScreen(error: snapshot.error);
        }
        if (!snapshot.hasData) {
          return _loadingScreen();
        }

        final resolution = snapshot.data!;
        _applyExperienceForResolution(resolution);
        switch (resolution.kind) {
          case AccountResolutionKind.onboardingPending:
            final name = resolution.profile['name']?.toString() ?? '';
            return VoiceProfileSetupPage(
              completeOnboarding: true,
              welcomeName: name,
            );
          case AccountResolutionKind.inactive:
          case AccountResolutionKind.notFound:
            return _AccessDeniedScreen(message: resolution.message ?? 'Access denied.');
          case AccountResolutionKind.resolved:
            return _homeForRole(resolution.role ?? MobileAppRole.patient);
        }
      },
    );
  }

  void _applyExperienceForResolution(AccountResolution resolution) {
    final isPatient = resolution.kind == AccountResolutionKind.onboardingPending ||
        (resolution.kind == AccountResolutionKind.resolved &&
            resolution.role == MobileAppRole.patient);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppExperienceService.instance.setPatientExperience(isPatient);
    });
  }

  Widget _homeForRole(MobileAppRole role) {
    switch (role) {
      case MobileAppRole.doctor:
        return const DoctorShellPage();
      case MobileAppRole.therapist:
        return const TherapistShellPage();
      case MobileAppRole.caregiver:
        return const CaregiverShellPage();
      case MobileAppRole.admin:
        return const _AdminWebOnlyScreen();
      case MobileAppRole.patient:
      case MobileAppRole.unknown:
        return const MainMenuPage();
    }
  }

  Widget _loadingScreen() {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Error loading profile: $error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ),
    );
  }
}

class _AccessDeniedScreen extends StatelessWidget {
  const _AccessDeniedScreen({required this.message});

  final String message;

  Future<void> _signOut(BuildContext context) async {
    AuthSession.markExplicitSignOut();
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (context) => const StartPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_outline, color: AppColors.accent, size: 48),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _signOut(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Return to sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminWebOnlyScreen extends StatelessWidget {
  const _AdminWebOnlyScreen();

  Future<void> _signOut(BuildContext context) async {
    AuthSession.markExplicitSignOut();
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (context) => const StartPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.admin_panel_settings_outlined,
                  color: AppColors.accent, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Administrator access is available on the web portal.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => _signOut(context),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
