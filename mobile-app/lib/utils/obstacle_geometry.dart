import 'dart:math' as math;

import '../models/obstacle_bounds.dart';

/// Letterbox transform used for YOLO inference (640×640).
class LetterboxMapping {
  const LetterboxMapping({
    required this.frameWidth,
    required this.frameHeight,
    required this.modelSize,
    required this.scale,
    required this.scaledW,
    required this.scaledH,
    required this.padX,
    required this.padY,
  });

  final int frameWidth;
  final int frameHeight;
  final int modelSize;
  final double scale;
  final int scaledW;
  final int scaledH;
  final int padX;
  final int padY;

  factory LetterboxMapping.fromFrame({
    required int frameWidth,
    required int frameHeight,
    required int modelSize,
  }) {
    final scale = math.min(modelSize / frameWidth, modelSize / frameHeight);
    final scaledW = math.max(1, (frameWidth * scale).round());
    final scaledH = math.max(1, (frameHeight * scale).round());
    final padX = (modelSize - scaledW) ~/ 2;
    final padY = (modelSize - scaledH) ~/ 2;
    return LetterboxMapping(
      frameWidth: frameWidth,
      frameHeight: frameHeight,
      modelSize: modelSize,
      scale: scale,
      scaledW: scaledW,
      scaledH: scaledH,
      padX: padX,
      padY: padY,
    );
  }

  ObstacleBounds? unmapBox({
    required double cx,
    required double cy,
    required double w,
    required double h,
  }) {
    final model = modelSize.toDouble();
    var leftPx = (cx - w / 2) * model;
    var topPx = (cy - h / 2) * model;
    var rightPx = (cx + w / 2) * model;
    var bottomPx = (cy + h / 2) * model;

    final contentLeft = padX.toDouble();
    final contentTop = padY.toDouble();
    final contentRight = padX + scaledW.toDouble();
    final contentBottom = padY + scaledH.toDouble();

    final overlap = _overlapArea(
      leftPx,
      topPx,
      rightPx,
      bottomPx,
      contentLeft,
      contentTop,
      contentRight,
      contentBottom,
    );
    final boxArea = math.max(1.0, (rightPx - leftPx) * (bottomPx - topPx));
    if (overlap / boxArea < 0.45) return null;

    var left = (leftPx - padX) / scaledW;
    var top = (topPx - padY) / scaledH;
    var right = (rightPx - padX) / scaledW;
    var bottom = (bottomPx - padY) / scaledH;

    left = left.clamp(0.0, 1.0);
    top = top.clamp(0.0, 1.0);
    right = right.clamp(0.0, 1.0);
    bottom = bottom.clamp(0.0, 1.0);

    final width = right - left;
    final height = bottom - top;
    if (width < 0.035 || height < 0.035) return null;

    return ObstacleBounds(
      left: left,
      top: top,
      width: width,
      height: height,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
    );
  }

  double estimateDistanceMeters({
    required int classId,
    required double boxHeightNorm,
    double verticalFovDegrees = 64,
  }) {
    final realHeight = _classRealHeightMeters(classId);
    // YOLO boxes often under-estimate full object height (e.g. torso-only person).
    final effectiveHeightPx =
        boxHeightNorm * frameHeight * _boxHeightScale(classId);
    if (effectiveHeightPx < 6) return 12;

    final vfovRad = verticalFovDegrees * math.pi / 180;
    final focalLengthPx = frameHeight / (2 * math.tan(vfovRad / 2));
    final rawDistance = (realHeight * focalLengthPx) / effectiveHeightPx;
    final calibrated = rawDistance * _distanceCalibration(classId);
    return calibrated.clamp(0.3, 20.0);
  }
}

double _overlapArea(
  double aLeft,
  double aTop,
  double aRight,
  double aBottom,
  double bLeft,
  double bTop,
  double bRight,
  double bBottom,
) {
  final interLeft = math.max(aLeft, bLeft);
  final interTop = math.max(aTop, bTop);
  final interRight = math.min(aRight, bRight);
  final interBottom = math.min(aBottom, bBottom);
  final w = math.max(0.0, interRight - interLeft);
  final h = math.max(0.0, interBottom - interTop);
  return w * h;
}

double _classRealHeightMeters(int classId) {
  switch (classId) {
    case 0: // Bike
      return 1.1;
    case 2: // Car
      return 1.45;
    case 3: // Person
      return 1.65;
    case 4: // Stairs
      return 1.0;
    case 8: // Motorcycle
      return 1.2;
    case 10: // Dog
      return 0.55;
    case 15: // Truck
      return 2.4;
    case 16: // Bus
      return 2.8;
    case 17: // Bench
      return 0.85;
    case 18: // Traffic Cone
      return 0.75;
    case 19: // Fire hydrant
      return 0.9;
    case 23: // Chair
      return 0.9;
    case 24: // Bicycle Rack
      return 1.0;
    default:
      return 1.2;
  }
}

/// Compensates for detection boxes that are smaller than the full object.
double _boxHeightScale(int classId) {
  switch (classId) {
    case 3: // Person — boxes often miss head/feet
      return 1.28;
    case 10: // Dog
      return 1.3;
    case 2: // Car
    case 15: // Truck
    case 16: // Bus
      return 1.2;
    default:
      return 1.15;
  }
}

/// Empirical scale tuned for typical phone rear-camera video streams.
double _distanceCalibration(int classId) {
  switch (classId) {
    case 3: // Person
      return 0.9;
    default:
      return 0.92;
  }
}
