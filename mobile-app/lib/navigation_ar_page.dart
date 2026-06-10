import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'models/navigation_destination.dart' show NavDestination;
import 'services/navigation_guidance_controller.dart';
import 'services/obstacle_scanner_service.dart';
import 'widgets/app_back_button.dart';
import 'widgets/ar_path_overlay.dart';
import 'widgets/direction_compass.dart';

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
  double _pulse = 0;

  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _guidanceState = widget.guidance.currentState;
    _guidanceSub = widget.guidance.states.listen((state) {
      if (!mounted) return;
      setState(() => _guidanceState = state);
    });
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _pulseController.addListener(() {
      if (mounted) setState(() => _pulse = _pulseController.value);
    });
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
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
        setState(() => _activeAlert = alert);
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
    _pulseController.dispose();
    _guidanceSub?.cancel();
    _obstacleSub?.cancel();
    unawaited(_obstacleScanner.dispose());
    _cameraController?.dispose();
    super.dispose();
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
          if (cameraReady) CameraPreview(_cameraController!) else Container(color: Colors.black),
          if (cameraReady)
            ArPathOverlay(
              turnDeltaDegrees: _guidanceState.turnDelta,
              guidanceHint: _guidanceState.guidanceHint,
              pulse: _pulse,
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
                  if (_guidanceState.hasGpsFix)
                    Text(
                      '${_guidanceState.distanceMeters.toStringAsFixed(0)} m',
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
    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DirectionCompass(
              state: _guidanceState,
              size: cameraReady ? 120 : 150,
              compact: cameraReady,
            ),
            if (cameraReady) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _accent.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.sensors, color: _accent, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'AI scanning surroundings for obstacles',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
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
              alert.message,
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
