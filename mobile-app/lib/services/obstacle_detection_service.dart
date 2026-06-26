import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import 'obstacle_frame_packet.dart';
import 'obstacle_inference_worker.dart';
import '../models/obstacle_bounds.dart';
import '../utils/obstacle_direction.dart';

class ObstacleDetection {
  const ObstacleDetection({
    required this.label,
    required this.distanceMeters,
    required this.confidence,
    required this.classId,
    this.bounds,
  });

  final String label;
  final double distanceMeters;
  final double confidence;
  final int classId;
  final ObstacleBounds? bounds;

  ObstacleDirection get direction {
    if (bounds == null) return ObstacleDirection.front;
    return directionFromBounds(bounds!);
  }
}

/// Coordinates background YOLO inference for obstacle alerts.
class ObstacleDetectionService {
  ObstacleDetectionService._();

  static final ObstacleDetectionService instance = ObstacleDetectionService._();

  final ObstacleInferenceWorker _worker = ObstacleInferenceWorker();

  double lastTopScore = 0;
  String lastTopLabel = '';
  int inferenceCount = 0;

  bool get isReady => _workerReady;
  bool _workerReady = false;
  bool _initializing = false;
  Completer<bool>? _initCompleter;

  Future<bool> initialize() async {
    if (_workerReady) return true;
    if (_initializing) {
      return _initCompleter?.future ?? Future.value(false);
    }

    _initializing = true;
    _initCompleter = Completer<bool>();
    try {
      _workerReady = await _worker.start();
      if (_workerReady) {
        await _worker.warmUpInference();
      }
      debugPrint('ObstacleDetectionService worker ready=$_workerReady');
      _initCompleter!.complete(_workerReady);
      return _workerReady;
    } catch (error, stack) {
      debugPrint('ObstacleDetectionService initialize failed: $error\n$stack');
      _initCompleter!.complete(false);
      return false;
    } finally {
      _initializing = false;
    }
  }

  Future<ObstacleDetection?> detectFromCameraAsync(CameraImage image) async {
    if (!_workerReady) return null;

    final result = await _worker.detectFromCamera(image);
    inferenceCount++;
    if (result == null) return null;

    lastTopScore = result.topScore;
    lastTopLabel = result.topLabel;

    if (result.label.isNotEmpty) {
      return result.toDetection();
    }

    return null;
  }

  Future<ObstacleDetection?> detectAsync(ObstacleFramePacket packet) async {
    if (!_workerReady) return null;

    final result = await _worker.detect(packet);
    inferenceCount++;
    if (result == null) return null;

    lastTopScore = result.topScore;
    lastTopLabel = result.topLabel;

    if (result.label.isNotEmpty) {
      return result.toDetection();
    }

    return null;
  }

  Future<void> dispose() async {
    await _worker.dispose();
    _workerReady = false;
  }
}

/// Fast fallback when the YOLO model misses obvious foreground objects.
Future<ObstacleDetection?> detectObstacleHeuristicAsync(CameraImage image) {
  if (image.planes.isEmpty) return Future.value(null);

  final y = image.planes[0];
  final compact = ObstacleFramePacket.compactYPlaneForStream(
    src: y.bytes,
    srcW: image.width,
    srcH: image.height,
    srcStride: y.bytesPerRow,
  );

  return compute(
    _detectObstacleHeuristicIsolate,
    _HeuristicFrameInput(
      width: compact.width,
      height: compact.height,
      rowStride: compact.yStride,
      bytes: compact.yBytes,
    ),
  );
}

class _HeuristicFrameInput {
  const _HeuristicFrameInput({
    required this.width,
    required this.height,
    required this.rowStride,
    required this.bytes,
  });

  final int width;
  final int height;
  final int rowStride;
  final Uint8List bytes;
}

ObstacleDetection? _detectObstacleHeuristicIsolate(_HeuristicFrameInput input) {
  final bytes = input.bytes;
  if (bytes.isEmpty) return null;

  final width = input.width;
  final height = input.height;
  final rowStride = input.rowStride;

  final centerLeft = (width * 0.24).round();
  final centerRight = (width * 0.76).round();
  final centerTop = (height * 0.16).round();
  final centerBottom = (height * 0.78).round();

  var centerSum = 0.0;
  var centerCount = 0;
  var surroundSum = 0.0;
  var surroundCount = 0;
  var centerVariance = 0.0;

  final step = math.max(8, (width * height) ~/ 1400);

  for (var y = 0; y < height; y += step) {
    final rowStart = y * rowStride;
    for (var x = 0; x < width; x += step) {
      final index = rowStart + x;
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

  if (centerCount == 0 || surroundCount == 0) return null;

  final centerAvg = centerSum / centerCount;
  final surroundAvg = surroundSum / surroundCount;

  for (var y = centerTop; y < centerBottom; y += step) {
    final rowStart = y * rowStride;
    for (var x = centerLeft; x < centerRight; x += step) {
      final index = rowStart + x;
      if (index < 0 || index >= bytes.length) continue;
      final diff = bytes[index] - centerAvg;
      centerVariance += diff * diff;
    }
  }
  centerVariance /= centerCount;

  final contrast = (centerAvg - surroundAvg).abs() / 255;
  final texture = (centerVariance / 6500).clamp(0.0, 1.0);
  final score = (contrast * 0.55 + texture * 0.45).clamp(0.0, 1.0);

  if (score < 0.50) return null;

  final distance = (4.5 - score * 3.2).clamp(0.8, 4.0);
    return null;
}
