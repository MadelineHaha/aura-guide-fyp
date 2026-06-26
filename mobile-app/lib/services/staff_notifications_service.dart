import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

import '../models/emergency_alert_entity.dart';
import 'communication_service.dart';
import 'doctor_patients_service.dart';

enum StaffNotificationKind { emergency, message }

class StaffNotificationItem {
  const StaffNotificationItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.sortMillis,
  });

  final String id;
  final StaffNotificationKind kind;
  final String title;
  final String body;
  final int sortMillis;
}

/// In-app notifications for doctor and therapist portals.
class StaffNotificationsService {
  StaffNotificationsService({
    FirebaseFirestore? firestore,
    DoctorPatientsService? patientsService,
    CommunicationService? communicationService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _patientsService = patientsService ?? DoctorPatientsService(),
        _communicationService = communicationService ?? CommunicationService();

  final FirebaseFirestore _firestore;
  final DoctorPatientsService _patientsService;
  final CommunicationService _communicationService;

  Stream<int>? _badgeCache;
  Stream<List<StaffNotificationItem>>? _itemsCache;

  Stream<int> watchBadgeCount() {
    return _badgeCache ??= Stream.multi((controller) {
      var unreadMessages = 0;
      var emergencyAlerts = 0;

      void emit() {
        if (!controller.isClosed) {
          controller.add(unreadMessages + emergencyAlerts);
        }
      }

      final subs = <StreamSubscription<dynamic>>[
        _communicationService.watchUnreadMessageCountForStaff().listen(
          (count) {
            unreadMessages = count;
            emit();
          },
          onError: controller.addError,
        ),
        _watchEmergencyAlertCount().listen(
          (count) {
            emergencyAlerts = count;
            emit();
          },
          onError: controller.addError,
        ),
      ];

      controller.onCancel = () {
        for (final sub in subs) {
          sub.cancel();
        }
      };
    });
  }

  Stream<List<StaffNotificationItem>> watchNotifications() {
    return _itemsCache ??= Stream.multi((controller) async {
      Future<void> emitNow() async {
        if (controller.isClosed) return;
        try {
          controller.add(await _buildNotifications());
        } catch (e, st) {
          if (!controller.isClosed) {
            controller.addError(e, st);
          }
        }
      }

      await emitNow();

      final subs = <StreamSubscription<dynamic>>[
        _patientsService.watchPatients().listen((_) => unawaited(emitNow())),
        _firestore.collection('emergencyalerts').snapshots().listen(
              (_) => unawaited(emitNow()),
              onError: controller.addError,
            ),
        _communicationService.watchThreadsForStaff().listen(
              (_) => unawaited(emitNow()),
              onError: controller.addError,
            ),
      ];

      controller.onCancel = () {
        for (final sub in subs) {
          sub.cancel();
        }
      };
    });
  }

  Stream<int> _watchEmergencyAlertCount() async* {
    await for (final patients in _patientsService.watchPatients()) {
      final patientIds = patients.map((p) => p.patientId.toUpperCase()).toSet();
      if (patientIds.isEmpty) {
        yield 0;
        continue;
      }
      yield* _firestore.collection('emergencyalerts').snapshots().map((snap) {
        var count = 0;
        for (final doc in snap.docs) {
          final entity = EmergencyAlertEntity.fromFirestore(doc.id, doc.data());
          if (entity == null || !entity.isOpen) continue;
          if (patientIds.contains(entity.userId.trim().toUpperCase())) {
            count++;
          }
        }
        return count;
      });
    }
  }

  Future<List<StaffNotificationItem>> _buildNotifications() async {
    final patients = await _patientsService.fetchPatients();
    final namesById = {
      for (final patient in patients)
        patient.patientId.toUpperCase(): patient.name,
    };
    final patientIds = namesById.keys.toSet();

    final items = <StaffNotificationItem>[];

    if (patientIds.isNotEmpty) {
      final alertSnap = await _firestore.collection('emergencyalerts').get();
      for (final doc in alertSnap.docs) {
        final entity = EmergencyAlertEntity.fromFirestore(doc.id, doc.data());
        if (entity == null || !entity.isOpen) continue;
        final userId = entity.userId.trim().toUpperCase();
        if (!patientIds.contains(userId)) continue;
        final patientName = namesById[userId] ?? userId;
        items.add(
          StaffNotificationItem(
            id: 'alert_${entity.alertId}',
            kind: StaffNotificationKind.emergency,
            title: 'Emergency — $patientName',
            body: '${entity.alertType} • ${entity.dateTime}',
            sortMillis: _parseAlertMillis(entity.dateTime),
          ),
        );
      }
    }

    final threads = await _communicationService.fetchThreadsForStaff();
    for (final thread in threads.where((thread) => thread.unread)) {
      items.add(
        StaffNotificationItem(
          id: 'msg_${thread.conversationId}',
          kind: StaffNotificationKind.message,
          title: 'New message — ${thread.title}',
          body: thread.preview,
          sortMillis: thread.lastMessageAtMs,
        ),
      );
    }

    items.sort((a, b) => b.sortMillis.compareTo(a.sortMillis));
    return items;
  }

  int _parseAlertMillis(String dateTime) {
    final normalized = dateTime.trim().replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    return parsed?.millisecondsSinceEpoch ?? 0;
  }
}
