import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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
  static const _patientNotifications = 'patientnotifications';

  Stream<List<PatientNotificationItem>>? _streamCache;
  Stream<int>? _unreadStreamCache;

  Stream<List<PatientNotificationItem>> watchForCurrentPatient() {
    return _streamCache ??= _createWatchStream();
  }

  Stream<int> watchUnreadCount() {
    return _unreadStreamCache ??= _createUnreadWatchStream();
  }

  /// Marks notifications as read in Firestore and clears the menu badge.
  Future<void> markAllViewedForPatient(String patientId) async {
    final trimmedId = patientId.trim();
    if (trimmedId.isEmpty) return;

    final snap = await _firestore
        .collection(_patientNotifications)
        .where('userId', isEqualTo: trimmedId)
        .get();

    final batch = _firestore.batch();
    var hasWrites = false;
    final now = FieldValue.serverTimestamp();
    for (final doc in snap.docs) {
      final data = doc.data();
      if (data['readAt'] != null) continue;
      batch.update(doc.reference, {
        'readAt': now,
        'updatedAt': now,
      });
      hasWrites = true;
    }
    if (hasWrites) {
      try {
        await batch.commit();
      } catch (error, stack) {
        debugPrint(
          'NotificationsService markAllViewedForPatient failed: $error\n$stack',
        );
      }
    }

    final upTo = DateTime.now().millisecondsSinceEpoch;
    await NotificationHistoryService.instance.markViewed(upToMillis: upTo);
  }

  Stream<int> _createUnreadWatchStream() {
    return Stream.multi((controller) async {
      Future<void> emit() async {
        if (controller.isClosed) return;
        try {
          final patientId = await _patientUserId();
          if (patientId == null) {
            controller.add(0);
            return;
          }
          final items = await _buildItems(patientId);
          final lastViewed =
              await NotificationHistoryService.instance.lastViewedMillis();
          final count = items.where((item) {
            if (item.isUnreadInFirestore) return true;
            return item.sortMillis > lastViewed;
          }).length;
          controller.add(count);
        } catch (e, st) {
          if (!controller.isClosed) {
            controller.addError(e, st);
          }
        }
      }

      try {
        final patientId = await _patientUserId();
        if (patientId == null) {
          controller.add(0);
          await controller.close();
          return;
        }

        await emit();

        final subs = <StreamSubscription<dynamic>>[
          NotificationHistoryService.instance.changes.listen((_) => emit()),
          ...[
            _medications,
            _reminders,
            _patientNotifications,
          ].map(
            (collection) => _firestore
                .collection(collection)
                .where('userId', isEqualTo: patientId)
                .snapshots()
                .listen(
                  (_) => emit(),
                  onError: (error, stack) {
                    debugPrint(
                      'NotificationsService $collection listener failed: $error\n$stack',
                    );
                    unawaited(emit());
                  },
                ),
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
          ...[
            _medications,
            _reminders,
            _patientNotifications,
          ].map(
            (collection) => _firestore
                .collection(collection)
                .where('userId', isEqualTo: patientId)
                .snapshots()
                .listen(
                  (_) => emit(),
                  onError: (error, stack) {
                    debugPrint(
                      'NotificationsService $collection listener failed: $error\n$stack',
                    );
                    unawaited(emit());
                  },
                ),
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

    final delivered = await _deliveredNotifications(patientId);
    final deliveredReminderKeys = delivered
        .map((item) => item.reminderId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

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

    for (final doc in remindersSnap.docs) {
      final reminder = MedicationReminderEntity.fromFirestore(doc.id, doc.data());
      if (reminder == null) continue;

      final medication = medsById[reminder.medicationId];
      if (medication == null) continue;

      final doseDate = reminder.doseDate.isNotEmpty
          ? reminder.doseDate
          : today;
      if (!medication.isActiveOnDate(doseDate)) continue;

      if (reminder.isDailyInstance && reminder.doseDate != today) continue;

      final repeat = reminder.repeatPattern.trim().toLowerCase();
      if (!reminder.isDailyInstance && repeat != 'daily') {
        final reminderDate = _dateFromTimestamp(reminder.reminderTime);
        if (reminderDate != today) continue;
      }

      if (deliveredReminderKeys.contains(reminder.reminderId)) continue;

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
          dateLabel: doseDate,
          kind: PatientNotificationKind.scheduled,
          status: status,
          scheduledTime: reminder.reminderTime,
          medicationName: medication.name,
          reminderId: reminder.reminderId,
          sortMillis: reminder.reminderTime.millisecondsSinceEpoch,
        ),
      );
    }

    final combined = [...delivered, ...scheduled];
    combined.sort((a, b) => b.sortMillis.compareTo(a.sortMillis));
    return combined;
  }

  Future<List<PatientNotificationItem>> _deliveredNotifications(
    String patientId,
  ) async {
    try {
      final snap = await _firestore
          .collection(_patientNotifications)
          .where('userId', isEqualTo: patientId)
          .get();

      if (snap.docs.isNotEmpty) {
        return snap.docs
            .map(_mapFirestoreNotification)
            .whereType<PatientNotificationItem>()
            .toList();
      }
    } catch (error, stack) {
      debugPrint(
        'NotificationsService patientnotifications fetch failed: $error\n$stack',
      );
    }

    final history = await NotificationHistoryService.instance.readAll();
    return history
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
            reminderId: entry.reminderId,
            sortMillis: entry.shownAt.toUtc().millisecondsSinceEpoch,
          ),
        )
        .toList();
  }

  PatientNotificationItem? _mapFirestoreNotification(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final createdAt = data['createdAt'];
    Timestamp? ts;
    if (createdAt is Timestamp) {
      ts = createdAt;
    }
    final sortMillis = ts?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;

    final doseDate = (data['doseDate'] as String?)?.trim() ?? '';
    final slot = (data['slot'] as String?)?.trim() ?? '';
    final timeLabel = _formatSlotLabel(slot, ts);

    final reminderId = (data['reminderId'] as String?)?.trim();
    final medicationId = (data['medicationId'] as String?)?.trim();
    final title = (data['title'] as String?)?.trim() ?? 'Medication reminder';
    final body = (data['body'] as String?)?.trim() ?? '';
    final firestoreStatus = (data['status'] as String?)?.trim() ?? '';

    var status = PatientNotificationStatus.delivered;
    if (firestoreStatus == 'Missed') {
      status = PatientNotificationStatus.missed;
    }

    return PatientNotificationItem(
      id: (data['notificationId'] as String?)?.trim() ?? doc.id,
      title: title,
      body: body,
      timeLabel: timeLabel,
      dateLabel: doseDate.isNotEmpty
          ? doseDate
          : _dateFromTimestamp(ts ?? Timestamp.now()),
      kind: PatientNotificationKind.delivered,
      status: status,
      reminderId: reminderId,
      medicationId: medicationId,
      isUnreadInFirestore: data['readAt'] == null,
      sortMillis: sortMillis,
    );
  }

  String _formatSlotLabel(String slot, Timestamp? createdAt) {
    if (slot.isNotEmpty) {
      final parts = slot.split(':');
      if (parts.length >= 2) {
        final hour = int.tryParse(parts[0]) ?? 0;
        final minute = parts[1].padLeft(2, '0');
        final period = hour >= 12 ? 'PM' : 'AM';
        final h12 = hour % 12 == 0 ? 12 : hour % 12;
        return '$h12:$minute $period';
      }
    }
    if (createdAt != null) {
      return MedicationReminderEntity.formatClockLabel(createdAt);
    }
    return '—';
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
