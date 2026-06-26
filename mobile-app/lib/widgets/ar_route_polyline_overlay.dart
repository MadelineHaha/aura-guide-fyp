import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/walking_route.dart';
import '../navigation/route_projection.dart';

/// Projects the OSRM walking route onto the camera view as a cyan polyline.
class ArRoutePolylineOverlay extends StatelessWidget {
  const ArRoutePolylineOverlay({
    super.key,
    required this.routePoints,
    required this.userLatitude,
    required this.userLongitude,
    required this.deviceHeading,
    this.routeStartIndex = 0,
    this.routeProjection,
    this.bottomInset = 112,
    this.maxDistanceMeters = 80,
    this.lineColor = const Color(0xFF63F7F2),
  });

  final List<RoutePoint> routePoints;
  final double? userLatitude;
  final double? userLongitude;
  final double deviceHeading;
  final int routeStartIndex;
  final RoutePolylineLocation? routeProjection;
  final double bottomInset;
  final double maxDistanceMeters;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    if (routePoints.length < 2 ||
        userLatitude == null ||
        userLongitude == null) {
      return const SizedBox.shrink();
    }

    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final reservedBottom = safeBottom + bottomInset;

    return IgnorePointer(
      child: CustomPaint(
        painter: _ArRoutePolylinePainter(
          routePoints: routePoints,
          userLatitude: userLatitude!,
          userLongitude: userLongitude!,
          deviceHeading: deviceHeading,
          routeStartIndex: routeStartIndex,
          routeProjection: routeProjection,
          bottomInset: reservedBottom,
          maxDistanceMeters: maxDistanceMeters,
          lineColor: lineColor,
        ),
      ),
    );
  }
}

class _ArRoutePolylinePainter extends CustomPainter {
  _ArRoutePolylinePainter({
    required this.routePoints,
    required this.userLatitude,
    required this.userLongitude,
    required this.deviceHeading,
    required this.routeStartIndex,
    required this.routeProjection,
    required this.bottomInset,
    required this.maxDistanceMeters,
    required this.lineColor,
  });

  final List<RoutePoint> routePoints;
  final double userLatitude;
  final double userLongitude;
  final double deviceHeading;
  final int routeStartIndex;
  final RoutePolylineLocation? routeProjection;
  final double bottomInset;
  final double maxDistanceMeters;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final anchorY = size.height - bottomInset + 8;
    final anchorX = size.width * 0.5;
    final metersToPx = size.height / 42.0;

    final start = routeProjection?.segmentIndex ??
        routeStartIndex.clamp(0, routePoints.length - 1);
    final path = Path();
    var hasPoint = false;

    if (routeProjection != null) {
      final projected = Offset(
        routeProjection!.latitude,
        routeProjection!.longitude,
      );
      final screen = _projectToScreen(
        point: RoutePoint(
          latitude: projected.dx,
          longitude: projected.dy,
        ),
        size: size,
        anchorX: anchorX,
        anchorY: anchorY,
        metersToPx: metersToPx,
        minDistance: 0,
        minForward: 0,
      );
      if (screen != null) {
        path.moveTo(screen.dx, screen.dy);
        hasPoint = true;
      }
    }

    final vertexStart = routeProjection != null
        ? routeProjection!.segmentIndex + 1
        : start;
    for (var i = vertexStart; i < routePoints.length; i++) {
      final screen = _projectToScreen(
        point: routePoints[i],
        size: size,
        anchorX: anchorX,
        anchorY: anchorY,
        metersToPx: metersToPx,
      );
      if (screen == null) {
        if (hasPoint) break;
        continue;
      }

      if (!hasPoint) {
        path.moveTo(screen.dx, screen.dy);
        hasPoint = true;
      } else {
        path.lineTo(screen.dx, screen.dy);
      }
    }

    if (!hasPoint) return;

    final glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    final linePaint = Paint()
      ..color = lineColor.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final highlightPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(anchorX, anchorY),
        Offset(anchorX, anchorY - size.height * 0.45),
        [
          lineColor.withValues(alpha: 0.95),
          lineColor.withValues(alpha: 0.35),
        ],
      )
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);
    canvas.drawPath(path, highlightPaint);
  }

  Offset? _projectToScreen({
    required RoutePoint point,
    required Size size,
    required double anchorX,
    required double anchorY,
    required double metersToPx,
    double minDistance = 0.8,
    double minForward = 0.6,
  }) {
    final distance = Geolocator.distanceBetween(
      userLatitude,
      userLongitude,
      point.latitude,
      point.longitude,
    );
    if (distance < minDistance || distance > maxDistanceMeters) return null;

    final bearing = Geolocator.bearingBetween(
      userLatitude,
      userLongitude,
      point.latitude,
      point.longitude,
    );
    var relative = _normalizeDegrees(bearing - deviceHeading);
    if (relative.abs() > 78) return null;

    final radians = relative * math.pi / 180.0;
    final forward = math.cos(radians) * distance;
    if (forward < minForward) return null;

    final lateral = math.sin(radians) * distance;
    final x = anchorX + lateral * metersToPx * 0.95;
    final y = anchorY - forward * metersToPx * 1.05;

    if (x < -40 || x > size.width + 40) return null;
    if (y < size.height * 0.08 || y > anchorY + 24) return null;
    return Offset(x, y);
  }

  double _normalizeDegrees(double degrees) {
    var value = degrees % 360;
    if (value > 180) value -= 360;
    if (value < -180) value += 360;
    return value;
  }

  @override
  bool shouldRepaint(covariant _ArRoutePolylinePainter oldDelegate) {
    return oldDelegate.routePoints != routePoints ||
        oldDelegate.userLatitude != userLatitude ||
        oldDelegate.userLongitude != userLongitude ||
        oldDelegate.deviceHeading != deviceHeading ||
        oldDelegate.routeStartIndex != routeStartIndex ||
        oldDelegate.routeProjection != routeProjection ||
        oldDelegate.bottomInset != bottomInset;
  }
}
