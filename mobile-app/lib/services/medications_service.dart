import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../auth_session.dart';
import '../models/medication_entity.dart';
import '../models/medication_item.dart';
import '../models/medication_reminder_entity.dart';
import '../utils/clinic_datetime.dart';
import 'activity_log_actions.dart';
import 'activity_log_service.dart';
import 'medication_local_reminder_service.dart';
import 'user_profile_service.dart';

class MedicationsService {
  MedicationsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    UserProfileService? profileService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _profileService = profileService ?? UserProfileService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final UserProfileService _profileService;

  static const _medications = 'medications';
  static const _reminders = 'medicationreminders';

  static String? _lastEnsurePatientId;
  static DateTime? _lastEnsureAt;
  static Future<int>? _ensureInFlight;

  static DateTime? _lastDailySyncAt;
  static const _dailySyncThrottle = Duration(minutes: 5);

  static Future<void> _syncDailyReminderInstances() async {
    final now = DateTime.now();
    if (_lastDailySyncAt != null &&
        now.difference(_lastDailySyncAt!) < _dailySyncThrottle) {
      return;
    }
    _lastDailySyncAt = now;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('syncDailyMedicationReminders')
          .call();
    } catch (error, stack) {
      debugPrint('syncDailyMedicationReminders failed: $error\n$stack');
    }
  }

  /// Today's dose cards: daily rows first, then slot templates not yet instanced.
  List<MedicationReminderEntity> _todayDoseReminders(
    List<MedicationReminderEntity> reminders,
    String today,
    Map<String, MedicationEntity> medsById,
  ) {
    final dailyToday = reminders
        .where((r) => r.isDailyInstance && r.doseDate == today)
        .toList();
    final coveredSlots = dailyToday
        .map((d) => d.slotReminderId)
        .where((id) => id.isNotEmpty)
        .toSet();

    final result = <MedicationReminderEntity>[...dailyToday];

    for (final slot in reminders.where((r) => !r.isDailyInstance)) {
      if (coveredSlots.contains(slot.reminderId)) continue;
      final medication = medsById[slot.medicationId];
      if (medication != null &&
          (medication.isCancelled || !medication.isActiveOnDate(today))) {
        continue;
      }
      if (!_isDueToday(slot, today)) continue;
      result.add(slot);
    }

    result.sort((a, b) => a.reminderTime.compareTo(b.reminderTime));
    return result;
  }

  static String? _lastStatusSyncPatient;
  static DateTime? _lastStatusSyncAt;
  static const _statusSyncThrottle = Duration(seconds: 20);

  static int reminderCountForFrequency(String frequency) {
    switch (frequency.trim()) {
      case 'Twice daily':
        return 2;
      case 'Three times daily':
        return 3;
      case 'Once daily':
      case 'Weekly':
      default:
        return 1;
    }
  }

  /// Ensures every medication has the required medicationreminders rows.
  Future<int> ensureRemindersForPatient(String patientId) async {
    final trimmedId = patientId.trim();
    if (trimmedId.isEmpty) return 0;

    final now = DateTime.now();
    if (_ensureInFlight != null) {
      return _ensureInFlight!;
    }
    final needsEnsure = await _patientNeedsSlotEnsure(trimmedId);
    if (!needsEnsure &&
        _lastEnsurePatientId == trimmedId &&
        _lastEnsureAt != null &&
        now.difference(_lastEnsureAt!) < const Duration(seconds: 20)) {
      return 0;
    }

    _ensureInFlight = _ensureRemindersForPatient(trimmedId);
    try {
      return await _ensureInFlight!;
    } finally {
      _lastEnsurePatientId = trimmedId;
      _lastEnsureAt = DateTime.now();
      _ensureInFlight = null;
    }
  }

  Future<int> _ensureRemindersForPatient(String patientId) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('ensureMedicationSlotReminders')
          .call();
      final data = result.data;
      if (data is Map) {
        final created = (data['created'] as num?)?.toInt() ?? 0;
        if (created > 0) {
          debugPrint(
            'MedicationsService ensured $created medication slot(s) for $patientId',
          );
          unawaited(MedicationLocalReminderService.instance.syncSchedules());
        }
        return created;
      }
    } catch (error, stack) {
      debugPrint('ensureMedicationSlotReminders failed: $error\n$stack');
    }
    return 0;
  }

  Future<bool> _patientNeedsSlotEnsure(String patientId) async {
    final medsSnap = await _firestore
        .collection(_medications)
        .where('userId', isEqualTo: patientId)
        .get();
    if (medsSnap.docs.isEmpty) return false;

    final remindersSnap = await _firestore
        .collection(_reminders)
        .where('userId', isEqualTo: patientId)
        .get();

    final slotsByMed = <String, int>{};
    for (final doc in remindersSnap.docs) {
      final dose = (doc.data()['doseDate'] as String?)?.trim() ?? '';
      if (dose.isNotEmpty) continue;
      final medId = (doc.data()['medicationId'] as String?)?.trim() ?? '';
      if (medId.isEmpty) continue;
      slotsByMed[medId] = (slotsByMed[medId] ?? 0) + 1;
    }

    for (final medDoc in medsSnap.docs) {
      final med = medDoc.data();
      final status = (med['status'] as String?)?.trim() ?? MedicationEntity.statusActive;
      if (status == MedicationEntity.statusCancelled) continue;
      final medicationId =
          (med['medicationId'] as String?)?.trim() ?? medDoc.id;
      final frequency = (med['frequency'] as String?)?.trim() ?? 'Once daily';
      final expected = reminderCountForFrequency(frequency);
      if ((slotsByMed[medicationId] ?? 0) < expected) return true;
    }
    return false;
  }

  void _clearStreamCache() {
    _streamCache = null;
  }

  static String todayDateString() {
    final d = ClinicDateTime.nowClinic();
    final y = d.year;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Rolls over daily reminders and marks overdue doses as Missed in Firestore.
  Future<void> syncTodayReminderStatuses(String patientId) async {
    final trimmedId = patientId.trim();
    if (trimmedId.isEmpty) return;

    final now = DateTime.now();
    if (_lastStatusSyncPatient == trimmedId &&
        _lastStatusSyncAt != null &&
        now.difference(_lastStatusSyncAt!) < _statusSyncThrottle) {
      return;
    }
    _lastStatusSyncPatient = trimmedId;
    _lastStatusSyncAt = now;

    final today = todayDateString();
    final nowClinic = ClinicDateTime.nowClinic();
    final medsById = await _medicationsById(trimmedId);

    final snap = await _firestore
        .collection(_reminders)
        .where('userId', isEqualTo: trimmedId)
        .get();

    final allReminders = snap.docs
        .map(
          (doc) => MedicationReminderEntity.fromFirestore(doc.id, doc.data()),
        )
        .whereType<MedicationReminderEntity>()
        .toList();
    final reminders = _todayDoseReminders(allReminders, today, medsById);

    for (final reminder in reminders) {
      final medication = medsById[reminder.medicationId];
      if (medication == null || medication.isCancelled) continue;
      if (!medication.isActiveOnDate(today)) continue;

      final docSnap = snap.docs.cast<QueryDocumentSnapshot<Map<String, dynamic>>>().where(
        (entry) => entry.id == reminder.reminderId,
      );
      if (docSnap.isEmpty) continue;
      final docRef = docSnap.first.reference;

      try {
        if (!reminder.isDailyInstance) {
          final isDaily = reminder.repeatPattern.toLowerCase() == 'daily';
          if (isDaily) {
            if (reminder.status == MedicationReminderEntity.statusMissed &&
                reminder.missedDate.isNotEmpty &&
                reminder.missedDate != today) {
              await docRef.update({
                'status': MedicationReminderEntity.statusPending,
                'missedDate': '',
                'updatedAt': FieldValue.serverTimestamp(),
              });
              continue;
            }
            if (reminder.status == MedicationReminderEntity.statusCompleted &&
                reminder.completedDate.isNotEmpty &&
                reminder.completedDate != today) {
              await docRef.update({
                'status': MedicationReminderEntity.statusPending,
                'completedDate': '',
                'updatedAt': FieldValue.serverTimestamp(),
              });
              continue;
            }
          }
        }

        if (!_isDueToday(reminder, today)) continue;
        if (reminder.isTakenOnDate(today)) continue;
        if (reminder.isMissedOnDate(today)) continue;

        final schedule = ClinicDateTime.fromFirestore(reminder.reminderTime);
        if (schedule == null) continue;

        final scheduledToday = DateTime(
          nowClinic.year,
          nowClinic.month,
          nowClinic.day,
          schedule.hour,
          schedule.minute,
        );
        if (!nowClinic.isAfter(scheduledToday)) continue;

        final lastPushAt = docSnap.first.data()['lastPushAt'];
        if (lastPushAt is Timestamp) {
          final elapsed = DateTime.now().difference(lastPushAt.toDate());
          if (elapsed < const Duration(minutes: 5)) continue;
        }

        await docRef.update({
          'status': MedicationReminderEntity.statusMissed,
          'missedDate': today,
          'completedDate': '',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } catch (error, stack) {
        debugPrint(
          'syncTodayReminderStatuses update ${reminder.reminderId} failed: '
          '$error\n$stack',
        );
      }
    }
  }

  static String _dateFromTimestamp(Timestamp ts) {
    final clinic = ClinicDateTime.fromFirestore(ts);
    if (clinic == null) return '';
    final y = clinic.year;
    final m = clinic.month.toString().padLeft(2, '0');
    final d = clinic.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<String?> _patientUserId() async {
    final user = AuthSession.resolveUser() ?? _auth.currentUser;
    if (user == null) return null;
    final result =
        await _profileService.loadProfile(user.uid, syncAuthFirst: false);
    final id = (result.data['userId'] as String?)?.trim() ??
        (result.data['patientId'] as String?)?.trim();
    if (id == null || id.isEmpty) return null;

    await _firestore.collection('users').doc(user.uid).set(
      {'userId': id},
      SetOptions(merge: true),
    );
    return id;
  }

  Future<Map<String, MedicationEntity>> _medicationsById(
    String patientId,
  ) async {
    final snap = await _firestore
        .collection(_medications)
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

  bool _isDueToday(MedicationReminderEntity reminder, String today) {
    final reminderDate = _dateFromTimestamp(reminder.reminderTime);
    if (reminder.repeatPattern.toLowerCase() == 'daily') {
      return true;
    }
    return reminderDate == today;
  }

  MedicationItem? _buildItem({
    required MedicationReminderEntity reminder,
    required MedicationEntity medication,
    required String today,
  }) {
    if (medication.isCancelled) return null;
    if (!medication.isActiveOnDate(today)) return null;
    if (!_isDueToday(reminder, today)) return null;

    final takenToday = reminder.isTakenOnDate(today);
    final missedToday = reminder.isMissedOnDate(today);

    return MedicationItem(
      reminderId: reminder.reminderId,
      medicationId: medication.medicationId,
      name: medication.name,
      scheduledTime: MedicationReminderEntity.formatClockLabel(
        reminder.reminderTime,
      ),
      reminderTime: reminder.reminderTime,
      dosage: medication.dosage,
      frequency: medication.frequency,
      instructions: medication.instructions,
      takenToday: takenToday,
      reminderMessage: reminder.reminderMessage.isNotEmpty
          ? reminder.reminderMessage
          : medication.instructions,
      status: takenToday
          ? MedicationReminderEntity.statusCompleted
          : missedToday
              ? MedicationReminderEntity.statusMissed
              : MedicationReminderEntity.statusPending,
    );
  }

  Future<List<MedicationItem>> _buildTodayItems(String patientId) async {
    try {
      await ensureRemindersForPatient(patientId);
    } catch (error, stack) {
      debugPrint('_buildTodayItems ensure failed: $error\n$stack');
    }
    try {
      await _syncDailyReminderInstances();
    } catch (error, stack) {
      debugPrint('_buildTodayItems daily sync failed: $error\n$stack');
    }
    try {
      await syncTodayReminderStatuses(patientId);
    } catch (error, stack) {
      debugPrint('_buildTodayItems status sync failed: $error\n$stack');
    }

    final today = todayDateString();
    final medsById = await _medicationsById(patientId);

    final reminderSnap = await _firestore
        .collection(_reminders)
        .where('userId', isEqualTo: patientId)
        .get();

    final paired = <({Timestamp time, MedicationItem item})>[];
    final allReminders = reminderSnap.docs
        .map(
          (doc) => MedicationReminderEntity.fromFirestore(doc.id, doc.data()),
        )
        .whereType<MedicationReminderEntity>()
        .toList();
    final reminders = _todayDoseReminders(allReminders, today, medsById);

    for (final reminder in reminders) {

      final medication = medsById[reminder.medicationId];
      if (medication == null || medication.isCancelled) continue;

      final item = _buildItem(
        reminder: reminder,
        medication: medication,
        today: today,
      );
      if (item != null) {
        paired.add((time: reminder.reminderTime, item: item));
      }
    }

    paired.sort((a, b) => a.time.compareTo(b.time));
    return paired.map((entry) => entry.item).toList();
  }

  static int countRemainingToday(List<MedicationItem> items) =>
      items.where((m) => !m.takenToday).length;

  /// Next untaken medication for today (sorted by scheduled time).
  static MedicationItem? nextPendingToday(List<MedicationItem> items) {
    for (final item in items) {
      if (!item.takenToday) return item;
    }
    return null;
  }

  Future<List<MedicationItem>> fetchTodayForCurrentPatient() async {
    final patientId = await _patientUserId();
    if (patientId == null) return [];
    return _buildTodayItems(patientId);
  }

  Stream<List<MedicationItem>>? _streamCache;

  Stream<List<MedicationItem>> watchForCurrentPatient() {
    return _streamCache ??= _createWatchStream();
  }

  Future<List<MedicationItem>> fetchTodayForPatient(String patientId) async {
    final trimmed = patientId.trim();
    if (trimmed.isEmpty) return [];
    return _buildTodayItems(trimmed);
  }

  Stream<List<MedicationItem>> watchForPatient(String patientId) {
    final trimmed = patientId.trim();
    if (trimmed.isEmpty) {
      return Stream.value(const []);
    }
    return Stream.multi((controller) async {
      Future<void> emit() async {
        if (controller.isClosed) return;
        try {
          controller.add(await _buildTodayItems(trimmed));
        } catch (e, st) {
          if (!controller.isClosed) {
            controller.addError(e, st);
          }
        }
      }

      try {
        await emit();
        final subs = <StreamSubscription<dynamic>>[];
        for (final collection in [_medications, _reminders]) {
          subs.add(
            _firestore
                .collection(collection)
                .where('userId', isEqualTo: trimmed)
                .snapshots()
                .listen((_) => emit(), onError: controller.addError),
          );
        }
        controller.onCancel = () {
          for (final sub in subs) {
            sub.cancel();
          }
        };
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    });
  }

  Stream<List<MedicationItem>> _createWatchStream() {
    return Stream.multi((controller) async {
      try {
        final patientId = await _patientUserId();
        if (patientId == null) {
          controller.add([]);
          await controller.close();
          return;
        }

        Future<void> emit() async {
          if (controller.isClosed) return;
          try {
            controller.add(await _buildTodayItems(patientId));
          } catch (e, st) {
            if (!controller.isClosed) {
              controller.addError(e, st);
            }
          }
        }

        await emit();

        final subs = <StreamSubscription<dynamic>>[];
        for (final collection in [_medications, _reminders]) {
          subs.add(
            _firestore
                .collection(collection)
                .where('userId', isEqualTo: patientId)
                .snapshots()
                .listen((_) => emit(), onError: controller.addError),
          );
        }

        controller.onCancel = () {
          for (final sub in subs) {
            sub.cancel();
          }
        };
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    });
  }

  Stream<int> watchRemainingTodayCount() =>
      watchForCurrentPatient().map(countRemainingToday);

  /// Marks today's dose via MedicationReminder status (ERD Table 4.6).
  Future<void> setTakenToday({
    required String reminderId,
    required bool taken,
  }) async {
    if (await _patientUserId() == null) {
      throw StateError('Patient profile not found.');
    }

    final trimmedId = reminderId.trim();
    if (trimmedId.isEmpty) {
      throw StateError('Invalid reminder.');
    }

    final today = todayDateString();
    await _firestore.collection(_reminders).doc(trimmedId).update({
      'status': taken
          ? MedicationReminderEntity.statusCompleted
          : MedicationReminderEntity.statusPending,
      'completedDate': taken ? today : '',
      'missedDate': '',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    if (taken) {
      unawaited(
        ActivityLogService.instance.log(
          action: ActivityLogActions.markMedication,
          details: 'Marked medication reminder $trimmedId as completed.',
        ),
      );
    }
    if (!taken) {
      await MedicationLocalReminderService.instance.clearFiredToday(trimmedId);
    }
    _clearStreamCache();
    unawaited(MedicationLocalReminderService.instance.syncSchedules());
  }
}
