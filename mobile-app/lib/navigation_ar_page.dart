import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'models/navigation_destination.dart' show NavDestination;
import 'l10n/app_localizations.dart';
import 'services/activity_log_actions.dart';
import 'services/activity_log_service.dart';
import 'services/app_settings_service.dart';
import 'services/device_permissions_service.dart';
import 'services/navigation_guidance_controller.dart';
import 'services/voice_assistant_coordinator.dart';
import 'services/obstacle_scanner_service.dart';
import 'utils/distance_format.dart';
import 'utils/obstacle_direction.dart';
import 'utils/obstacle_labels.dart';
import 'widgets/app_back_button.dart';
import 'widgets/ar_path_overlay.dart';
import 'widgets/obstacle_detection_overlay.dart';

class NavigationArPage extends StatefulWidget {
  const NavigationArPage({
    super.key,
    required this.destination,
    required this.guidance,
  });

  final NavDestination destination;
  final NavigationGuidanceController guidance;

  @override
  State<NavigationArPage> createState() => _NavigationArPageState();
}

class _NavigationArPageState extends State<NavigationArPage>
    with SingleTickerProviderStateMixin {
  static const Color _accent = Color(0xFF63F7F2);

  final _obstacleScanner = ObstacleScannerService();

  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _initializingCamera = true;
  String? _error;

  StreamSubscription<NavigationGuidanceState>? _guidanceSub;
  StreamSubscription<ObstacleAlert>? _obstacleSub;

  NavigationGuidanceState _guidanceState = NavigationGuidanceState.initial;
  ObstacleAlert? _activeAlert;
  DateTime? _lastObstacleSpeechAt;
  String? _lastSpokenObstacleMessage;
  Timer? _clearAlertTimer;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    VoiceAssistantCoordinator.instance.acquireMicLock();
    _guidanceState = widget.guidance.currentState;
    _guidanceSub = widget.guidance.states.listen((state) {
      if (!mounted) return;
      setState(() => _guidanceState = state);
    });
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    unawaited(_initCamera());
  }

  Future<void> _initCamera() async {
    try {
      await _obstacleScanner.warmUp();

      final cameraGranted =
          await DevicePermissionsService.instance.ensureCamera();
      if (!cameraGranted) {
        unawaited(
          ActivityLogService.instance.logWarning(
            action: ActivityLogActions.cameraDenied,
            details: 'Camera permission denied for AR navigation.',
          ),
        );
        throw StateError(
          'Camera permission is required for AR navigation. '
          'Please allow camera access in your device settings.',
        );
      }

      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        throw StateError('No camera found on this device.');
      }

      final backCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      try {
        await controller.initialize();
      } on CameraException catch (e) {
        if (e.code == 'CameraAccessDenied' ||
            e.code == 'CameraAccessDeniedWithoutPrompt') {
          unawaited(
            ActivityLogService.instance.logWarning(
              action: ActivityLogActions.cameraDenied,
              details: 'Camera access denied while initializing AR navigation.',
            ),
          );
          throw StateError(
            'Camera permission is required for AR navigation. '
            'Please allow camera access in your device settings.',
          );
        }
        rethrow;
      }
      _cameraController = controller;

      _obstacleSub = _obstacleScanner.alerts.listen((alert) {
        if (!mounted) return;
        _clearAlertTimer?.cancel();
        setState(() => _activeAlert = alert);
        _clearAlertTimer = Timer(const Duration(seconds: 3), () {
          if (!mounted) return;
          setState(() => _activeAlert = null);
        });
        unawaited(_announceObstacle(alert));
      });
      await _obstacleScanner.start(controller);

      if (mounted) {
        setState(() {
          _initializingCamera = false;
          _error = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initializingCamera = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    VoiceAssistantCoordinator.instance.releaseMicLock();
    _clearAlertTimer?.cancel();
    _pulseController.dispose();
    _guidanceSub?.cancel();
    _obstacleSub?.cancel();
    unawaited(_obstacleScanner.dispose());
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _announceObstacle(ObstacleAlert alert) async {
    final message = _obstacleLocatedMessage(alert);

    final now = DateTime.now();
    if (_lastSpokenObstacleMessage == message &&
        _lastObstacleSpeechAt != null &&
        now.difference(_lastObstacleSpeechAt!) <
            const Duration(milliseconds: 1500)) {
      return;
    }

    _lastObstacleSpeechAt = now;
    _lastSpokenObstacleMessage = message;
    await AppSettingsService.instance.stopSpeaking();
    await AppSettingsService.instance.speakCalmSystemVoice(message);
  }

  String _obstacleLocatedMessage(ObstacleAlert alert) {
    final detectedLabel = _localizedDetectedLabel(alert.label);
    final direction = context.l10n.t(
      obstacleDirectionL10nKey(alert.direction),
    );
    final distance = alert.distanceMeters.toStringAsFixed(
      alert.distanceMeters.truncateToDouble() == alert.distanceMeters ? 0 : 1,
    );
    return context.l10n.t(
      'obstacleLocated',
      {'label': detectedLabel, 'direction': direction, 'distance': distance},
    );
  }

  String _obstacleOverlayLabel(ObstacleAlert alert) {
    return _obstacleLocatedMessage(alert);
  }

  String _localizedObstacleLabel(String label) {
    if (label == 'Person') {
      return context.l10n.t('obstaclePeople');
    }
    return ObstacleLabels.friendlyName(label);
  }

  String _localizedDetectedLabel(String label) {
    return context.l10n.t(
      'obstacleDetected',
      {'label': _localizedObstacleLabel(label)},
    );
  }

  Widget _buildFullScreenCameraPreview() {
    final controller = _cameraController!;
    final previewSize = controller.value.previewSize;

    final overlay = _activeAlert != null
        ? ObstacleDetectionOverlay(
            alert: _activeAlert!,
            controller: controller,
            labelText: _obstacleOverlayLabel(_activeAlert!),
          )
        : null;

    if (previewSize == null) {
      return CameraPreview(controller, child: overlay);
    }

    // Fill the screen like the native camera app (no small letterboxed preview).
    final isPortrait =
        MediaQuery.orientationOf(context) == Orientation.portrait;
    final previewWidth =
        isPortrait ? previewSize.height : previewSize.width;
    final previewHeight =
        isPortrait ? previewSize.width : previewSize.height;

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: previewWidth,
            height: previewHeight,
            child: CameraPreview(controller, child: overlay),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cameraReady =
        !_initializingCamera && _error == null && _cameraController != null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (cameraReady)
            Positioned.fill(
              child: _buildFullScreenCameraPreview(),
            )
          else
            Container(color: Colors.black),
          if (cameraReady)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return ArPathOverlay(
                  turnDeltaDegrees: _guidanceState.turnDelta,
                  pulse: _pulseController.value,
                );
              },
            ),
          _buildTopHud(),
          _buildDirectionPanel(cameraReady),
          if (_initializingCamera)
            Container(
              color: Colors.black87,
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: _accent),
                  SizedBox(height: 12),
                  Text(
                    'Starting camera…',
                    style: TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
          if (_error != null) _buildErrorState(),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: const AppBackButton(style: AppBackButtonStyle.filled),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHud() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 64, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_activeAlert != null) _ObstacleBanner(alert: _activeAlert!),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(
                    _guidanceState.hasGpsFix
                        ? Icons.gps_fixed
                        : Icons.gps_not_fixed,
                    color: _accent,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.destination.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_guidanceState.walkMode)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _accent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.directions_walk, color: _accent, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Walk',
                            style: TextStyle(
                              color: _accent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_guidanceState.hasGpsFix)
                    Text(
                      formatNavigationDistance(_guidanceState.distanceMeters),
                      style: const TextStyle(
                        color: _accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDirectionPanel(bool cameraReady) {
    if (!cameraReady) return const SizedBox.shrink();

    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _accent.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.sensors, color: _accent, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.t('aiScanningObstacles'),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Text(
        _error ?? 'Could not start AR navigation.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.white70, height: 1.4),
      ),
    );
  }
}

class _ObstacleBanner extends StatelessWidget {
  const _ObstacleBanner({required this.alert});

  final ObstacleAlert alert;

  static String messageFor(BuildContext context, ObstacleAlert alert) {
    final friendlyLabel = alert.label == 'Person'
        ? context.l10n.t('obstaclePeople')
        : ObstacleLabels.friendlyName(alert.label);
    final detectedLabel = context.l10n.t(
      'obstacleDetected',
      {'label': friendlyLabel},
    );
    final direction = context.l10n.t(
      obstacleDirectionL10nKey(alert.direction),
    );
    final distance = alert.distanceMeters.toStringAsFixed(
      alert.distanceMeters.truncateToDouble() == alert.distanceMeters ? 0 : 1,
    );
    return context.l10n.t(
      'obstacleLocated',
      {'label': detectedLabel, 'direction': direction, 'distance': distance},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF63F7F2),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF63F7F2).withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.black, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _ObstacleBanner.messageFor(context, alert),
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
