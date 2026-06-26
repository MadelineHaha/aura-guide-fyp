import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/emergency_alert_entity.dart';
import 'caregiver_profile_service.dart';

class CaregiverEmergencyAlert {
  const CaregiverEmergencyAlert({
    required this.docId,
    required this.entity,
    required this.patientName,
  });

  final String docId;
  final EmergencyAlertEntity entity;
  final String patientName;
}

class CaregiverEmergencyService {
  CaregiverEmergencyService({
    FirebaseFirestore? firestore,
    CaregiverProfileService? profileService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _profileService = profileService ?? CaregiverProfileService();

  final FirebaseFirestore _firestore;
  final CaregiverProfileService _profileService;

  static const _alerts = 'emergencyalerts';

  static ({double lat, double lng})? parseGpsLocation(String raw) {
    final match =
        RegExp(r'(-?\d+\.\d+)\s*,\s*(-?\d+\.\d+)').firstMatch(raw.trim());
    if (match == null) return null;
    final lat = double.tryParse(match.group(1)!);
    final lng = double.tryParse(match.group(2)!);
    if (lat == null || lng == null) return null;
    return (lat: lat, lng: lng);
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

  List<CaregiverEmergencyAlert> _mapAlerts(
    QuerySnapshot<Map<String, dynamic>> snap,
    Set<String> connectedIds,
    Map<String, String> namesById,
  ) {
    final alerts = <CaregiverEmergencyAlert>[];
    for (final doc in snap.docs) {
      final entity = EmergencyAlertEntity.fromFirestore(doc.id, doc.data());
      if (entity == null) continue;
      final userId = entity.userId.trim().toUpperCase();
      if (!connectedIds.contains(userId)) continue;
      if (!entity.isOpen) continue;
      alerts.add(
        CaregiverEmergencyAlert(
          docId: doc.id,
          entity: entity,
          patientName: namesById[userId] ?? userId,
        ),
      );
    }
    alerts.sort((a, b) => b.entity.dateTime.compareTo(a.entity.dateTime));
    return alerts;
  }

  Stream<List<CaregiverEmergencyAlert>> watchOpenAlerts() async* {
    await for (final profile in _profileService.watchCurrentProfile()) {
      final connectedIds = CaregiverProfileService.connectedUserIdsFromData(
        profile,
      );
      if (connectedIds.isEmpty) {
        yield [];
        continue;
      }
      final namesById = await _patientNamesById(connectedIds);
      yield* _firestore.collection(_alerts).snapshots().map(
            (snap) => _mapAlerts(snap, connectedIds, namesById),
          );
    }
  }

  Future<void> resolveAlert(String docId, {String notes = 'Resolved by caregiver.'}) async {
    await _firestore.collection(_alerts).doc(docId).update({
      'Status': EmergencyAlertEntity.statusResolved,
      'ResolutionNotes': notes,
    });
  }
}
