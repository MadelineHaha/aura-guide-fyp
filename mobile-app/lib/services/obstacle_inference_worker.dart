import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'obstacle_detection_service.dart';
import 'obstacle_frame_packet.dart';
import '../models/obstacle_bounds.dart';
import '../utils/obstacle_geometry.dart';

/// Runs YOLO inference off the UI thread while keeping correct output parsing.
class ObstacleInferenceWorker {
  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  List<int>? _inputShape;
  List<int>? _outputShape;
  var _inputSize = 640;
  var _anchorCount = 8400;
  var _inputLength = 0;
  var _outputLength = 0;
  List<double>? _outputBuffer;
  dynamic _reshapedOutput;

  Future<bool> start() async {
    if (_interpreter != null) return true;

    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await _loadInterpreter(options);
      _isolateInterpreter = await IsolateInterpreter.create(
        address: _interpreter!.address,
        debugName: 'ObstacleYoloWorker',
      );

      _inputShape = _interpreter!.getInputTensor(0).shape;
      _outputShape = _interpreter!.getOutputTensor(0).shape;
      _inputSize = _resolveInputSize(_inputShape!);
      _anchorCount = _resolveAnchorCount(_outputShape!);
      _inputLength = _inputShape!.reduce((a, b) => a * b);
      _outputLength = _outputShape!.reduce((a, b) => a * b);

      debugPrint(
        'ObstacleInferenceWorker ready input=$_inputShape output=$_outputShape',
      );
      return true;
    } catch (error, stack) {
      debugPrint('ObstacleInferenceWorker start failed: $error\n$stack');
      await dispose();
      return false;
    }
  }

  Future<Interpreter> _loadInterpreter(InterpreterOptions options) async {
    try {
      return await Interpreter.fromAsset(
        'assets/ai/obstacle_model.tflite',
        options: options,
      );
    } catch (assetError) {
      debugPrint('Obstacle model fromAsset failed, trying temp file: $assetError');
      final bytes = await rootBundle.load('assets/ai/obstacle_model.tflite');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/obstacle_model.tflite');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      return Interpreter.fromFile(file, options: options);
    }
  }

  Future<ObstacleDetectionResult?> detectFromCamera(CameraImage image) async {
    final isolateInterpreter = _isolateInterpreter;
    final inputShape = _inputShape;
    final outputShape = _outputShape;

    if (isolateInterpreter == null ||
        inputShape == null ||
        outputShape == null ||
        image.planes.isEmpty) {
      return null;
    }

    try {
      final inputFlat = await ObstacleFramePacket.toModelInputAsync(
        image,
        inputSize: _inputSize,
        inputLength: _inputLength,
      );
      final frame = ObstacleFramePacket.inferenceFrameSize(
        image.width,
        image.height,
      );
      return _runInference(
        isolateInterpreter,
        inputShape,
        outputShape,
        inputFlat,
        frameWidth: frame.width,
        frameHeight: frame.height,
      );
    } catch (error, stack) {
      debugPrint('ObstacleInferenceWorker detectFromCamera failed: $error\n$stack');
      return null;
    }
  }

  Future<ObstacleDetectionResult?> detect(ObstacleFramePacket packet) async {
    final isolateInterpreter = _isolateInterpreter;
    final inputShape = _inputShape;
    final outputShape = _outputShape;

    if (isolateInterpreter == null ||
        inputShape == null ||
        outputShape == null ||
        packet.width <= 0 ||
        packet.height <= 0) {
      return null;
    }

    try {
      final inputFlat = await compute(
        _fillInputIsolate,
        _FillInputJob(
          packetMessage: packet.toIsolateMessage(),
          inputSize: _inputSize,
          inputLength: _inputLength,
        ),
      );
      return _runInference(
        isolateInterpreter,
        inputShape,
        outputShape,
        inputFlat,
        frameWidth: packet.width,
        frameHeight: packet.height,
      );
    } catch (error, stack) {
      debugPrint('ObstacleInferenceWorker detect failed: $error\n$stack');
      return null;
    }
  }

  Future<ObstacleDetectionResult?> _runInference(
    IsolateInterpreter isolateInterpreter,
    List<int> inputShape,
    List<int> outputShape,
    Float32List inputFlat, {
    required int frameWidth,
    required int frameHeight,
  }) async {
    try {
      final input = inputFlat.reshape(inputShape);
      _outputBuffer ??= List<double>.filled(_outputLength, 0);
      _reshapedOutput ??= _outputBuffer!.reshape(outputShape);
      final output = _reshapedOutput;

      if (isolateInterpreter.state == IsolateInterpreterState.loading) {
        await isolateInterpreter.stateChanges.firstWhere(
          (state) => state == IsolateInterpreterState.idle,
        );
      }
      await isolateInterpreter.run(input, output);

      return _parseOutput(
        output,
        anchorCount: _anchorCount,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        modelSize: _inputSize,
      );
    } catch (error, stack) {
      debugPrint('ObstacleInferenceWorker run failed: $error\n$stack');
      return null;
    }
  }

  Future<void> warmUpInference() async {
    final isolateInterpreter = _isolateInterpreter;
    final inputShape = _inputShape;
    final outputShape = _outputShape;
    if (isolateInterpreter == null ||
        inputShape == null ||
        outputShape == null ||
        _inputLength <= 0) {
      return;
    }

    try {
      const padValue = 114 / 255.0;
      final inputFlat = Float32List(_inputLength)..fillRange(0, _inputLength, padValue);
      _outputBuffer ??= List<double>.filled(_outputLength, 0);
      _reshapedOutput ??= _outputBuffer!.reshape(outputShape);
      await _runInference(
        isolateInterpreter,
        inputShape,
        outputShape,
        inputFlat,
        frameWidth: _inputSize,
        frameHeight: _inputSize,
      );
    } catch (error) {
      debugPrint('ObstacleInferenceWorker warmUpInference failed: $error');
    }
  }

  Future<void> dispose() async {
    await _isolateInterpreter?.close();
    _isolateInterpreter = null;
    _interpreter?.close();
    _interpreter = null;
    _inputShape = null;
    _outputShape = null;
    _outputBuffer = null;
    _reshapedOutput = null;
  }
}

class _FillInputJob {
  const _FillInputJob({
    required this.packetMessage,
    required this.inputSize,
    required this.inputLength,
  });

  final List<dynamic> packetMessage;
  final int inputSize;
  final int inputLength;
}

Float32List _fillInputIsolate(_FillInputJob job) {
  final packet = ObstacleFramePacket.fromIsolateMessage(job.packetMessage);
  final buffer = Float32List(job.inputLength);
  ObstacleFramePacket.fillYoloInput(packet, buffer, job.inputSize);
  return buffer;
}

class ObstacleDetectionResult {
  const ObstacleDetectionResult({
    required this.label,
    required this.distanceMeters,
    required this.confidence,
    required this.classId,
    required this.topLabel,
    required this.topScore,
    this.bounds,
  });

  final String label;
  final double distanceMeters;
  final double confidence;
  final int classId;
  final String topLabel;
  final double topScore;
  final ObstacleBounds? bounds;

  ObstacleDetection toDetection() {
    return ObstacleDetection(
      label: label,
      distanceMeters: distanceMeters,
      confidence: confidence,
      classId: classId,
      bounds: bounds,
    );
  }

  Map<String, dynamic> toMap() => {
        'label': label,
        'distanceMeters': distanceMeters,
        'confidence': confidence,
        'classId': classId,
        'topLabel': topLabel,
        'topScore': topScore,
        if (bounds != null) ...bounds!.toMap(),
      };

  factory ObstacleDetectionResult.fromMap(Map<String, dynamic> map) {
    final hasBounds = map.containsKey('left') && map.containsKey('top');
    return ObstacleDetectionResult(
      label: map['label'] as String? ?? '',
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble() ?? 0,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      classId: map['classId'] as int? ?? -1,
      topLabel: map['topLabel'] as String? ?? '',
      topScore: (map['topScore'] as num?)?.toDouble() ?? 0,
      bounds: hasBounds ? ObstacleBounds.fromMap(map) : null,
    );
  }
}

int _resolveInputSize(List<int> shape) {
  if (shape.length == 4) {
    if (shape[3] == 3) return shape[1];
    if (shape[1] == 3) return shape[2];
  }
  return shape.length >= 2 ? shape[1] : 640;
}

int _resolveAnchorCount(List<int> shape) {
  if (shape.length == 3) {
    return shape[2] > shape[1] ? shape[2] : shape[1];
  }
  if (shape.length == 2) {
    return shape[1] > shape[0] ? shape[1] : shape[0];
  }
  return 8400;
}

double _readOutput(List output, int feature, int anchor, int anchorCount) {
  // Output layout: [1, features, anchors] e.g. [1, 35, 8400]
  final batch = output[0];
  if (batch is List && batch.length > feature) {
    final featureRow = batch[feature];
    if (featureRow is List && anchor < featureRow.length) {
      return (featureRow[anchor] as num).toDouble();
    }
  }
  return 0;
}

/// Class names in training order (CombinedDataset / metadata.yaml).
const _yoloClassNames = <String>[
  'Bike',
  'Building',
  'Car',
  'Person',
  'Stairs',
  'Traffic sign',
  'Electrical Pole',
  'Road',
  'Motorcycle',
  'Dustbin',
  'Dog',
  'Manhole',
  'Tree',
  'Guard rail',
  'Pedestrian crosswalk',
  'Truck',
  'Bus',
  'Bench',
  'Traffic Cone',
  'Fire hydrant',
  'Teraffic Barrel', // spelling matches training export
  'Plant Pot',
  'Electrical Box',
  'Chair',
  'Bicycle Rack',
  'door',
  'elevator',
  'escalator',
  'lift_icon',
  'surau_icon',
  'toilet_icon',
];

/// Background classes — not useful for obstacle alerts.
const _excludedClassIds = <int>{1, 5, 6, 7, 13, 14};

class _ParsedBox {
  const _ParsedBox({
    required this.classId,
    required this.score,
    required this.cx,
    required this.cy,
    required this.w,
    required this.h,
  });

  final int classId;
  final double score;
  final double cx;
  final double cy;
  final double w;
  final double h;
}

double _boxIoU(_ParsedBox a, _ParsedBox b) {
  final aLeft = a.cx - a.w / 2;
  final aTop = a.cy - a.h / 2;
  final aRight = a.cx + a.w / 2;
  final aBottom = a.cy + a.h / 2;
  final bLeft = b.cx - b.w / 2;
  final bTop = b.cy - b.h / 2;
  final bRight = b.cx + b.w / 2;
  final bBottom = b.cy + b.h / 2;

  final interLeft = math.max(aLeft, bLeft);
  final interTop = math.max(aTop, bTop);
  final interRight = math.min(aRight, bRight);
  final interBottom = math.min(aBottom, bBottom);

  final interW = math.max(0.0, interRight - interLeft);
  final interH = math.max(0.0, interBottom - interTop);
  final intersection = interW * interH;
  if (intersection <= 0) return 0;

  final union = a.w * a.h + b.w * b.h - intersection;
  return union <= 0 ? 0 : intersection / union;
}

List<_ParsedBox> _nonMaxSuppression(
  List<_ParsedBox> boxes, {
  double iouThreshold = 0.45,
  int maxDetections = 50,
}) {
  if (boxes.isEmpty) return const [];

  final sorted = List<_ParsedBox>.from(boxes)
    ..sort((a, b) => b.score.compareTo(a.score));

  final kept = <_ParsedBox>[];
    for (final candidate in sorted) {
    var overlaps = false;
    for (final existing in kept) {
      if (candidate.classId == existing.classId &&
          _boxIoU(candidate, existing) > iouThreshold) {
        overlaps = true;
        break;
      }
    }
    if (!overlaps) {
      kept.add(candidate);
      if (kept.length >= maxDetections) break;
    }
  }
  return kept;
}

ObstacleDetectionResult? _parseOutput(
  List output, {
  required int anchorCount,
  required int frameWidth,
  required int frameHeight,
  required int modelSize,
}) {
  const numClasses = 31;

  double confidenceThresholdForClass(int classId) {
    switch (classId) {
      case 3: // Person
      case 8: // Dog
      case 23: // Chair
      case 17: // Bench
        return 0.30;
      default:
        return 0.34;
    }
  }

  if (frameWidth <= 0 || frameHeight <= 0) {
    return null;
  }

  final letterbox = LetterboxMapping.fromFrame(
    frameWidth: frameWidth,
    frameHeight: frameHeight,
    modelSize: modelSize,
  );

  final candidates = <_ParsedBox>[];
  var debugBestScore = 0.0;
  var debugBestClass = -1;

  for (var anchor = 0; anchor < anchorCount; anchor++) {
    var bestClass = -1;
    var bestScore = 0.0;

    for (var classIndex = 0; classIndex < numClasses; classIndex++) {
      final classScore =
          _readOutput(output, 4 + classIndex, anchor, anchorCount);
      if (classScore > bestScore) {
        bestScore = classScore;
        bestClass = classIndex;
      }
    }

    if (bestScore > debugBestScore) {
      debugBestScore = bestScore;
      debugBestClass = bestClass;
    }

    if (bestClass < 0 || bestScore < confidenceThresholdForClass(bestClass)) {
      continue;
    }
    if (_excludedClassIds.contains(bestClass)) continue;

    final cx = _readOutput(output, 0, anchor, anchorCount);
    final cy = _readOutput(output, 1, anchor, anchorCount);
    final boxW = _readOutput(output, 2, anchor, anchorCount).abs();
    final boxH = _readOutput(output, 3, anchor, anchorCount).abs();
    if (boxW <= 0.01 || boxH <= 0.01) continue;

    candidates.add(
      _ParsedBox(
        classId: bestClass,
        score: bestScore,
        cx: cx,
        cy: cy,
        w: boxW,
        h: boxH,
      ),
    );
  }

  final topLabel = debugBestClass >= 0 && debugBestClass < _yoloClassNames.length
      ? _yoloClassNames[debugBestClass]
      : '';

  final nmsBoxes = _nonMaxSuppression(candidates, iouThreshold: 0.42);
  if (nmsBoxes.isEmpty) {
    return ObstacleDetectionResult(
      label: '',
      distanceMeters: 0,
      confidence: 0,
      classId: -1,
      topLabel: topLabel,
      topScore: debugBestScore,
    );
  }

  _ParsedBox? best;
  var bestWeighted = -1.0;
  for (final box in nmsBoxes) {
    final centerDistance = math.sqrt(
      math.pow(box.cx - 0.5, 2) + math.pow(box.cy - 0.5, 2),
    );
    final priorityBoost = box.classId == 3 ? 1.1 : 1.0;
    final weighted = box.score *
        (1.15 - centerDistance.clamp(0.0, 0.85)) *
        priorityBoost;
    if (weighted > bestWeighted) {
      bestWeighted = weighted;
      best = box;
    }
  }

  final winner = best!;
  final bounds = letterbox.unmapBox(
    cx: winner.cx,
    cy: winner.cy,
    w: winner.w,
    h: winner.h,
  );
  if (bounds == null) {
    return ObstacleDetectionResult(
      label: '',
      distanceMeters: 0,
      confidence: 0,
      classId: -1,
      topLabel: topLabel,
      topScore: debugBestScore,
    );
  }

  final label = winner.classId < _yoloClassNames.length
      ? _yoloClassNames[winner.classId]
      : 'Object';
  final distance = letterbox.estimateDistanceMeters(
    classId: winner.classId,
    boxHeightNorm: bounds.height,
  );

  return ObstacleDetectionResult(
    label: label,
    distanceMeters: double.parse(distance.toStringAsFixed(1)),
    confidence: winner.score,
    classId: winner.classId,
    topLabel: topLabel,
    topScore: debugBestScore,
    bounds: bounds,
  );
}
