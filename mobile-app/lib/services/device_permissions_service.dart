import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests microphone and camera access so voice and AR features work smoothly.
class DevicePermissionsService {
  DevicePermissionsService._();

  static final DevicePermissionsService instance = DevicePermissionsService._();

  Future<bool> get hasMicrophone => _isGranted(Permission.microphone);

  Future<bool> get hasCamera => _isGranted(Permission.camera);

  /// Prompts for mic and camera when the app starts (if not already granted).
  Future<void> requestMicAndCameraOnLaunch() async {
    await _requestIfNeeded(Permission.microphone);
    await _requestIfNeeded(Permission.camera);
  }

  /// Ensures microphone access before voice capture.
  Future<bool> ensureMicrophone() => _ensure(Permission.microphone);

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
