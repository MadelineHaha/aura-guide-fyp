import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth_session.dart';
import '../models/medication_entity.dart';
import '../models/medication_item.dart';
import '../models/medication_reminder_entity.dart';
import '../utils/clinic_datetime.dart';
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
      if (entity != null) {
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
    final today = todayDateString();
    final medsById = await _medicationsById(patientId);

    final reminderSnap = await _firestore
        .collection(_reminders)
        .where('userId', isEqualTo: patientId)
        .get();

    final items = <MedicationItem>[];
    for (final doc in reminderSnap.docs) {
      final reminder = MedicationReminderEntity.fromFirestore(
        doc.id,
        doc.data(),
      );
      if (reminder == null) continue;

      final medication = medsById[reminder.medicationId];
      if (medication == null) continue;

      final item = _buildItem(
        reminder: reminder,
        medication: medication,
        today: today,
      );
      if (item != null) items.add(item);
    }

    items.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
    return items;
  }

  static int countRemainingToday(List<MedicationItem> items) =>
      items.where((m) => !m.takenToday).length;

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
    _clearStreamCache();
  }
}
