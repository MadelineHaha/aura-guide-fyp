import 'package:firebase_auth/firebase_auth.dart';

/// Tracks whether the user explicitly tapped Log Out and holds the last
/// signed-in user when Auth briefly reports null (e.g. after email verify).
class AuthSession {
  AuthSession._();

  static bool explicitSignOutRequested = false;

  /// Last non-null Firebase user — kept in sync by [_AuthGate].
  static User? lastKnownUser;

  static void markExplicitSignOut() {
    explicitSignOutRequested = true;
    lastKnownUser = null;
  }

  static void clearExplicitSignOut() {
    explicitSignOutRequested = false;
  }

  static void updateSignedInUser(User user) {
    lastKnownUser = user;
    explicitSignOutRequested = false;
  }

  /// Prefer live Auth, then cached user from the auth gate.
  static User? resolveUser() {
    return FirebaseAuth.instance.currentUser ?? lastKnownUser;
  }

  /// Reloads the live Firebase user and refreshes [lastKnownUser] with the
  /// latest email (e.g. after verify-before-update completes).
  static Future<User?> reloadAndResolve({int maxAttempts = 6}) async {
    for (var i = 0; i < maxAttempts; i++) {
      final live = FirebaseAuth.instance.currentUser;
      if (live != null) {
        try {
          // Force token refresh so [User.email] reflects verify-before-update.
          await live.getIdToken(true);
          await live.reload();
        } catch (_) {}
        final refreshed = FirebaseAuth.instance.currentUser;
        if (refreshed != null) {
          updateSignedInUser(refreshed);
          return refreshed;
        }
      }
      if (i < maxAttempts - 1) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
    }
    return resolveUser();
  }
}
