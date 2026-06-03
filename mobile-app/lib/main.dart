import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app_route_observer.dart';
import 'auth_session.dart';
import 'firebase_auth_helper.dart';
import 'firebase_options.dart';
import 'main_menu_page.dart';
import 'start_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await configureFirebaseAuth();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aura Guide',
      navigatorObservers: [appRouteObserver],
      home: const _AuthGate(),
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

  @override
  void initState() {
    super.initState();
    _user = FirebaseAuth.instance.currentUser;
    if (_user != null) {
      AuthSession.updateSignedInUser(_user!);
    }
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuthChanged);
  }

  Future<void> _onAuthChanged(User? user) async {
    if (!mounted) return;

    if (user != null) {
      AuthSession.updateSignedInUser(user);
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
          AuthSession.updateSignedInUser(recovered);
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
      return const MainMenuPage();
    }

    return const StartPage();
  }
}
