import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_navigator.dart';
import '../auth_session.dart';
import '../firebase_options.dart';
import '../medications_page.dart';
import 'app_settings_service.dart';
import 'medication_local_reminder_service.dart';
import 'notification_history_service.dart';
import 'user_profile_service.dart';

const _channelId = 'medication_reminders';
const _channelName = 'Medication reminders';

enum PushTokenSyncStatus {
  saved,
  unchanged,
  notificationsDisabled,
  notSignedIn,
  tokenUnavailable,
  saveFailed,
}

class PushTokenSyncResult {
  const PushTokenSyncResult({
    required this.status,
    this.message,
    this.tokenPreview,
  });

  final PushTokenSyncStatus status;
  final String? message;
  final String? tokenPreview;

  bool get isSuccess =>
      status == PushTokenSyncStatus.saved ||
      status == PushTokenSyncStatus.unchanged;
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

/// Registers FCM tokens and shows medication reminder notifications.
class MedicationPushService {
  MedicationPushService._();

  static final MedicationPushService instance = MedicationPushService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Shared plugin for medication local alarms and FCM foreground display.
  FlutterLocalNotificationsPlugin get localNotifications => _localNotifications;

  bool _pendingMedicationsNavigation = false;

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  Timer? _retryTimer;
  bool _listenersReady = false;
  String? _activeUid;

  /// Call from `main()` before `runApp`.
  static void registerBackgroundHandler() {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  Future<void> start() async {
    if (kIsWeb) return;

    final user = AuthSession.resolveUser() ?? FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('MedicationPushService.start skipped: no signed-in user');
      return;
    }

    _activeUid = user.uid;
    await syncToken();
    unawaited(_ensureNotificationListeners());
    unawaited(MedicationLocalReminderService.instance.start());
  }

  /// Manual trigger from Settings or the Notification button on the main menu.
  Future<PushTokenSyncResult> registerForReminders({
    bool enableNotificationsSetting = true,
  }) async {
    if (kIsWeb) {
      return const PushTokenSyncResult(
        status: PushTokenSyncStatus.tokenUnavailable,
        message: 'Push notifications are not supported on web.',
      );
    }

    final user = AuthSession.resolveUser() ?? FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const PushTokenSyncResult(
        status: PushTokenSyncStatus.notSignedIn,
        message: 'Sign in as a patient first.',
      );
    }

    _activeUid = user.uid;

    if (enableNotificationsSetting &&
        !AppSettingsService.instance.settings.notificationsEnabled) {
      await AppSettingsService.instance.setNotificationsEnabled(true);
    }

    final result = await syncToken(forceSave: true);
    unawaited(_ensureNotificationListeners());
    unawaited(MedicationLocalReminderService.instance.start());
    return result;
  }

  /// Sends a test notification on this device (no Cloud Functions required).
  Future<String?> sendTestPush() async {
    return MedicationLocalReminderService.instance.sendTestNotification();
  }

  /// Saves the device FCM token to `users/{authUid}.fcmToken`.
  Future<PushTokenSyncResult> syncToken({bool forceSave = false}) async {
    if (kIsWeb) {
      return const PushTokenSyncResult(
        status: PushTokenSyncStatus.tokenUnavailable,
      );
    }

    final uid = await _waitForUid();
    if (uid == null) {
      debugPrint('MedicationPushService.syncToken skipped: no uid');
      return const PushTokenSyncResult(
        status: PushTokenSyncStatus.notSignedIn,
        message: 'No signed-in user.',
      );
    }
    _activeUid = uid;

    if (!AppSettingsService.instance.settings.notificationsEnabled) {
      debugPrint('MedicationPushService.syncToken skipped: notifications off');
      return const PushTokenSyncResult(
        status: PushTokenSyncStatus.notificationsDisabled,
        message: 'Turn on Notifications in Settings.',
      );
    }

    try {
      await _messaging.setAutoInitEnabled(true);

      try {
        await _requestNotificationPermission();
      } catch (error) {
        debugPrint('MedicationPushService permission request failed: $error');
      }

      // Give Play Services a moment after permission / cold start.
      await Future<void>.delayed(const Duration(milliseconds: 800));

      String? token;
      Object? lastError;
      for (var attempt = 0; attempt < 8; attempt++) {
        try {
          token = await _messaging.getToken();
        } catch (error) {
          lastError = error;
          debugPrint(
            'MedicationPushService.getToken error (attempt ${attempt + 1}): $error',
          );
        }
        if (token != null && token.isNotEmpty) break;
        await Future<void>.delayed(Duration(milliseconds: 600 + attempt * 400));
      }

      if (token == null || token.isEmpty) {
        debugPrint('MedicationPushService: FCM token unavailable on this device');
        _scheduleRetry();
        return PushTokenSyncResult(
          status: PushTokenSyncStatus.tokenUnavailable,
          message: lastError?.toString() ??
              'Could not get FCM token. Use a device with Google Play Services, '
              'then tap Notification on the home screen to retry.',
        );
      }

      final preview = token.length > 12
          ? '${token.substring(0, 8)}…${token.substring(token.length - 4)}'
          : token;

      if (!forceSave) {
        final existing = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final stored = (existing.data()?['fcmToken'] as String?)?.trim();
        if (stored == token) {
          debugPrint('MedicationPushService: token already in Firestore');
          return PushTokenSyncResult(
            status: PushTokenSyncStatus.unchanged,
            tokenPreview: preview,
            message: 'Push token already registered.',
          );
        }
      }

      await _saveToken(uid, token);
      _retryTimer?.cancel();
      _retryTimer = null;

      return PushTokenSyncResult(
        status: PushTokenSyncStatus.saved,
        tokenPreview: preview,
        message: 'Push token saved to Firestore.',
      );
    } catch (error, stack) {
      debugPrint('MedicationPushService.syncToken failed: $error\n$stack');
      _scheduleRetry();
      return PushTokenSyncResult(
        status: PushTokenSyncStatus.saveFailed,
        message: error.toString(),
      );
    }
  }

  Future<void> disposeOnSignOut() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _tokenSub?.cancel();
    _tokenSub = null;
    await _foregroundSub?.cancel();
    _foregroundSub = null;
    await _openedSub?.cancel();
    _openedSub = null;
    _activeUid = null;
    _listenersReady = false;
    await MedicationLocalReminderService.instance.disposeOnSignOut();
  }

  Future<void> onNotificationsPreferenceChanged(bool enabled) async {
    if (kIsWeb) return;

    final uid = _resolveUid();
    if (uid == null) return;
    _activeUid = uid;

    if (enabled) {
      await syncToken(forceSave: true);
      unawaited(_ensureNotificationListeners());
      unawaited(MedicationLocalReminderService.instance.start());
    } else {
      await _clearStoredToken();
      await MedicationLocalReminderService.instance.disposeOnSignOut();
    }
  }

  Future<String?> _waitForUid() async {
    final immediate = _resolveUid();
    if (immediate != null) return immediate;

    try {
      final user = await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(const Duration(seconds: 8));
      return user?.uid;
    } catch (_) {
      return null;
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();
    }

    if (Platform.isIOS) {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint(
        'MedicationPushService FCM auth: ${settings.authorizationStatus.name}',
      );
    }
  }

  /// Ensures local notification channel and FCM listeners are ready.
  Future<void> ensureNotificationsReady() async {
    if (kIsWeb) return;
    await _ensureNotificationListeners();
  }

  Future<void> _ensureNotificationListeners() async {
    if (_listenersReady || kIsWeb) return;

    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localNotifications.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      if (Platform.isAndroid) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                _channelId,
                _channelName,
                description: 'Automatic medication reminders',
                importance: Importance.high,
              ),
            );
      }

      _foregroundSub ??=
          FirebaseMessaging.onMessage.listen(_showForegroundNotification);
      _openedSub ??=
          FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageNavigation);
      _tokenSub ??= _messaging.onTokenRefresh.listen((token) {
        final uid = _resolveUid();
        if (uid != null) unawaited(_saveToken(uid, token));
      });

      final launchDetails =
          await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final payload = launchDetails!.notificationResponse?.payload?.trim();
        if (payload != null && payload.isNotEmpty && payload != 'TEST') {
          openMedicationsFromNotificationTap(payload);
        } else {
          openMedicationsFromNotificationTap();
        }
      }

      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessageNavigation(initialMessage);
      }

      _listenersReady = true;
    } catch (error, stack) {
      debugPrint(
        'MedicationPushService listeners setup failed: $error\n$stack',
      );
    }
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 30), () {
      unawaited(syncToken(forceSave: true));
    });
  }

  Future<void> _saveToken(String uid, String token) async {
    if (!AppSettingsService.instance.settings.notificationsEnabled) return;

    try {
      final profile =
          await UserProfileService().loadProfile(uid, syncAuthFirst: false);
      final patientId = (profile.data['userId'] as String?)?.trim() ??
          (profile.data['patientId'] as String?)?.trim();

      final payload = <String, dynamic>{
        'fcmToken': token,
        'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (patientId != null && patientId.isNotEmpty) {
        payload['userId'] = patientId;
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        payload,
        SetOptions(merge: true),
      );
      debugPrint(
        'MedicationPushService saved fcmToken for $uid (patientId=$patientId)',
      );
    } catch (error, stack) {
      debugPrint('MedicationPushService token save failed: $error\n$stack');
      rethrow;
    }
  }

  Future<void> _clearStoredToken() async {
    final uid = _resolveUid();
    if (uid == null || uid.isEmpty) return;

    try {
      await _messaging.deleteToken();
    } catch (error) {
      debugPrint('MedicationPushService deleteToken failed: $error');
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmToken': FieldValue.delete(),
          'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (error) {
      debugPrint('MedicationPushService token clear failed: $error');
    }
  }

  String? _resolveUid() {
    return _activeUid ??
        AuthSession.resolveUser()?.uid ??
        FirebaseAuth.instance.currentUser?.uid;
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    if (!_isMedicationReminder(message)) return;

    final notification = message.notification;
    final title = notification?.title ?? 'Medication reminder';
    final body = notification?.body ?? message.data['body'] ?? '';

    await _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: 'Automatic medication reminders',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: message.data['reminderId'],
    );
    unawaited(
      NotificationHistoryService.instance.record(
        title: title,
        body: body,
        reminderId: message.data['reminderId'],
      ),
    );
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload?.trim();
    if (payload == null || payload.isEmpty || payload == 'TEST') {
      openMedicationsFromNotificationTap();
      return;
    }
    openMedicationsFromNotificationTap(payload);
  }

  void _handleMessageNavigation(RemoteMessage message) {
    if (!_isMedicationReminder(message)) return;
    final reminderId = message.data['reminderId']?.trim();
    if (reminderId != null && reminderId.isNotEmpty) {
      openMedicationsFromNotificationTap(reminderId);
    } else {
      openMedicationsFromNotificationTap();
    }
  }

  bool _isMedicationReminder(RemoteMessage message) {
    return message.data['type'] == 'medication_reminder';
  }

  /// Opens [MedicationsPage] when the user taps a medication notification.
  void openMedicationsFromNotificationTap([String? reminderId]) {
    void navigate() {
      final navigator = rootNavigatorKey.currentState;
      if (navigator == null) {
        if (!_pendingMedicationsNavigation) {
          _pendingMedicationsNavigation = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _pendingMedicationsNavigation = false;
            openMedicationsFromNotificationTap(reminderId);
          });
        }
        return;
      }

      final route = MaterialPageRoute<void>(
        settings: const RouteSettings(name: 'MedicationsPage'),
        builder: (_) => MedicationsPage(highlightReminderId: reminderId),
      );
      navigator.push(route);
    }

    navigate();
  }
}
