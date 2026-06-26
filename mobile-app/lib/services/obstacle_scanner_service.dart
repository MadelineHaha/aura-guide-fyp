import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'obstacle_detection_service.dart';
import '../models/obstacle_bounds.dart';
import '../utils/obstacle_direction.dart';

/// Automatically scans the live camera feed for obstacles in the background.
class ObstacleScannerService {
  ObstacleScannerService({ObstacleDetectionService? detection})
      : _detection = detection ?? ObstacleDetectionService.instance;

  final ObstacleDetectionService _detection;

  final _alerts = StreamController<ObstacleAlert>.broadcast();
  CameraController? _cameraController;
  CameraImage? _latestFrame;
  Timer? _scanTimer;

  DateTime _lastAlertAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastPositiveScanAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _scanInFlight = false;
  double? _smoothedDistanceMeters;
  String _smoothedDistanceLabel = '';
  String? _trackedLabel;
  int _consistentHits = 0;

  static const _scanInterval = Duration(milliseconds: 100);
  static const _alertCooldown = Duration(milliseconds: 200);
  static const _strongConfidence = 0.30;
  static const _weakConfidenceHits = 1;
  static const _heuristicStall = Duration(milliseconds: 450);

  bool isRunning = false;
  bool modelReady = false;
  int framesSeen = 0;
  String statusText = 'Starting';

  Stream<ObstacleAlert> get alerts => _alerts.stream;

  Future<void> warmUp() async {
    modelReady = await _detection.initialize();
  }

  Future<void> start(CameraController controller) async {
    await stop();
    if (!controller.value.isInitialized) return;

    modelReady = await _detection.initialize();
    statusText = modelReady ? 'Scanning surroundings' : 'Scanning (fallback)';

    _cameraController = controller;
    isRunning = true;

    await controller.startImageStream(_onFrame);

    unawaited(_scanLatestFrame());
    _scanTimer = Timer.periodic(_scanInterval, (_) {
      unawaited(_scanLatestFrame());
    });
  }

  Future<void> stop() async {
    isRunning = false;
    _scanTimer?.cancel();
    _scanTimer = null;
    _latestFrame = null;
    _smoothedDistanceMeters = null;
    _smoothedDistanceLabel = '';
    _trackedLabel = null;
    _consistentHits = 0;

    final controller = _cameraController;
    _cameraController = null;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Future<void> dispose() async {
    await stop();
    if (!_alerts.isClosed) {
      await _alerts.close();
    }
  }

  void _onFrame(CameraImage image) {
    framesSeen++;
    _latestFrame = image;
  }

  Future<void> _scanLatestFrame() async {
    if (!isRunning || _scanInFlight) return;

    final frame = _latestFrame;
    if (frame == null) {
      statusText = 'Waiting for camera frames';
      return;
    }

    _scanInFlight = true;
    try {
      ObstacleDetection? detection;

      if (modelReady) {
        detection = await _detection.detectFromCameraAsync(frame);
      }

      if (detection == null && !modelReady) {
        detection = await detectObstacleHeuristicAsync(frame);
      } else if (detection == null && modelReady) {
        final now = DateTime.now();
        final stalled = now.difference(_lastPositiveScanAt) > _heuristicStall;
        final nearMiss = _detection.lastTopScore >= 0.15;
        if (stalled && nearMiss) {
          detection = await detectObstacleHeuristicAsync(frame);
        }
      }

      if (detection == null) {
        if (_consistentHits > 0) _consistentHits--;
        if (_consistentHits == 0) _trackedLabel = null;

        if (_detection.inferenceCount % 8 == 0) {
          debugPrint(
            'ObstacleScanner: no detection '
            '(top=${_detection.lastTopLabel} '
            'score=${_detection.lastTopScore.toStringAsFixed(3)} '
            'frames=$framesSeen model=$modelReady)',
          );
        }
        statusText = modelReady
            ? 'Scanning (${_detection.lastTopLabel.isEmpty ? 'watching' : _detection.lastTopLabel} ${_detection.lastTopScore.toStringAsFixed(2)})'
            : 'Scanning surroundings';
        return;
      }

      _lastPositiveScanAt = DateTime.now();

      if (detection.label == _trackedLabel) {
        _consistentHits++;
      } else {
        _trackedLabel = detection.label;
        _consistentHits = 1;
      }

      if (detection.label == 'Person' &&
          detection.confidence < 0.50) {
        return;
      }

      final strongHit = detection.confidence >= _strongConfidence;

      if (!strongHit && _consistentHits < _weakConfidenceHits) {
        return;
      }

      final now = DateTime.now();
      if (now.difference(_lastAlertAt) < _alertCooldown) return;

      final rotateForPortrait = frame.width > frame.height;
      final direction = detection.bounds == null
          ? ObstacleDirection.front
          : directionFromBounds(
              detection.bounds!,
              rotateForPortrait: rotateForPortrait,
            );

      final distanceMeters = _smoothDistance(
        label: detection.label,
        distanceMeters: detection.distanceMeters,
      );

      _lastAlertAt = now;
      statusText = '${detection.label} detected';
      debugPrint(
        'ObstacleScanner: ALERT ${detection.label} '
        'dir=${direction.name} '
        'conf=${detection.confidence.toStringAsFixed(2)} '
        'hits=$_consistentHits '
        'dist=${distanceMeters.toStringAsFixed(1)}m '
        'centerX=${detection.bounds?.displayCenterX(rotateForPortrait: rotateForPortrait).toStringAsFixed(2)}',
      );
      if (!_alerts.isClosed) {
        _alerts.add(
          ObstacleAlert(
            label: detection.label,
            distanceMeters: double.parse(distanceMeters.toStringAsFixed(1)),
            confidence: detection.confidence,
            bounds: detection.bounds,
            direction: direction,
          ),
        );
      }
    } catch (error) {
      debugPrint('ObstacleScannerService scan error: $error');
      statusText = 'Scanner error';
    } finally {
      _scanInFlight = false;
      if (isRunning && _latestFrame != null) {
        unawaited(_scanLatestFrame());
      }
    }
  }

  double _smoothDistance({
    required String label,
    required double distanceMeters,
  }) {
    if (_smoothedDistanceLabel != label) {
      _smoothedDistanceLabel = label;
      _smoothedDistanceMeters = distanceMeters;
      return distanceMeters;
    }

    final previous = _smoothedDistanceMeters ?? distanceMeters;
    const alpha = 0.45;
    final smoothed = previous + alpha * (distanceMeters - previous);
    _smoothedDistanceMeters = smoothed;
    return smoothed;
  }
}

class ObstacleAlert {
  const ObstacleAlert({
    required this.label,
    required this.distanceMeters,
    required this.confidence,
    this.bounds,
    this.direction = ObstacleDirection.front,
  });

  final String label;
  final double distanceMeters;
  final double confidence;
  final ObstacleBounds? bounds;
  final ObstacleDirection direction;

  ObstacleDirection get resolvedDirection {
    if (bounds == null) return direction;
    return directionFromBounds(bounds!);
  }

  String get message {
    final distanceText = distanceMeters.toStringAsFixed(
      distanceMeters.truncateToDouble() == distanceMeters ? 0 : 1,
    );
    return '$label on the ${direction.name}, $distanceText m';
  }
}
