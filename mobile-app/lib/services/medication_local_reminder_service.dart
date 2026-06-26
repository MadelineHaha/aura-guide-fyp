import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/medication_item.dart';
import '../auth_session.dart';
import '../models/medication_entity.dart';
import '../models/medication_reminder_entity.dart';
import '../utils/clinic_datetime.dart';
import 'app_settings_service.dart';
import 'medications_service.dart';
import 'medication_push_service.dart';
import 'notification_history_service.dart';
import 'user_profile_service.dart';

const _channelId = 'medication_reminders';
const _channelName = 'Medication reminders';
const _clinicTimezone = 'Asia/Kuala_Lumpur';
const _firedPrefsPrefix = 'med_reminder_fired_';
const _firedAtPrefsPrefix = 'med_reminder_fired_at_';
const _missedPrefsPrefix = 'med_reminder_missed_';
const _scheduleDays = 14;

/// Schedules medication reminders on the device — no Cloud Functions or Blaze plan.
class MedicationLocalReminderService with WidgetsBindingObserver {
  MedicationLocalReminderService._();

  static final MedicationLocalReminderService instance =
      MedicationLocalReminderService._();

  final FlutterLocalNotificationsPlugin _notifications =
      MedicationPushService.instance.localNotifications;

  bool _timezoneReady = false;
  StreamSubscription<List<MedicationItem>>? _watchSub;
  Timer? _resyncTimer;
  Timer? _minuteTimer;
  String? _lastCheckedSlot;

  Map<String, MedicationEntity> _cachedMeds = {};
  List<MedicationReminderEntity> _cachedReminders = [];

  Future<void> start() async {
    if (kIsWeb) return;

    WidgetsBinding.instance.addObserver(this);
    await ensureTimezoneReady();
    await MedicationPushService.instance.ensureNotificationsReady();
    await syncSchedules();
    _startWatching();
    _startMinuteClock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncSchedules());
      unawaited(_checkDueRemindersNow(force: true));
      unawaited(_syncMissedStatuses());
    }
  }

  /// Call from `main()` so timezone data is ready before scheduling.
  Future<void> ensureTimezoneReady() async {
    await _ensureTimezone();
  }

  Future<void> clearFiredToday(String reminderId) async {
    final today = MedicationsService.todayDateString();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_firedPrefsPrefix${reminderId.trim()}_$today');
  }

  Future<void> disposeOnSignOut() async {
    WidgetsBinding.instance.removeObserver(this);
    _watchSub?.cancel();
    _watchSub = null;
    _resyncTimer?.cancel();
    _resyncTimer = null;
    _minuteTimer?.cancel();
    _minuteTimer = null;
    _lastCheckedSlot = null;
    _cachedMeds = {};
    _cachedReminders = [];
    await cancelAll();
  }

  Future<void> onNotificationsPreferenceChanged(bool enabled) async {
    if (kIsWeb) return;
    if (enabled) {
      await start();
    } else {
      _minuteTimer?.cancel();
      _minuteTimer = null;
      await cancelAll();
    }
  }

  /// Shows an immediate notification to verify permissions and scheduling.
  Future<String?> sendTestNotification() async {
    if (kIsWeb) return 'Push notifications are not supported on web.';

    if (!AppSettingsService.instance.settings.notificationsEnabled) {
      return 'Turn on Notifications in Settings first.';
    }

    try {
      await MedicationPushService.instance.ensureNotificationsReady();
      await _notifications.show(
        99999,
        'Medication reminder',
        'This is a test medication reminder from Aura Guide.',
        _notificationDetails(),
        payload: 'TEST',
      );
      await NotificationHistoryService.instance.record(
        title: 'Medication reminder',
        body: 'This is a test medication reminder from Aura Guide.',
        reminderId: 'TEST',
      );
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<void> syncSchedules() async {
    if (kIsWeb) return;
    if (!AppSettingsService.instance.settings.notificationsEnabled) {
      await cancelAll();
      return;
    }

    await _ensureTimezone();
    await MedicationPushService.instance.ensureNotificationsReady();

    final patientId = await _patientUserId();
    if (patientId == null) return;

    await MedicationsService().ensureRemindersForPatient(patientId);

    final location = tz.getLocation(_clinicTimezone);
    final today = MedicationsService.todayDateString();
    final now = tz.TZDateTime.now(location);

    _cachedMeds = await _loadMedications(patientId);
    _cachedReminders = await _loadReminders(patientId);

    final keepIds = <int>{};
    for (final reminder in _cachedReminders) {
      final medication = _cachedMeds[reminder.medicationId];
      if (medication == null) continue;
      if (!_isReminderEligible(reminder, medication, today)) continue;

      final clinicTime = _clinicTimeFromReminder(reminder);
      if (clinicTime == null) continue;

      final isDaily =
          reminder.repeatPattern.trim().toLowerCase() == 'daily';
      final baseId = _notificationId(reminder.reminderId);
      for (var dayOffset = 0; dayOffset < _scheduleDays; dayOffset++) {
        keepIds.add(_notificationIdForDay(baseId, dayOffset));
      }

      await _scheduleReminderAlarm(
        reminder: reminder,
        medication: medication,
        location: location,
        now: now,
        clinicTime: clinicTime,
        isDaily: isDaily,
        today: today,
        baseNotificationId: _notificationId(reminder.reminderId),
      );
    }

    await _cancelStale(keepIds);
    final pending = await _notifications.pendingNotificationRequests();
    debugPrint(
      'MedicationLocalReminderService synced ${keepIds.length} slot(s), '
      '${pending.length} pending alarm(s)',
    );

    await _checkDueRemindersNow(force: true);
  }

  Future<void> cancelAll() async {
    try {
      await _notifications.cancelAll();
    } catch (error) {
      debugPrint('MedicationLocalReminderService cancelAll failed: $error');
    }
  }

  void _startMinuteClock() {
    _minuteTimer?.cancel();
    _minuteTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_checkDueRemindersNow());
      unawaited(_checkMissedFollowUps());
      unawaited(_syncMissedStatuses());
    });
  }

  Future<void> _syncMissedStatuses() async {
    final patientId = await _patientUserId();
    if (patientId == null) return;
    await MedicationsService().syncTodayReminderStatuses(patientId);
  }

  /// Fires a notification when clinic clock matches reminderTime (HH:mm).
  Future<void> _checkDueRemindersNow({bool force = false}) async {
    if (kIsWeb) return;
    if (!AppSettingsService.instance.settings.notificationsEnabled) return;

    await _ensureTimezone();
    final location = tz.getLocation(_clinicTimezone);
    final now = tz.TZDateTime.now(location);
    final slot = _formatSlot(now.hour, now.minute);
    if (!force && slot == _lastCheckedSlot) return;
    _lastCheckedSlot = slot;

    final today = MedicationsService.todayDateString();
    if (_cachedReminders.isEmpty) {
      final patientId = await _patientUserId();
      if (patientId == null) return;
      _cachedMeds = await _loadMedications(patientId);
      _cachedReminders = await _loadReminders(patientId);
    }

    for (final reminder in _cachedReminders) {
      final medication = _cachedMeds[reminder.medicationId];
      if (medication == null) continue;
      if (!_isReminderEligible(reminder, medication, today)) continue;

      final clinicTime = _clinicTimeFromReminder(reminder);
      if (clinicTime == null) continue;
      if (_formatSlot(clinicTime.hour, clinicTime.minute) != slot) continue;
      if (await _alreadyFiredToday(reminder.reminderId, today)) continue;

      await _deliverReminderNotification(
        reminder: reminder,
        medication: medication,
      );
    }
  }

  Future<void> _scheduleReminderAlarm({
    required MedicationReminderEntity reminder,
    required MedicationEntity medication,
    required tz.Location location,
    required tz.TZDateTime now,
    required DateTime clinicTime,
    required bool isDaily,
    required String today,
    required int baseNotificationId,
  }) async {
    final body = _buildBody(reminder, medication);
    final modes = await _androidScheduleModes();
    final daysToSchedule = isDaily ? _scheduleDays : 1;

    for (var dayOffset = 0; dayOffset < daysToSchedule; dayOffset++) {
      final scheduled = tz.TZDateTime(
        location,
        now.year,
        now.month,
        now.day,
        clinicTime.hour,
        clinicTime.minute,
      ).add(Duration(days: dayOffset));

      if (dayOffset == 0 && _sameClinicMinute(scheduled, now)) {
        if (!await _alreadyFiredToday(reminder.reminderId, today)) {
          await _deliverReminderNotification(
            reminder: reminder,
            medication: medication,
          );
        }
        continue;
      }

      if (!scheduled.isAfter(now)) continue;

      if (!isDaily) {
        final clinicDate = ClinicDateTime.fromFirestore(reminder.reminderTime);
        if (clinicDate == null) continue;
        final reminderDate =
            '${clinicDate.year}-${clinicDate.month.toString().padLeft(2, '0')}-${clinicDate.day.toString().padLeft(2, '0')}';
        if (reminderDate != today) continue;
      }

      final notificationId = _notificationIdForDay(baseNotificationId, dayOffset);
      var scheduledOk = false;
      for (final mode in modes) {
        try {
          await _notifications.zonedSchedule(
            notificationId,
            'Medication reminder',
            body,
            scheduled,
            _notificationDetails(),
            androidScheduleMode: mode,
            payload: reminder.reminderId,
          );
          scheduledOk = true;
          break;
        } catch (error) {
          debugPrint(
            'MedicationLocalReminderService schedule ${reminder.reminderId} '
            'day+$dayOffset ($mode) failed: $error',
          );
        }
      }
      if (!scheduledOk) {
        debugPrint(
          'MedicationLocalReminderService could not schedule '
          '${reminder.reminderId} at ${scheduled.toString()}',
        );
      }
    }
  }

  Future<void> _deliverReminderNotification({
    required MedicationReminderEntity reminder,
    required MedicationEntity medication,
  }) async {
    final today = MedicationsService.todayDateString();
    if (await _alreadyFiredToday(reminder.reminderId, today)) return;

    await MedicationPushService.instance.ensureNotificationsReady();

    final body = _buildBody(reminder, medication);
    final notificationId = _notificationId(reminder.reminderId);

    await _notifications.show(
      notificationId,
      'Medication reminder',
      body,
      _notificationDetails(),
      payload: reminder.reminderId,
    );

    await NotificationHistoryService.instance.record(
      title: medication.name,
      body: body,
      reminderId: reminder.reminderId,
    );

    await _persistNotificationToFirestore(
      reminderId: reminder.reminderId,
      kind: 'reminder',
    );

    await _markFiredToday(reminder.reminderId, today);
    debugPrint(
      'MedicationLocalReminderService delivered ${reminder.reminderId} at '
      '${_formatSlot(ClinicDateTime.nowClinic().hour, ClinicDateTime.nowClinic().minute)}',
    );
  }

  Future<void> _checkMissedFollowUps() async {
    if (kIsWeb) return;
    if (!AppSettingsService.instance.settings.notificationsEnabled) return;

    final today = MedicationsService.todayDateString();
    if (_cachedReminders.isEmpty) {
      final patientId = await _patientUserId();
      if (patientId == null) return;
      _cachedMeds = await _loadMedications(patientId);
      _cachedReminders = await _loadReminders(patientId);
    }

    for (final reminder in _cachedReminders) {
      final medication = _cachedMeds[reminder.medicationId];
      if (medication == null) continue;
      if (!_isReminderEligible(reminder, medication, today)) continue;
      if (reminder.isTakenOnDate(today)) continue;
      if (await _missedFollowUpSentToday(reminder.reminderId, today)) continue;
      if (!await _alreadyFiredToday(reminder.reminderId, today)) continue;

      final firedAt = await _firedAtToday(reminder.reminderId, today);
      if (firedAt == null) continue;
      if (DateTime.now().difference(firedAt) < const Duration(minutes: 5)) {
        continue;
      }

      await _deliverMissedFollowUp(
        reminder: reminder,
        medication: medication,
      );
    }
  }

  Future<void> _deliverMissedFollowUp({
    required MedicationReminderEntity reminder,
    required MedicationEntity medication,
  }) async {
    final today = MedicationsService.todayDateString();
    if (await _missedFollowUpSentToday(reminder.reminderId, today)) return;

    await MedicationPushService.instance.ensureNotificationsReady();

    final body =
        '${medication.name} was not marked as taken. Please take it now.';
    final notificationId = _notificationId(reminder.reminderId) + 500000;

    await _notifications.show(
      notificationId,
      'Missed medication',
      body,
      _notificationDetails(),
      payload: reminder.reminderId,
    );

    await NotificationHistoryService.instance.record(
      title: 'Missed medication',
      body: body,
      reminderId: reminder.reminderId,
    );

    await _persistNotificationToFirestore(
      reminderId: reminder.reminderId,
      kind: 'missed',
    );

    await _markMissedFollowUpSent(reminder.reminderId, today);
    debugPrint(
      'MedicationLocalReminderService missed follow-up ${reminder.reminderId}',
    );
  }

  Future<void> _persistNotificationToFirestore({
    required String reminderId,
    required String kind,
  }) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('recordMedicationPatientNotification')
          .call({
        'reminderId': reminderId.trim(),
        'kind': kind,
      });
    } catch (error, stack) {
      debugPrint(
        'recordMedicationPatientNotification failed: $error\n$stack',
      );
    }
  }

  bool _isReminderEligible(
    MedicationReminderEntity reminder,
    MedicationEntity medication,
    String today,
  ) {
    if (!medication.isActiveOnDate(today)) return false;
    if (reminder.status == MedicationReminderEntity.statusMissed &&
        reminder.missedDate == today) {
      return false;
    }
    if (reminder.isTakenOnDate(today)) return false;

    final repeat = reminder.repeatPattern.trim().toLowerCase();
    if (repeat != 'daily') {
      final clinicDate = ClinicDateTime.fromFirestore(reminder.reminderTime);
      if (clinicDate == null) return false;
      final reminderDate =
          '${clinicDate.year}-${clinicDate.month.toString().padLeft(2, '0')}-${clinicDate.day.toString().padLeft(2, '0')}';
      if (reminderDate != today) return false;
    }
    return true;
  }

  bool _sameClinicMinute(tz.TZDateTime a, tz.TZDateTime b) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day &&
        a.hour == b.hour &&
        a.minute == b.minute;
  }

  String _formatSlot(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  Future<bool> _alreadyFiredToday(String reminderId, String today) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_firedPrefsPrefix${reminderId}_$today') ?? false;
  }

  Future<void> _markFiredToday(String reminderId, String today) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_firedPrefsPrefix${reminderId}_$today', true);
    await prefs.setInt(
      '$_firedAtPrefsPrefix${reminderId}_$today',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<DateTime?> _firedAtToday(String reminderId, String today) async {
    final prefs = await SharedPreferences.getInstance();
    final millis =
        prefs.getInt('$_firedAtPrefsPrefix${reminderId}_$today');
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<bool> _missedFollowUpSentToday(String reminderId, String today) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_missedPrefsPrefix${reminderId}_$today') ?? false;
  }

  Future<void> _markMissedFollowUpSent(String reminderId, String today) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_missedPrefsPrefix${reminderId}_$today', true);
  }

  Future<void> _ensureTimezone() async {
    if (_timezoneReady) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(_clinicTimezone));
    _timezoneReady = true;
  }

  Future<List<AndroidScheduleMode>> _androidScheduleModes() async {
    if (!Platform.isAndroid) {
      return const [AndroidScheduleMode.exactAllowWhileIdle];
    }

    try {
      final android = _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final canExact = await android?.canScheduleExactNotifications();
      if (canExact == true) {
        return const [
          AndroidScheduleMode.alarmClock,
          AndroidScheduleMode.exactAllowWhileIdle,
          AndroidScheduleMode.inexactAllowWhileIdle,
        ];
      }
    } catch (error) {
      debugPrint('MedicationLocalReminderService schedule mode check: $error');
    }

    return const [
      AndroidScheduleMode.inexactAllowWhileIdle,
      AndroidScheduleMode.exactAllowWhileIdle,
    ];
  }

  /// Opens Android "Alarms & reminders" settings when the user opts in.
  Future<void> openExactAlarmSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
    } catch (error) {
      debugPrint(
        'MedicationLocalReminderService exact alarm settings: $error',
      );
    }
  }

  Future<bool> hasExactAlarmPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _notifications
              .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin>()
              ?.canScheduleExactNotifications() ??
          false;
    } catch (_) {
      return false;
    }
  }

  void _startWatching() {
    _watchSub?.cancel();
    _resyncTimer?.cancel();

    _watchSub = MedicationsService()
        .watchForCurrentPatient()
        .listen((_) => unawaited(syncSchedules()));

    _resyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(syncSchedules());
    });
  }

  Future<String?> _patientUserId() async {
    final user = AuthSession.resolveUser() ?? FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final result =
        await UserProfileService().loadProfile(user.uid, syncAuthFirst: false);
    return (result.data['userId'] as String?)?.trim() ??
        (result.data['patientId'] as String?)?.trim();
  }

  Future<Map<String, MedicationEntity>> _loadMedications(
    String patientId,
  ) async {
    final snap = await FirebaseFirestore.instance
        .collection('medications')
        .where('userId', isEqualTo: patientId)
        .get();

    final map = <String, MedicationEntity>{};
    for (final doc in snap.docs) {
      final entity = MedicationEntity.fromFirestore(doc.id, doc.data());
      if (entity != null && !entity.isCancelled) {
        map[entity.medicationId] = entity;
      }
    }
    return map;
  }

  Future<List<MedicationReminderEntity>> _loadReminders(
    String patientId,
  ) async {
    final snap = await FirebaseFirestore.instance
        .collection('medicationreminders')
        .where('userId', isEqualTo: patientId)
        .get();

    final all = <MedicationReminderEntity>[];
    for (final doc in snap.docs) {
      final entity = MedicationReminderEntity.fromFirestore(doc.id, doc.data());
      if (entity != null) {
        all.add(entity);
      }
    }

    final today = MedicationsService.todayDateString();
    final dailyToday =
        all.where((r) => r.isDailyInstance && r.doseDate == today).toList();
    if (dailyToday.isNotEmpty) {
      dailyToday.sort((a, b) => a.reminderTime.compareTo(b.reminderTime));
      return dailyToday;
    }

    final slots = all.where((r) => !r.isDailyInstance).toList()
      ..sort((a, b) => a.reminderTime.compareTo(b.reminderTime));
    return slots;
  }

  DateTime? _clinicTimeFromReminder(MedicationReminderEntity reminder) {
    final label = reminder.reminderTimeLabel?.trim();
    if (label != null && label.isNotEmpty) {
      final match = RegExp(r'(\d{2}):(\d{2}):(\d{2})$').firstMatch(label);
      if (match != null) {
        return DateTime(
          2000,
          1,
          1,
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
        );
      }
    }
    final clinic = ClinicDateTime.fromFirestore(reminder.reminderTime);
    if (clinic == null) return null;
    return DateTime(2000, 1, 1, clinic.hour, clinic.minute);
  }

  String _buildBody(
    MedicationReminderEntity reminder,
    MedicationEntity medication,
  ) {
    if (reminder.reminderMessage.isNotEmpty) {
      return reminder.reminderMessage;
    }
    return 'Time to take ${medication.name} (${medication.dosage}).';
  }

  int _notificationId(String reminderId) {
    final digits = int.tryParse(reminderId.replaceAll(RegExp(r'\D'), ''));
    if (digits != null && digits > 0) return digits;
    return reminderId.hashCode & 0x7FFFFFFF;
  }

  int _notificationIdForDay(int baseId, int dayOffset) {
    return baseId * 32 + dayOffset;
  }

  NotificationDetails _notificationDetails() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Automatic medication reminders',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  Future<void> _cancelStale(Set<int> keepIds) async {
    final pending = await _notifications.pendingNotificationRequests();
    for (final request in pending) {
      if (request.id == 99999) continue;
      if (!keepIds.contains(request.id)) {
        await _notifications.cancel(request.id);
      }
    }
  }
}
