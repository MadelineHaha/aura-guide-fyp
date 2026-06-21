import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:pedometer_2/pedometer_2.dart';
import 'package:permission_handler/permission_handler.dart';

import '../auth_session.dart';
import '../utils/clinic_datetime.dart';
import 'user_profile_service.dart';

/// Snapshot of the patient's step count for the UI.
class StepTrackingSnapshot {
  const StepTrackingSnapshot({
    required this.stepsToday,
    required this.lastUpdated,
    required this.permissionGranted,
    required this.isLoading,
    this.errorMessage,
  });

  final int stepsToday;
  final DateTime? lastUpdated;
  final bool permissionGranted;
  final bool isLoading;
  final String? errorMessage;

  static const empty = StepTrackingSnapshot(
    stepsToday: 0,
    lastUpdated: null,
    permissionGranted: false,
    isLoading: true,
  );
}

/// Reads daily step totals from the device step counter (Android Recording API /
/// iOS CMPedometer — not accelerometer-based counting) and syncs one Firestore
/// `activity` document per patient per day for admin reports.
class StepTrackingService extends ChangeNotifier {
  StepTrackingService._();

  static final StepTrackingService instance = StepTrackingService._();

  static const _collection = 'activity';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserProfileService _profileService = UserProfileService();
  final Pedometer _pedometer = Pedometer();

  final StreamController<int> _stepStreamController =
      StreamController<int>.broadcast();

  StreamSubscription<int>? _iosStepSub;
  Timer? _pollTimer;
  _StepLifecycleObserver? _lifecycleObserver;

  String? _patientUserId;
  bool _started = false;
  int _stepsToday = 0;
  DateTime? _lastUpdated;
  bool _permissionGranted = false;
  bool _isLoading = false;
  String? _errorMessage;
  String? _firestoreSavedDate;
  int _firestoreSavedSteps = -1;

  /// Latest step count for today (device sensor).
  int get currentSteps => _stepsToday;

  /// When the count was last read from the device.
  DateTime? get lastUpdated => _lastUpdated;

  bool get permissionGranted => _permissionGranted;

  StepTrackingSnapshot get snapshot => StepTrackingSnapshot(
        stepsToday: _stepsToday,
        lastUpdated: _lastUpdated,
        permissionGranted: _permissionGranted,
        isLoading: _isLoading,
        errorMessage: _errorMessage,
      );

  /// Broadcast stream of step count updates while the app is running.
  Stream<int> get stepStream => _stepStreamController.stream;

  static String todayDateString() {
    final d = ClinicDateTime.nowClinic();
    return _dateString(d);
  }

  static String _dateString(DateTime date) {
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static DateTime _startOfDay(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static String _activityDocId(String userId, String date) => '${userId}_$date';

  /// Starts tracking when the patient is signed in.
  Future<void> start() async {
    if (kIsWeb) {
      _setError('Step tracking is not available on web.');
      return;
    }

    final user = AuthSession.resolveUser() ?? _auth.currentUser;
    if (user == null) return;

    _patientUserId = await _resolvePatientUserId(user.uid);
    if (_patientUserId == null) {
      _setError('Patient profile not found.');
      return;
    }

    _permissionGranted = await requestPermission();
    if (!_permissionGranted) {
      _setError('Activity recognition permission is required for step tracking.');
      notifyListeners();
      return;
    }

    _errorMessage = null;

    if (!_started) {
      _lifecycleObserver = _StepLifecycleObserver(this);
      WidgetsBinding.instance.addObserver(_lifecycleObserver!);
      _startPolling();
      if (Platform.isIOS) {
        _startIosStream();
      }
      _started = true;
    }

    await refresh();
  }

  Future<void> disposeOnSignOut() async {
    await _iosStepSub?.cancel();
    _iosStepSub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_lifecycleObserver != null) {
      WidgetsBinding.instance.removeObserver(_lifecycleObserver!);
      _lifecycleObserver = null;
    }
    _started = false;
    _patientUserId = null;
    _stepsToday = 0;
    _lastUpdated = null;
    _permissionGranted = false;
    _isLoading = false;
    _errorMessage = null;
    _firestoreSavedDate = null;
    _firestoreSavedSteps = -1;
    notifyListeners();
  }

  /// Requests ACTIVITY_RECOGNITION (Android 10+) or motion sensors (iOS).
  Future<bool> requestPermission() async {
    if (kIsWeb) return false;

    final permission =
        Platform.isAndroid ? Permission.activityRecognition : Permission.sensors;
    var status = await permission.status;
    if (status.isGranted) {
      _permissionGranted = true;
      return true;
    }

    status = await permission.request();
    _permissionGranted = status.isGranted;
    return status.isGranted;
  }

  /// Reads today's step total from the device and saves to Firestore if needed.
  Future<void> refresh() async {
    if (kIsWeb) return;

    final patientId = _patientUserId;
    if (patientId == null || !_permissionGranted) return;

    _isLoading = true;
    notifyListeners();

    final now = ClinicDateTime.nowClinic();
    final midnight = _startOfDay(now);
    final today = _dateString(now);

    try {
      final steps = await _pedometer.getStepCount(from: midnight, to: now);
      _applyStepCount(steps, updatedAt: DateTime.now());
      await _saveDailyToFirestore(
        patientId: patientId,
        date: today,
        steps: steps,
      );
      _errorMessage = null;
    } catch (error) {
      debugPrint('StepTrackingService.refresh failed: $error');
      _setError('Could not read steps from this device.');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _applyStepCount(int steps, {required DateTime updatedAt}) {
    final normalized = steps.clamp(0, 200000);
    if (normalized == _stepsToday &&
        _lastUpdated != null &&
        updatedAt.difference(_lastUpdated!).inSeconds < 5) {
      return;
    }
    _stepsToday = normalized;
    _lastUpdated = updatedAt;
    if (!_stepStreamController.isClosed) {
      _stepStreamController.add(normalized);
    }
    notifyListeners();
  }

  Future<String?> _resolvePatientUserId(String authUid) async {
    final result =
        await _profileService.loadProfile(authUid, syncAuthFirst: false);
    final id = (result.data['userId'] as String?)?.trim() ??
        (result.data['patientId'] as String?)?.trim();
    return id?.isNotEmpty == true ? id : null;
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(minutes: 3), (_) {
      unawaited(refresh());
    });
  }

  void _startIosStream() {
    final midnight = _startOfDay(ClinicDateTime.nowClinic());
    _iosStepSub?.cancel();
    _iosStepSub = _pedometer.stepCountStreamFrom(from: midnight).listen(
      (steps) {
        _applyStepCount(steps, updatedAt: DateTime.now());
        final patientId = _patientUserId;
        if (patientId == null) return;
        unawaited(
          _saveDailyToFirestore(
            patientId: patientId,
            date: todayDateString(),
            steps: steps,
          ),
        );
      },
      onError: (Object error) {
        debugPrint('StepTrackingService iOS stream error: $error');
      },
    );
  }

  /// Sync today's steps to Firestore (`activity/{userId}_{date}`).
  /// Writes directly — no pre-read (Firestore rules deny get on missing docs).
  Future<void> _saveDailyToFirestore({
    required String patientId,
    required String date,
    required int steps,
  }) async {
    final normalized = steps.clamp(0, 200000);

    if (_firestoreSavedDate == date && normalized <= _firestoreSavedSteps) {
      return;
    }

    final docId = _activityDocId(patientId, date);
    final docRef = _firestore.collection(_collection).doc(docId);
    final isFirstSaveForDate = _firestoreSavedDate != date;

    try {
      final payload = <String, dynamic>{
        'userId': patientId,
        'date': date,
        'steps': normalized,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (isFirstSaveForDate) {
        payload['createdAt'] = FieldValue.serverTimestamp();
      }

      await docRef.set(payload, SetOptions(merge: true));

      _firestoreSavedDate = date;
      _firestoreSavedSteps = normalized;
      debugPrint(
        'StepTrackingService saved activity/$docId steps=$normalized',
      );
    } on FirebaseException catch (error) {
      debugPrint(
        'StepTrackingService Firestore save failed [${error.code}]: ${error.message}',
      );
    } catch (error) {
      debugPrint('StepTrackingService Firestore save failed: $error');
    }
  }

  void _setError(String message) {
    _errorMessage = message;
    _isLoading = false;
    notifyListeners();
  }
}

class _StepLifecycleObserver with WidgetsBindingObserver {
  _StepLifecycleObserver(this._service);

  final StepTrackingService _service;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_service.refresh());
    }
  }
}
