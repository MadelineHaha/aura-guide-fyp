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
import '../utils/voice_option_parser.dart';
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

  /// Groups today's medications for voice summaries.
  static MedicationDayGroups groupTodayItems(List<MedicationItem> items) {
    final taken = <MedicationItem>[];
    final missed = <MedicationItem>[];
    final upcoming = <MedicationItem>[];

    for (final item in items) {
      if (item.takenToday) {
        taken.add(item);
      } else if (item.isOverdue ||
          item.status == MedicationReminderEntity.statusMissed) {
        missed.add(item);
      } else {
        upcoming.add(item);
      }
    }

    return MedicationDayGroups(
      taken: taken,
      missed: missed,
      upcoming: upcoming,
    );
  }

  /// Spoken summary of taken, missed, and upcoming doses for voice-only mode.
  static String buildVoiceSummary(
    List<MedicationItem> items,
    String Function(String key, [Map<String, Object?> params]) l10n,
  ) {
    if (items.isEmpty) {
      return l10n('voiceMedicationsEmpty');
    }

    final groups = groupTodayItems(items);
    final parts = <String>[
      l10n('voiceMedicationsPageIntro'),
      buildProgressLine(items, l10n),
    ];

    var doseNumber = 1;
    for (final section in [
      (headerKey: 'voiceMedicationsTakenHeader', items: groups.taken),
      (headerKey: 'voiceMedicationsMissedHeader', items: groups.missed),
      (headerKey: 'voiceMedicationsUpcomingHeader', items: groups.upcoming),
    ]) {
      parts.add(
        _voiceMedicationSection(
          l10n: l10n,
          headerKey: section.headerKey,
          items: section.items,
          startNumber: doseNumber,
          onNumberAdvanced: (next) => doseNumber = next,
        ),
      );
    }
    parts.add(l10n('voiceMedicationsPageFooter'));

    return parts.join(' ');
  }

  static String buildProgressLine(
    List<MedicationItem> items,
    String Function(String key, [Map<String, Object?> params]) l10n,
  ) {
    final takenCount = items.where((item) => item.takenToday).length;
    final total = items.length;
    final percent = total == 0 ? 0 : ((takenCount / total) * 100).round();
    return l10n('voiceMedicationsProgress', {
      'takenCount': takenCount,
      'total': total,
      'percent': percent,
    });
  }

  /// Parses spoken mark taken / not taken commands against today's doses.
  static MedicationVoiceAction? parseVoiceAction(
    String speech,
    List<MedicationItem> items,
  ) {
    if (items.isEmpty) return null;

    final normalized = _normalizeSpeech(speech);
    if (normalized.isEmpty) return null;

    final taken = _parseWantsTaken(normalized);
    if (taken == null) return null;

    final item = _findItemForSpeech(normalized, items, rawSpeech: speech);
    if (item == null) return null;

    return MedicationVoiceAction(item: item, taken: taken);
  }

  static bool? _parseWantsTaken(String normalized) {
    const notTakenPhrases = [
      'unmark',
      'mark as not taken',
      'as not taken',
      'not taken',
      'mark not taken',
      'did not take',
      'didnt take',
      'have not taken',
      'havent taken',
      'undo',
      'uncheck',
      'batal tanda',
      'tidak ambil',
      'belum ambil',
      '未服用',
      '标记为未服用',
      '取消标记',
      '没有服用',
    ];
    for (final phrase in notTakenPhrases) {
      if (normalized.contains(phrase)) return false;
    }

    const takenPhrases = [
      'mark as taken',
      'as taken',
      'mark taken',
      'checked off',
      'check off',
      'i took',
      'already took',
      'have taken',
      'tandakan',
      'sudah ambil',
      'telah ambil',
      '已服用',
      '标记为已服用',
    ];
    for (final phrase in takenPhrases) {
      if (normalized.contains(phrase)) return true;
    }

    if (normalized.contains('mark') && normalized.contains('taken')) {
      return true;
    }
    if (RegExp(r'\btaken\b').hasMatch(normalized)) {
      return true;
    }
    return null;
  }

  static MedicationItem? _findItemForSpeech(
    String normalized,
    List<MedicationItem> items, {
    String? rawSpeech,
  }) {
    final byOption = VoiceOptionParser.selectByOptionIndex(
      items,
      rawSpeech ?? normalized,
      skipIfTimeLike: true,
    );
    if (byOption != null) return byOption;

    final nameMatches = <MedicationItem>[];
    MedicationItem? best;
    var bestScore = 0;

    for (final item in items) {
      final timeNorm = _normalizeSpeech(item.scheduledTime);
      if (timeNorm.isNotEmpty &&
          (normalized.contains(timeNorm) ||
              normalized.contains(timeNorm.replaceAll(' ', '')))) {
        return item;
      }

      final nameNorm = _normalizeSpeech(item.name);
      if (nameNorm.isNotEmpty && normalized.contains(nameNorm)) {
        nameMatches.add(item);
      }

      if (nameNorm.isNotEmpty) {
        final words = nameNorm.split(RegExp(r'\s+'));
        final score = words
            .where((word) => word.length > 2 && normalized.contains(word))
            .length;
        if (score > bestScore) {
          bestScore = score;
          best = item;
        }
      }
    }

    if (nameMatches.length == 1) return nameMatches.first;
    if (nameMatches.length > 1) {
      for (final item in nameMatches) {
        final timeNorm = _normalizeSpeech(item.scheduledTime);
        if (timeNorm.isNotEmpty &&
            (normalized.contains(timeNorm) ||
                normalized.contains(timeNorm.replaceAll(' ', '')))) {
          return item;
        }
      }
      return null;
    }

    if (bestScore > 0) return best;

    final query = _extractMedicationQuery(normalized);
    if (query.isNotEmpty) {
      for (final item in items) {
        final nameNorm = _normalizeSpeech(item.name);
        if (nameNorm.contains(query) || query.contains(nameNorm)) {
          return item;
        }
      }
    }

    return items.length == 1 ? items.first : null;
  }

  static String _extractMedicationQuery(String normalized) {
    var query = normalized;
    const stripPhrases = [
      'mark as taken',
      'mark as not taken',
      'as not taken',
      'as taken',
      'not taken',
      'check off',
      'please',
      'the',
      'my',
      'medication',
      'medications',
      'medicine',
      'pill',
      'dose',
      'uncheck',
      'unmark',
      'mark',
      'taken',
      'undo',
    ];
    for (final phrase in stripPhrases) {
      query = query.replaceAll(phrase, ' ');
    }
    return query.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _normalizeSpeech(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _voiceMedicationSection({
    required String Function(String key, [Map<String, Object?> params]) l10n,
    required String headerKey,
    required List<MedicationItem> items,
    required int startNumber,
    required void Function(int next) onNumberAdvanced,
  }) {
    if (items.isEmpty) {
      return l10n('voiceMedicationsSectionNone', {'header': l10n(headerKey)});
    }

    var number = startNumber;
    final doses = items
        .map(
          (item) => l10n('voiceMedicationsNumberedDoseLine', {
            'number': number++,
            'name': item.name,
            'time': item.scheduledTime,
            'dosage': item.dosage,
          }),
        )
        .join(' ');
    onNumberAdvanced(number);
    return l10n('voiceMedicationsSectionList', {
      'header': l10n(headerKey),
      'items': doses,
    });
  }
}

class MedicationDayGroups {
  const MedicationDayGroups({
    required this.taken,
    required this.missed,
    required this.upcoming,
  });

  final List<MedicationItem> taken;
  final List<MedicationItem> missed;
  final List<MedicationItem> upcoming;
}

class MedicationVoiceAction {
  const MedicationVoiceAction({
    required this.item,
    required this.taken,
  });

  final MedicationItem item;
  final bool taken;
}
