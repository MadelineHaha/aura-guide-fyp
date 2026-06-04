import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import '../auth_session.dart';
import '../models/emergency_alert_entity.dart';
import '../utils/clinic_datetime.dart';
import 'user_profile_service.dart';

class EmergencyAlertService {
  EmergencyAlertService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    UserProfileService? profileService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _profileService = profileService ?? UserProfileService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final UserProfileService _profileService;

  static const _collection = 'emergencyalerts';
  static const _counterPath = 'system/emergencyAlertCounter';

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

  EmergencyAlertEntity? _mapDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return EmergencyAlertEntity.fromFirestore(doc.id, doc.data());
  }

  Future<String> _resolveLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return 'Location unavailable (permission denied)';
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      final lat = position.latitude.toStringAsFixed(6);
      final lng = position.longitude.toStringAsFixed(6);
      return '$lat, $lng';
    } catch (_) {
      return 'Location unavailable';
    }
  }

  Future<String> _reserveAlertId() async {
    final counterRef = _firestore.doc(_counterPath);
    return _firestore.runTransaction<String>((transaction) async {
      final counterSnap = await transaction.get(counterRef);
      final next = counterSnap.exists
          ? (counterSnap.data()?['next'] as num?)?.toInt() ?? 1
          : 1;
      final alertId = 'E${next.toString().padLeft(5, '0')}';
      transaction.set(counterRef, {'next': next + 1}, SetOptions(merge: true));
      return alertId;
    });
  }

  Future<EmergencyAlertEntity?> fetchActiveForCurrentPatient() async {
    final patientId = await _patientUserId();
    if (patientId == null) return null;

    final snap = await _firestore
        .collection(_collection)
        .where('userId', isEqualTo: patientId)
        .where('status', isEqualTo: EmergencyAlertEntity.statusActive)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return _mapDoc(snap.docs.first);
  }

  Stream<EmergencyAlertEntity?> watchActiveForCurrentPatient() {
    return Stream.multi((controller) async {
      try {
        final patientId = await _patientUserId();
        if (patientId == null) {
          controller.add(null);
          await controller.close();
          return;
        }

        Future<void> emit(QuerySnapshot<Map<String, dynamic>> snap) async {
          if (controller.isClosed) return;
          EmergencyAlertEntity? active;
          for (final doc in snap.docs) {
            final entity = _mapDoc(doc);
            if (entity != null && entity.isActive) {
              active = entity;
              break;
            }
          }
          controller.add(active);
        }

        final initial = await _firestore
            .collection(_collection)
            .where('userId', isEqualTo: patientId)
            .where('status', isEqualTo: EmergencyAlertEntity.statusActive)
            .limit(1)
            .get();
        await emit(initial);

        final sub = _firestore
            .collection(_collection)
            .where('userId', isEqualTo: patientId)
            .where('status', isEqualTo: EmergencyAlertEntity.statusActive)
            .limit(1)
            .snapshots()
            .listen(emit, onError: controller.addError);

        controller.onCancel = () => sub.cancel();
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    });
  }

  /// Creates an Active alert (ERD Table 4.7). Returns existing active alert if one exists.
  Future<EmergencyAlertEntity> triggerSos({
    String alertType = EmergencyAlertEntity.alertTypeManualSos,
  }) async {
    final patientId = await _patientUserId();
    if (patientId == null) {
      throw StateError('Patient profile not found.');
    }

    final existing = await fetchActiveForCurrentPatient();
    if (existing != null) return existing;

    final alertId = await _reserveAlertId();
    final location = await _resolveLocation();
    final clinicNow = ClinicDateTime.nowClinic();
    final entity = EmergencyAlertEntity(
      alertId: alertId,
      dateTime: ClinicDateTime.toTimestamp(clinicNow),
      location: location,
      alertType: alertType,
      status: EmergencyAlertEntity.statusActive,
      userId: patientId,
      dateTimeLabel: EmergencyAlertEntity.formatClinicDateTime(clinicNow),
    );

    await _firestore
        .collection(_collection)
        .doc(alertId)
        .set(entity.toFirestoreMap());

    return entity;
  }
}
