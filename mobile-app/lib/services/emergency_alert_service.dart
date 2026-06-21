import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

import '../auth_session.dart';
import '../models/emergency_alert_entity.dart';
import '../models/user_entity.dart';
import '../utils/clinic_datetime.dart';
import 'activity_log_actions.dart';
import 'activity_log_service.dart';
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

  EmergencyAlertEntity? _mapDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return EmergencyAlertEntity.fromFirestore(doc.id, doc.data());
  }

  bool _isOpenStatus(Map<String, dynamic> data) {
    final status = (data['Status'] as String?)?.trim() ??
        (data['status'] as String?)?.trim() ??
        '';
    return status == EmergencyAlertEntity.statusActive ||
        status == EmergencyAlertEntity.statusResponded;
  }

  Future<String> _ensurePatientUserId() async {
    final user = AuthSession.resolveUser() ?? _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to send an emergency alert.');
    }

    final result =
        await _profileService.loadProfile(user.uid, syncAuthFirst: false);
    var patientId = (result.data['userId'] as String?)?.trim() ??
        (result.data['patientId'] as String?)?.trim();

    if (patientId != null && patientId.isNotEmpty) {
      await _firestore.collection('users').doc(user.uid).set(
        {'userId': patientId, 'authUid': user.uid},
        SetOptions(merge: true),
      );
      return patientId;
    }

    if (!result.found && result.data.isEmpty) {
      throw StateError(
        'Patient profile not found. Please complete registration first.',
      );
    }

    patientId = await _allocatePatientUserId(user.uid, result.data);
    return patientId;
  }

  Future<String> _allocatePatientUserId(
    String uid,
    Map<String, dynamic> existing,
  ) async {
    final userRef = _firestore.collection(UserEntity.collection).doc(uid);
    final counterRef = _firestore.doc(UserEntity.counterDocPath);

    return _firestore.runTransaction<String>((transaction) async {
      final counterSnap = await transaction.get(counterRef);
      final next = (counterSnap.data()?['next'] as num?)?.toInt() ?? 1;
      final userId = 'U${next.toString().padLeft(5, '0')}';
      transaction.set(counterRef, {'next': next + 1}, SetOptions(merge: true));
      transaction.set(
        userRef,
        {
          ...existing,
          'userId': userId,
          'authUid': uid,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      return userId;
    });
  }

  Future<String> _resolveLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        unawaited(
          ActivityLogService.instance.logWarning(
            action: ActivityLogActions.failedGps,
            details: 'Location permission denied while sending emergency alert.',
          ),
        );
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
    } catch (error) {
      unawaited(
        ActivityLogService.instance.logWarning(
          action: ActivityLogActions.failedGps,
          details: 'Could not retrieve GPS for emergency alert: $error',
        ),
      );
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
    try {
      final patientId = await _ensurePatientUserId();

      final snap = await _firestore
          .collection(_collection)
          .where('UserID', isEqualTo: patientId)
          .limit(10)
          .get();

      for (final doc in snap.docs) {
        if (!_isOpenStatus(doc.data())) continue;
        final entity = _mapDoc(doc);
        if (entity != null && entity.isOpen) return entity;
      }
      return null;
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition' || e.code == 'permission-denied') {
        return null;
      }
      rethrow;
    }
  }

  Stream<EmergencyAlertEntity?> watchActiveForCurrentPatient() {
    return Stream.multi((controller) async {
      try {
        final patientId = await _ensurePatientUserId();

        Future<void> emit(QuerySnapshot<Map<String, dynamic>> snap) async {
          if (controller.isClosed) return;
          EmergencyAlertEntity? active;
          for (final doc in snap.docs) {
            if (!_isOpenStatus(doc.data())) continue;
            final entity = _mapDoc(doc);
            if (entity != null && entity.isOpen) {
              active = entity;
              break;
            }
          }
          controller.add(active);
        }

        final initial = await _firestore
            .collection(_collection)
            .where('UserID', isEqualTo: patientId)
            .limit(10)
            .get();
        await emit(initial);

        final sub = _firestore
            .collection(_collection)
            .where('UserID', isEqualTo: patientId)
            .limit(10)
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

  /// Creates an Active alert (ERD Table 4.7). Returns existing open alert if one exists.
  Future<EmergencyAlertEntity> triggerSos({
    String alertType = EmergencyAlertEntity.alertTypeManualSos,
  }) async {
    final patientId = await _ensurePatientUserId();

    EmergencyAlertEntity? existing;
    try {
      existing = await fetchActiveForCurrentPatient();
    } on FirebaseException {
      existing = null;
    }
    if (existing != null) return existing;

    final alertId = await _reserveAlertId();
    final location = await _resolveLocation();
    final clinicNow = ClinicDateTime.nowClinic();
    final entity = EmergencyAlertEntity(
      alertId: alertId,
      dateTime: EmergencyAlertEntity.formatClinicDateTime(clinicNow),
      location: location,
      alertType: alertType,
      status: EmergencyAlertEntity.statusActive,
      userId: patientId,
    );

    try {
      await _firestore
          .collection(_collection)
          .doc(alertId)
          .set(entity.toFirestoreMap());
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw StateError(
          'Could not save emergency alert. Sign in again, complete patient '
          'registration, and ensure Firestore security rules are deployed '
          '(firebase deploy --only firestore:rules).',
        );
      }
      throw StateError('Could not save emergency alert: ${e.message ?? e.code}');
    }

    final isFall =
        alertType == EmergencyAlertEntity.alertTypeFallDetection;
    if (isFall) {
      unawaited(
        ActivityLogService.instance.logSystem(
          action: ActivityLogActions.emergencyAlert,
          details: 'Fall detection event detected.',
          relatedUserId: patientId,
        ),
      );
    } else {
      unawaited(
        ActivityLogService.instance.log(
          action: ActivityLogActions.emergencyAlert,
          details:
              'Manual SOS alert $alertId sent. Location: $location.',
          userId: patientId,
        ),
      );
    }

    return entity;
  }
}