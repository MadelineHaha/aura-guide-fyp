class RoutePoint {
  const RoutePoint({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class WalkStep {
  const WalkStep({
    required this.instruction,
    required this.latitude,
    required this.longitude,
    required this.distanceMeters,
  });

  final String instruction;
  final double latitude;
  final double longitude;
  final double distanceMeters;
}

/// Pedestrian route along streets and footpaths.
class WalkingRoute {
  const WalkingRoute({
    required this.points,
    required this.steps,
    required this.totalDistanceMeters,
  });

  final List<RoutePoint> points;
  final List<WalkStep> steps;
  final double totalDistanceMeters;

  bool get isEmpty => points.isEmpty;
}
