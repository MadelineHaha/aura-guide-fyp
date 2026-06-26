import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests microphone and camera access so voice and AR features work smoothly.
class DevicePermissionsService {
  DevicePermissionsService._();

  static final DevicePermissionsService instance = DevicePermissionsService._();

  Future<bool> get hasMicrophone => _isGranted(Permission.microphone);

  Future<bool> get hasCamera => _isGranted(Permission.camera);

  /// Prompts for mic, camera, and notifications when the app starts.
  Future<void> requestMicAndCameraOnLaunch() async {
    await _requestIfNeeded(Permission.microphone);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      await _requestIfNeeded(Permission.speech);
    }
    await _requestIfNeeded(Permission.camera);
    await _requestIfNeeded(Permission.notification);
  }

  /// Ensures microphone access before voice capture.
  Future<bool> ensureMicrophone() => _ensure(Permission.microphone);

  /// iOS also requires speech-recognition permission for voice commands.
  Future<bool> ensureSpeechRecognition() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform != TargetPlatform.iOS) return true;
    return _ensure(Permission.speech);
  }

  /// Ensures camera access before AR navigation.
  Future<bool> ensureCamera() => _ensure(Permission.camera);

  /// Ensures phone access before SIM number detection.
  Future<bool> ensurePhone() => _ensure(Permission.phone);

  Future<void> openSettings() => openAppSettings();

  Future<bool> _isGranted(Permission permission) async {
    final status = await permission.status;
    return status.isGranted;
  }

  Future<void> _requestIfNeeded(Permission permission) async {
    final status = await permission.status;
    if (status.isGranted) return;

    if (status.isDenied || status.isLimited) {
      await permission.request();
      return;
    }

    if (kDebugMode && status.isPermanentlyDenied) {
      debugPrint(
        'DevicePermissionsService: $permission permanently denied — open settings.',
      );
    }
  }

  Future<bool> _ensure(Permission permission) async {
    var status = await permission.status;
    if (status.isGranted) return true;

    if (status.isDenied || status.isLimited) {
      status = await permission.request();
      return status.isGranted;
    }

    return false;
  }
}
