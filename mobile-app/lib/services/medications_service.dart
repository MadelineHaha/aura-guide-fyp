import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
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
  static const _reminderCounterPath = 'system/medicationReminderCounter';

  static String? _lastEnsurePatientId;
  static DateTime? _lastEnsureAt;
  static Future<int>? _ensureInFlight;

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

  static String repeatPatternForFrequency(String frequency) {
    return frequency.trim() == 'Weekly' ? 'Weekly' : 'Daily';
  }

  static List<String> defaultReminderTimesForFrequency(String frequency) {
    switch (frequency.trim()) {
      case 'Twice daily':
        return const ['08:00', '20:00'];
      case 'Three times daily':
        return const ['08:00', '14:00', '20:00'];
      case 'Once daily':
      case 'Weekly':
      default:
        return const ['08:00'];
    }
  }

  static List<String> pickMissingReminderTimes({
    required List<String> existingTimes,
    required String frequency,
    required int countNeeded,
  }) {
    if (countNeeded <= 0) return const [];

    final defaults = defaultReminderTimesForFrequency(frequency);
    final missing = <String>[];
    for (final time in defaults) {
      if (missing.length >= countNeeded) break;
      if (!existingTimes.contains(time)) missing.add(time);
    }

    var index = 0;
    while (missing.length < countNeeded && defaults.isNotEmpty) {
      final time = defaults[index % defaults.length];
      if (!existingTimes.contains(time) && !missing.contains(time)) {
        missing.add(time);
      }
      index += 1;
      if (index > defaults.length * 4) break;
    }
    return missing;
  }

  static String _clockFromTimestamp(Timestamp ts) {
    final clinic = ClinicDateTime.fromFirestore(ts);
    if (clinic == null) return '08:00';
    return '${clinic.hour.toString().padLeft(2, '0')}:'
        '${clinic.minute.toString().padLeft(2, '0')}';
  }

  static String _reminderTimeLabel(DateTime clinic) {
    final y = clinic.year;
    final m = clinic.month.toString().padLeft(2, '0');
    final d = clinic.day.toString().padLeft(2, '0');
    final hh = clinic.hour.toString().padLeft(2, '0');
    final mm = clinic.minute.toString().padLeft(2, '0');
    final ss = clinic.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  static Timestamp _timestampFromDateAndTime(String dateYmd, String timeHm) {
    final dateParts = dateYmd.split('-');
    final timeParts = timeHm.split(':');
    final clinic = DateTime(
      int.parse(dateParts[0]),
      int.parse(dateParts[1]),
      int.parse(dateParts[2]),
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );
    return ClinicDateTime.toTimestamp(clinic);
  }

  /// Ensures every medication has the required medicationreminders rows.
  Future<int> ensureRemindersForPatient(String patientId) async {
    final trimmedId = patientId.trim();
    if (trimmedId.isEmpty) return 0;

    final now = DateTime.now();
    if (_ensureInFlight != null) {
      return _ensureInFlight!;
    }
    if (_lastEnsurePatientId == trimmedId &&
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
    final medsSnap = await _firestore
        .collection(_medications)
        .where('userId', isEqualTo: patientId)
        .get();
    if (medsSnap.docs.isEmpty) return 0;

    final remindersSnap = await _firestore
        .collection(_reminders)
        .where('userId', isEqualTo: patientId)
        .get();

    final remindersByMed = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in remindersSnap.docs) {
      final medId = (doc.data()['medicationId'] as String?)?.trim() ?? '';
      if (medId.isEmpty) continue;
      remindersByMed.putIfAbsent(medId, () => []).add(doc);
    }

    var created = 0;
    await _firestore.runTransaction((transaction) async {
      final counterRef = _firestore.doc(_reminderCounterPath);
      final counterSnap = await transaction.get(counterRef);
      var remNext = counterSnap.exists
          ? (counterSnap.data()?['next'] as num?)?.toInt() ?? 1
          : 1;

      for (final medDoc in medsSnap.docs) {
        final med = medDoc.data();
        final medicationId =
            (med['medicationId'] as String?)?.trim() ?? medDoc.id;
        if (medicationId.isEmpty) continue;

        final frequency = (med['frequency'] as String?)?.trim() ?? 'Once daily';
        final status = (med['status'] as String?)?.trim() ?? MedicationEntity.statusActive;
        if (status == MedicationEntity.statusCancelled) continue;

        final expectedCount = reminderCountForFrequency(frequency);
        final existingDocs = remindersByMed[medicationId] ?? [];
        if (existingDocs.length >= expectedCount) continue;

        final existingTimes = existingDocs
            .map((doc) => _clockFromTimestamp(doc.data()['reminderTime'] as Timestamp))
            .toList()
          ..sort();
        final timesToAdd = pickMissingReminderTimes(
          existingTimes: existingTimes,
          frequency: frequency,
          countNeeded: expectedCount - existingTimes.length,
        );
        if (timesToAdd.isEmpty) continue;

        final startDate =
            (med['startDate'] as String?)?.trim() ?? todayDateString();
        final repeatPattern = repeatPatternForFrequency(frequency);
        final name = (med['name'] as String?)?.trim() ?? '';
        final dosage = (med['dosage'] as String?)?.trim() ?? '';
        final message = name.isNotEmpty && dosage.isNotEmpty
            ? 'Take $name — $dosage'
            : 'Medication reminder for ${name.isNotEmpty ? name : medicationId}';
        final staffId =
            (med['staffId'] as String?)?.trim() ??
            (med['staffID'] as String?)?.trim() ??
            '';
        if (staffId.isEmpty) continue;

        for (final reminderTime in timesToAdd) {
          final reminderId = 'R${remNext.toString().padLeft(5, '0')}';
          remNext += 1;
          created += 1;

          final ts = _timestampFromDateAndTime(startDate, reminderTime);
          final clinic = ClinicDateTime.fromFirestore(ts);
          final reminderLabel =
              clinic != null ? _reminderTimeLabel(clinic) : '';

          transaction.set(_firestore.collection(_reminders).doc(reminderId), {
            'reminderId': reminderId,
            'reminderTime': ts,
            'reminderTimeLabel': reminderLabel,
            'reminderType': MedicationReminderEntity.typeNotification,
            'reminderMessage': message,
            'repeatPattern': repeatPattern,
            'status': MedicationReminderEntity.statusPending,
            'medicationId': medicationId,
            'userId': patientId,
            'staffId': staffId,
            'completedDate': '',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      if (created > 0) {
        transaction.set(counterRef, {'next': remNext}, SetOptions(merge: true));
      }
    });

    if (created > 0) {
      debugPrint(
        'MedicationsService created $created medication reminder(s) for $patientId',
      );
      unawaited(MedicationLocalReminderService.instance.syncSchedules());
    }
    return created;
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
    if (reminder.status == MedicationReminderEntity.statusMissed) return null;

    final takenToday = reminder.isTakenOnDate(today);

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
          : MedicationReminderEntity.statusPending,
    );
  }

  Future<List<MedicationItem>> _buildTodayItems(String patientId) async {
    await ensureRemindersForPatient(patientId);

    final today = todayDateString();
    final medsById = await _medicationsById(patientId);

    final reminderSnap = await _firestore
        .collection(_reminders)
        .where('userId', isEqualTo: patientId)
        .get();

    final paired = <({Timestamp time, MedicationItem item})>[];
    for (final doc in reminderSnap.docs) {
      final reminder = MedicationReminderEntity.fromFirestore(
        doc.id,
        doc.data(),
      );
      if (reminder == null) continue;

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
