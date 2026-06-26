import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/emergency_alert_entity.dart';
import '../../services/communication_service.dart';
import 'caregiver_profile_service.dart';

enum CaregiverNotificationKind { emergency, message }

class CaregiverNotificationItem {
  const CaregiverNotificationItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.sortMillis,
  });

  final String id;
  final CaregiverNotificationKind kind;
  final String title;
  final String body;
  final int sortMillis;
}

class CaregiverNotificationsService {
  CaregiverNotificationsService({
    FirebaseFirestore? firestore,
    CaregiverProfileService? profileService,
    CommunicationService? communicationService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _profileService = profileService ?? CaregiverProfileService(),
        _communicationService = communicationService ?? CommunicationService();

  final FirebaseFirestore _firestore;
  final CaregiverProfileService _profileService;
  final CommunicationService _communicationService;

  Stream<int>? _badgeCache;
  Stream<List<CaregiverNotificationItem>>? _itemsCache;

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
        _communicationService.watchUnreadMessageCountForCaregiver().listen(
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

  Stream<List<CaregiverNotificationItem>> watchNotifications() {
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
        _profileService.watchCurrentProfile().listen((_) => unawaited(emitNow())),
        _firestore.collection('emergencyalerts').snapshots().listen(
              (_) => unawaited(emitNow()),
              onError: controller.addError,
            ),
        _communicationService.watchThreadsForCaregiver().listen(
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
    await for (final profile in _profileService.watchCurrentProfile()) {
      final connectedIds =
          CaregiverProfileService.connectedUserIdsFromData(profile);
      if (connectedIds.isEmpty) {
        yield 0;
        continue;
      }
      yield* _firestore.collection('emergencyalerts').snapshots().map((snap) {
        var count = 0;
        for (final doc in snap.docs) {
          final entity = EmergencyAlertEntity.fromFirestore(doc.id, doc.data());
          if (entity == null || !entity.isOpen) continue;
          if (connectedIds.contains(entity.userId.trim().toUpperCase())) {
            count++;
          }
        }
        return count;
      });
    }
  }

  Future<List<CaregiverNotificationItem>> _buildNotifications() async {
    final profile = await _profileService.loadCurrentProfile() ?? {};
    final connectedIds =
        CaregiverProfileService.connectedUserIdsFromData(profile);
    final namesById = await _patientNamesById(connectedIds);
    final items = <CaregiverNotificationItem>[];

    if (connectedIds.isNotEmpty) {
      final alertSnap = await _firestore.collection('emergencyalerts').get();
      for (final doc in alertSnap.docs) {
        final entity = EmergencyAlertEntity.fromFirestore(doc.id, doc.data());
        if (entity == null || !entity.isOpen) continue;
        final userId = entity.userId.trim().toUpperCase();
        if (!connectedIds.contains(userId)) continue;
        final patientName = namesById[userId] ?? userId;
        items.add(
          CaregiverNotificationItem(
            id: 'alert_${entity.alertId}',
            kind: CaregiverNotificationKind.emergency,
            title: 'Emergency — $patientName',
            body: '${entity.alertType} • ${entity.dateTime}',
            sortMillis: _parseAlertMillis(entity.dateTime),
          ),
        );
      }
    }

    final threads = await _communicationService.watchThreadsForCaregiver().first;
    for (final thread in threads.where((thread) => thread.unread)) {
      items.add(
        CaregiverNotificationItem(
          id: 'msg_${thread.conversationId}',
          kind: CaregiverNotificationKind.message,
          title: 'New message — ${thread.title}',
          body: thread.preview,
          sortMillis: thread.lastMessageAtMs,
        ),
      );
    }

    items.sort((a, b) => b.sortMillis.compareTo(a.sortMillis));
    return items;
  }

  Future<Map<String, String>> _patientNamesById(Set<String> ids) async {
    if (ids.isEmpty) return {};
    final snap = await _firestore.collection('users').get();
    final map = <String, String>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final patientId = (data['userId'] ?? data['patientId'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      if (!ids.contains(patientId)) continue;
      final name = data['name']?.toString().trim();
      map[patientId] =
          name != null && name.isNotEmpty ? name : patientId;
    }
    return map;
  }

  int _parseAlertMillis(String dateTime) {
    final normalized = dateTime.trim().replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    return parsed?.millisecondsSinceEpoch ?? 0;
  }
}
