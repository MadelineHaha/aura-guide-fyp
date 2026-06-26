import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app_navigator.dart';
import 'app_route_observer.dart';
import 'auth_session.dart';
import 'firebase_auth_helper.dart';
import 'firebase_options.dart';
import 'l10n/app_localizations.dart';
import 'widgets/role_home_gate.dart';
import 'services/app_settings_service.dart';
import 'services/device_permissions_service.dart';
import 'services/system_accessibility_service.dart';
import 'services/patient_call_session.dart';
import 'start_page.dart';
import 'widgets/patient_experience_host.dart';
import 'widgets/patient_incoming_call_host.dart';
import 'services/emergency_ai_service.dart';
import 'services/voice_assistant_coordinator.dart';
import 'services/app_experience_service.dart';
import 'services/activity_log_service.dart';
import 'services/medication_push_service.dart';
import 'services/medication_local_reminder_service.dart';
import 'services/step_tracking_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemAccessibilityService.instance.ensureAttached();

  await EmergencyAIService().initialize();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await MedicationLocalReminderService.instance.ensureTimezoneReady();

  MedicationPushService.registerBackgroundHandler();

  await configureFirebaseAuth();
  await AppSettingsService.instance.load();
  AppSettingsService.instance.registerNotificationsPreferenceHandler(
    MedicationPushService.instance.onNotificationsPreferenceChanged,
  );
  AppSettingsService.instance.registerAfterSettingsSyncHandler(
    () => MedicationPushService.instance.syncToken(forceSave: true),
  );
  unawaited(ActivityLogService.instance.warmUp());
  await DevicePermissionsService.instance.requestMicAndCameraOnLaunch();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppSettingsService.instance,
      builder: (context, _) {
        final settings = AppSettingsService.instance.settings;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Aura Guide',
          navigatorKey: rootNavigatorKey,
          navigatorObservers: [
            appRouteObserver,
            VoiceAssistantCoordinator.instance.navigatorObserver,
          ],
          locale: Locale(settings.languageCode),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) {
            return PatientExperienceHost(
              child: PatientIncomingCallHost(
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(settings.fontScale),
                  ),
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
          },
          home: const _AuthGate(),
        );
      },
    );
  }
}

/// Keeps the user on Main Menu unless they explicitly log out.
/// Email verify/reload can briefly emit null from authStateChanges.
class _AuthGate extends StatefulWidget {
  const _AuthGate();

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  StreamSubscription<User?>? _authSub;
  User? _user;
  bool _initializing = true;

  Future<void> _bootstrapSignedInUser(User user) async {
    AuthSession.updateSignedInUser(user);
    await AppSettingsService.instance.syncFromFirestore(user.uid);
    unawaited(StepTrackingService.instance.start());
    unawaited(MedicationPushService.instance.start());
  }

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      unawaited(_bootstrapSignedInUser(_user!));
    }
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  Future<void> _onAuthChanged(User? user) async {
    if (!mounted) return;

    if (user != null) {
      await _bootstrapSignedInUser(user);
      if (!mounted) return;
      setState(() {
        _user = user;
        _initializing = false;
      });
      return;
    }

    // Only go to Start Page when user tapped Log Out.
    if (AuthSession.explicitSignOutRequested) {
      AuthSession.clearExplicitSignOut();
      AuthSession.lastKnownUser = null;
      AppExperienceService.instance.clear();
      AppSettingsService.instance.clearCloudSync();
      unawaited(PatientCallSession.instance.disposeOnSignOut());
      unawaited(StepTrackingService.instance.disposeOnSignOut());
      unawaited(MedicationPushService.instance.disposeOnSignOut());
      setState(() {
        _user = null;
        _initializing = false;
      });
      return;
    }

    // Transient null — keep last signed-in user on screen (do not log out).
    if (_user != null) {
      for (var i = 0; i < 6; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final recovered = FirebaseAuth.instance.currentUser;
        if (!mounted) return;
        if (recovered != null) {
          await _bootstrapSignedInUser(recovered);
          if (!mounted) return;
          setState(() => _user = recovered);
          return;
        }
      }
      return;
    }

    setState(() => _initializing = false);
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing && _user == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF63C3C4)),
        ),
      );
    }

    if (_user != null) {
      return RoleHomeGate(uid: _user!.uid);
    }

    return const StartPage();
  }
}
