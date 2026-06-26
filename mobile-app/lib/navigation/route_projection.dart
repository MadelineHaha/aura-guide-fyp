import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

import '../models/walking_route.dart';

/// A location projected onto the OSRM walking-route polyline.
class RoutePolylineLocation {
  const RoutePolylineLocation({
    required this.segmentIndex,
    required this.segmentT,
    required this.vertexIndex,
    required this.latitude,
    required this.longitude,
    required this.distanceToUserMeters,
  });

  /// Index of the segment start vertex (`points[segmentIndex]` → `points[segmentIndex + 1]`).
  final int segmentIndex;

  /// Position along the segment, 0 = start vertex, 1 = end vertex.
  final double segmentT;
  final int vertexIndex;
  final double latitude;
  final double longitude;
  final double distanceToUserMeters;
}

/// Closest-point and look-ahead helpers for route-following AR navigation.
class RouteProjection {
  const RouteProjection._();

  static const defaultLookaheadMeters = 6.5;
  static const minLookaheadMeters = 5.0;
  static const maxLookaheadMeters = 8.0;

  /// Finds the closest point on the route polyline ahead of prior progress.
  static RoutePolylineLocation closestForward({
    required double userLat,
    required double userLng,
    required List<RoutePoint> points,
    required int progressSegmentIndex,
    int lookbackSegments = 10,
  }) {
    if (points.isEmpty) {
      return RoutePolylineLocation(
        segmentIndex: 0,
        segmentT: 0,
        vertexIndex: 0,
        latitude: userLat,
        longitude: userLng,
        distanceToUserMeters: 0,
      );
    }

    if (points.length == 1) {
      final distance = Geolocator.distanceBetween(
        userLat,
        userLng,
        points[0].latitude,
        points[0].longitude,
      );
      return RoutePolylineLocation(
        segmentIndex: 0,
        segmentT: 0,
        vertexIndex: 0,
        latitude: points[0].latitude,
        longitude: points[0].longitude,
        distanceToUserMeters: distance,
      );
    }

    final searchFrom = math.max(
      0,
      math.min(progressSegmentIndex - lookbackSegments, points.length - 2),
    );

    RoutePolylineLocation? best;
    for (var i = searchFrom; i < points.length - 1; i++) {
      final candidate = _closestOnSegment(
        userLat: userLat,
        userLng: userLng,
        start: points[i],
        end: points[i + 1],
        segmentIndex: i,
      );
      if (best == null ||
          candidate.distanceToUserMeters < best.distanceToUserMeters) {
        best = candidate;
      }
    }

    return best!;
  }

  /// Walks [aheadMeters] forward along the polyline from [from].
  static RoutePoint lookaheadPoint({
    required List<RoutePoint> points,
    required RoutePolylineLocation from,
    double aheadMeters = defaultLookaheadMeters,
  }) {
    aheadMeters = aheadMeters.clamp(minLookaheadMeters, maxLookaheadMeters);
    if (points.isEmpty) {
      return RoutePoint(latitude: from.latitude, longitude: from.longitude);
    }
    if (points.length == 1) return points.first;

    var remaining = aheadMeters;
    var segmentIndex = from.segmentIndex.clamp(0, points.length - 2);
    var segmentT = from.segmentT.clamp(0.0, 1.0);

    while (segmentIndex < points.length - 1 && remaining > 0) {
      final start = _interpolate(
        points[segmentIndex],
        points[segmentIndex + 1],
        segmentT,
      );
      final end = points[segmentIndex + 1];
      final segmentLength = Geolocator.distanceBetween(
        start.latitude,
        start.longitude,
        end.latitude,
        end.longitude,
      );

      if (segmentLength <= 0.01) {
        segmentIndex++;
        segmentT = 0;
        continue;
      }

      if (remaining <= segmentLength) {
        final ratio = remaining / segmentLength;
        final lat = start.latitude + (end.latitude - start.latitude) * ratio;
        final lng = start.longitude + (end.longitude - start.longitude) * ratio;
        return RoutePoint(latitude: lat, longitude: lng);
      }

      remaining -= segmentLength;
      segmentIndex++;
      segmentT = 0;
    }

    return points.last;
  }

  /// Remaining distance along the polyline from [from] to the route end.
  static double remainingDistance({
    required List<RoutePoint> points,
    required RoutePolylineLocation from,
  }) {
    if (points.isEmpty) return 0;
    if (points.length == 1) {
      return Geolocator.distanceBetween(
        from.latitude,
        from.longitude,
        points[0].latitude,
        points[0].longitude,
      );
    }

    var total = 0.0;
    final segmentIndex = from.segmentIndex.clamp(0, points.length - 2);
    final segmentT = from.segmentT.clamp(0.0, 1.0);

    final onSegment = _interpolate(
      points[segmentIndex],
      points[segmentIndex + 1],
      segmentT,
    );
    final segmentEnd = points[segmentIndex + 1];
    total += Geolocator.distanceBetween(
      onSegment.latitude,
      onSegment.longitude,
      segmentEnd.latitude,
      segmentEnd.longitude,
    );

    for (var i = segmentIndex + 1; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      total += Geolocator.distanceBetween(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
    }

    return total;
  }

  static RoutePolylineLocation _closestOnSegment({
    required double userLat,
    required double userLng,
    required RoutePoint start,
    required RoutePoint end,
    required int segmentIndex,
  }) {
    final refLat = userLat;
    final refLng = userLng;

    final ax = 0.0;
    final ay = 0.0;
    final bx = _metersX(start.latitude, start.longitude, refLat, refLng);
    final by = _metersY(start.latitude, start.longitude, refLat, refLng);
    final px = _metersX(userLat, userLng, refLat, refLng);
    final py = _metersY(userLat, userLng, refLat, refLng);

    final abx = bx - ax;
    final aby = by - ay;
    final abLen2 = abx * abx + aby * aby;
    final t = abLen2 <= 0.0001
        ? 0.0
        : ((px - ax) * abx + (py - ay) * aby) / abLen2;
    final clampedT = t.clamp(0.0, 1.0);

    final closestLat =
        start.latitude + (end.latitude - start.latitude) * clampedT;
    final closestLng =
        start.longitude + (end.longitude - start.longitude) * clampedT;
    final distance = Geolocator.distanceBetween(
      userLat,
      userLng,
      closestLat,
      closestLng,
    );

    return RoutePolylineLocation(
      segmentIndex: segmentIndex,
      segmentT: clampedT,
      vertexIndex: clampedT < 0.5 ? segmentIndex : segmentIndex + 1,
      latitude: closestLat,
      longitude: closestLng,
      distanceToUserMeters: distance,
    );
  }

  static RoutePoint _interpolate(RoutePoint start, RoutePoint end, double t) {
    return RoutePoint(
      latitude: start.latitude + (end.latitude - start.latitude) * t,
      longitude: start.longitude + (end.longitude - start.longitude) * t,
    );
  }

  static double _metersY(
    double lat,
    double lng,
    double refLat,
    double refLng,
  ) {
    return (lat - refLat) * 111320.0;
  }

  static double _metersX(
    double lat,
    double lng,
    double refLat,
    double refLng,
  ) {
    return (lng - refLng) *
        111320.0 *
        math.cos(refLat * math.pi / 180.0);
  }
}
