import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth_session.dart';
import '../models/medication_entity.dart';
import '../models/medication_reminder_entity.dart';
import '../models/patient_notification_item.dart';
import '../utils/clinic_datetime.dart';
import 'medications_service.dart';
import 'notification_history_service.dart';
import 'user_profile_service.dart';

class NotificationsService {
  NotificationsService({
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

  Stream<List<PatientNotificationItem>>? _streamCache;

  Stream<List<PatientNotificationItem>> watchForCurrentPatient() {
    return _streamCache ??= _createWatchStream();
  }

  Stream<List<PatientNotificationItem>> _createWatchStream() {
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
            controller.add(await _buildItems(patientId));
          } catch (e, st) {
            if (!controller.isClosed) {
              controller.addError(e, st);
            }
          }
        }

        await emit();

        final subs = <StreamSubscription<dynamic>>[
          NotificationHistoryService.instance.changes.listen((_) => emit()),
          ...[_medications, _reminders].map(
            (collection) => _firestore
                .collection(collection)
                .where('userId', isEqualTo: patientId)
                .snapshots()
                .listen((_) => emit(), onError: controller.addError),
          ),
        ];

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

  Future<String?> _patientUserId() async {
    final user = AuthSession.resolveUser() ?? _auth.currentUser;
    if (user == null) return null;
    final result =
        await _profileService.loadProfile(user.uid, syncAuthFirst: false);
    return (result.data['userId'] as String?)?.trim() ??
        (result.data['patientId'] as String?)?.trim();
  }

  Future<List<PatientNotificationItem>> _buildItems(String patientId) async {
    final today = MedicationsService.todayDateString();
    final nowClinic = ClinicDateTime.nowClinic();

    final history = await NotificationHistoryService.instance.readAll();
    final delivered = history
        .map(
          (entry) => PatientNotificationItem(
            id: 'history_${entry.id}',
            title: entry.title.isNotEmpty
                ? entry.title
                : 'Medication reminder',
            body: entry.body,
            timeLabel: entry.timeLabel,
            dateLabel: entry.dateLabel,
            kind: PatientNotificationKind.delivered,
            status: PatientNotificationStatus.delivered,
            sortMillis: entry.shownAt.toUtc().millisecondsSinceEpoch,
          ),
        )
        .toList();

    final medsSnap = await _firestore
        .collection(_medications)
        .where('userId', isEqualTo: patientId)
        .get();
    final medsById = <String, MedicationEntity>{};
    for (final doc in medsSnap.docs) {
      final entity = MedicationEntity.fromFirestore(doc.id, doc.data());
      if (entity != null && !entity.isCancelled) {
        medsById[entity.medicationId] = entity;
      }
    }

    final remindersSnap = await _firestore
        .collection(_reminders)
        .where('userId', isEqualTo: patientId)
        .get();

    final scheduled = <PatientNotificationItem>[];
    final deliveredReminderIds = history
        .map((e) => e.reminderId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    for (final doc in remindersSnap.docs) {
      final reminder = MedicationReminderEntity.fromFirestore(doc.id, doc.data());
      if (reminder == null) continue;

      final medication = medsById[reminder.medicationId];
      if (medication == null) continue;
      if (!medication.isActiveOnDate(today)) continue;

      final repeat = reminder.repeatPattern.trim().toLowerCase();
      if (repeat != 'daily') {
        final reminderDate = _dateFromTimestamp(reminder.reminderTime);
        if (reminderDate != today) continue;
      }

      if (deliveredReminderIds.contains(reminder.reminderId)) continue;

      final clinicTime = ClinicDateTime.fromFirestore(reminder.reminderTime);
      if (clinicTime == null) continue;

      final status = _resolveStatus(reminder, today, nowClinic, clinicTime);

      scheduled.add(
        PatientNotificationItem(
          id: reminder.reminderId,
          title: medication.name,
          body: reminder.reminderMessage.isNotEmpty
              ? reminder.reminderMessage
              : 'Take ${medication.name} — ${medication.dosage}',
          timeLabel: MedicationReminderEntity.formatClockLabel(
            reminder.reminderTime,
          ),
          dateLabel: today,
          kind: PatientNotificationKind.scheduled,
          status: status,
          scheduledTime: reminder.reminderTime,
          medicationName: medication.name,
          sortMillis: reminder.reminderTime.millisecondsSinceEpoch,
        ),
      );
    }

    final combined = [...delivered, ...scheduled];
    combined.sort((a, b) => b.sortMillis.compareTo(a.sortMillis));
    return combined;
  }

  String _dateFromTimestamp(Timestamp ts) {
    final clinic = ClinicDateTime.fromFirestore(ts);
    if (clinic == null) return '';
    final y = clinic.year;
    final m = clinic.month.toString().padLeft(2, '0');
    final d = clinic.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  PatientNotificationStatus _resolveStatus(
    MedicationReminderEntity reminder,
    String today,
    DateTime nowClinic,
    DateTime clinicTime,
  ) {
    if (reminder.isTakenOnDate(today) ||
        reminder.status == MedicationReminderEntity.statusCompleted) {
      return PatientNotificationStatus.completed;
    }
    if (reminder.status == MedicationReminderEntity.statusMissed) {
      return PatientNotificationStatus.missed;
    }

    final dueMinutes = clinicTime.hour * 60 + clinicTime.minute;
    final nowMinutes = nowClinic.hour * 60 + nowClinic.minute;
    if (nowMinutes > dueMinutes) {
      return PatientNotificationStatus.missed;
    }
    if (nowMinutes == dueMinutes) {
      return PatientNotificationStatus.pending;
    }
    return PatientNotificationStatus.upcoming;
  }
}
