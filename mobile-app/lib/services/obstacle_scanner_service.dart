import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';

/// Lightweight frame analysis that simulates AI obstacle detection from the camera feed.
class ObstacleScannerService {
  ObstacleScannerService();

  final _alerts = StreamController<ObstacleAlert>.broadcast();
  CameraController? _cameraController;
  DateTime _lastAlertAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _frameCount = 0;

  Stream<ObstacleAlert> get alerts => _alerts.stream;

  Future<void> start(CameraController controller) async {
    await stop();
    if (!controller.value.isInitialized) return;
    _cameraController = controller;
    await controller.startImageStream(_onFrame);
  }

  Future<void> stop() async {
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null && controller.value.isStreamingImages) {
      await controller.stopImageStream();
    }
  }

  Future<void> dispose() async {
    await stop();
    await _alerts.close();
  }

  void _onFrame(CameraImage image) {
    _frameCount++;
    if (_frameCount % 6 != 0) return;

    final score = _analyzeFrame(image);
    final now = DateTime.now();
    if (score < 0.42) return;
    if (now.difference(_lastAlertAt).inMilliseconds < 2800) return;

    _lastAlertAt = now;
    final distance = (4.5 - score * 3.2).clamp(0.8, 4.0);
    final label = score > 0.72 ? 'People' : 'Obstacle';
    if (!_alerts.isClosed) {
      _alerts.add(
        ObstacleAlert(
          label: label,
          distanceMeters: double.parse(distance.toStringAsFixed(1)),
          confidence: score,
        ),
      );
    }
  }

  double _analyzeFrame(CameraImage image) {
    if (image.planes.isEmpty) return 0;

    final plane = image.planes.first;
    final bytes = plane.bytes;
    if (bytes.isEmpty) return 0;

    final width = image.width;
    final height = image.height;
    final centerLeft = (width * 0.28).round();
    final centerRight = (width * 0.72).round();
    final centerTop = (height * 0.18).round();
    final centerBottom = (height * 0.72).round();

    var centerSum = 0.0;
    var centerCount = 0;
    var surroundSum = 0.0;
    var surroundCount = 0;
    var centerVariance = 0.0;

    final samples = min(bytes.length, width * height);
    final step = max(12, samples ~/ 1800);

    for (var y = 0; y < height; y += step) {
      for (var x = 0; x < width; x += step) {
        final index = y * plane.bytesPerRow + x;
        if (index < 0 || index >= bytes.length) continue;
        final value = bytes[index].toDouble();

        final inCenter = x >= centerLeft &&
            x <= centerRight &&
            y >= centerTop &&
            y <= centerBottom;
        if (inCenter) {
          centerSum += value;
          centerCount++;
        } else {
          surroundSum += value;
          surroundCount++;
        }
      }
    }

    if (centerCount == 0 || surroundCount == 0) return 0;

    final centerAvg = centerSum / centerCount;
    final surroundAvg = surroundSum / surroundCount;

    for (var y = centerTop; y < centerBottom; y += step) {
      for (var x = centerLeft; x < centerRight; x += step) {
        final index = y * plane.bytesPerRow + x;
        if (index < 0 || index >= bytes.length) continue;
        final diff = bytes[index] - centerAvg;
        centerVariance += diff * diff;
      }
    }
    centerVariance /= centerCount;

    final contrast = (centerAvg - surroundAvg).abs() / 255;
    final texture = (centerVariance / 6500).clamp(0.0, 1.0);
    return (contrast * 0.55 + texture * 0.45).clamp(0.0, 1.0);
  }
}

class ObstacleAlert {
  const ObstacleAlert({
    required this.label,
    required this.distanceMeters,
    required this.confidence,
  });

  final String label;
  final double distanceMeters;
  final double confidence;

  String get message {
    final distanceText = distanceMeters.toStringAsFixed(
      distanceMeters.truncateToDouble() == distanceMeters ? 0 : 1,
    );
    return "$label ahead $distanceText m";
  }
}
