import 'package:geolocator/geolocator.dart';

import '../models/walking_route.dart';

/// Spoken turn type derived from the pedestrian route.
enum TurnInstruction {
  continueStraight,
  slightLeft,
  turnLeft,
  sharpLeft,
  slightRight,
  turnRight,
  sharpRight,
}

/// A voice maneuver anchored to the same [WalkingRoute] used for AR navigation.
class RouteVoiceManeuver {
  const RouteVoiceManeuver({
    required this.stepIndex,
    required this.routeIndex,
    required this.latitude,
    required this.longitude,
    required this.instruction,
    required this.isTurn,
  });

  /// Index in [WalkingRoute.steps] from the pathfinding service.
  final int stepIndex;

  /// Nearest index in [WalkingRoute.points] on the displayed polyline.
  final int routeIndex;
  final double latitude;
  final double longitude;
  final TurnInstruction instruction;

  /// Whether this step should trigger 50 m / 20 m / now turn prompts.
  final bool isTurn;
}

/// Builds voice maneuvers from the pedestrian route returned by pathfinding.
class TurnInstructionGenerator {
  const TurnInstructionGenerator();

  TurnInstruction classifyBearingDelta(double deltaDegrees) {
    final delta = _normalizeDelta(deltaDegrees);
    if (delta.abs() < 15) return TurnInstruction.continueStraight;
    if (delta >= 15 && delta < 45) return TurnInstruction.slightRight;
    if (delta >= 45 && delta < 120) return TurnInstruction.turnRight;
    if (delta >= 120) return TurnInstruction.sharpRight;
    if (delta <= -15 && delta > -45) return TurnInstruction.slightLeft;
    if (delta <= -45 && delta > -120) return TurnInstruction.turnLeft;
    return TurnInstruction.sharpLeft;
  }

  /// Uses OSRM/pathfinding [WalkStep] maneuvers on the displayed polyline.
  List<RouteVoiceManeuver> generateFromWalkRoute(WalkingRoute route) {
    if (route.steps.isEmpty || route.points.isEmpty) return const [];

    final maneuvers = <RouteVoiceManeuver>[];
    for (var i = 0; i < route.steps.length; i++) {
      final step = route.steps[i];
      if (step.maneuverType == 'arrive') continue;

      final instruction = instructionFromWalkStep(step);
      final isTurn = _isTurnManeuver(step);

      maneuvers.add(
        RouteVoiceManeuver(
          stepIndex: i,
          routeIndex: _nearestPolylineIndex(
            route.points,
            step.latitude,
            step.longitude,
          ),
          latitude: step.latitude,
          longitude: step.longitude,
          instruction: instruction,
          isTurn: isTurn,
        ),
      );
    }

    return maneuvers;
  }

  TurnInstruction instructionFromWalkStep(WalkStep step) {
    final modifier = step.maneuverModifier;
    if (modifier.contains('sharp left')) return TurnInstruction.sharpLeft;
    if (modifier.contains('sharp right')) return TurnInstruction.sharpRight;
    if (modifier.contains('slight left')) return TurnInstruction.slightLeft;
    if (modifier.contains('slight right')) return TurnInstruction.slightRight;
    if (modifier.contains('left')) return TurnInstruction.turnLeft;
    if (modifier.contains('right')) return TurnInstruction.turnRight;
    if (modifier == 'uturn') return TurnInstruction.sharpLeft;
    if (step.maneuverType == 'turn' ||
        step.maneuverType == 'fork' ||
        step.maneuverType == 'merge') {
      return TurnInstruction.turnLeft;
    }
    return TurnInstruction.continueStraight;
  }

  bool isStraightLeg(WalkStep step) {
    return step.maneuverType == 'depart' ||
        step.maneuverModifier == 'straight' ||
        (! _isTurnManeuver(step) && step.maneuverType != 'arrive');
  }

  bool _isTurnManeuver(WalkStep step) {
    if (step.maneuverType == 'turn' ||
        step.maneuverType == 'fork' ||
        step.maneuverType == 'merge' ||
        step.maneuverType == 'roundabout' ||
        step.maneuverType == 'rotary') {
      return true;
    }
    final modifier = step.maneuverModifier;
    return modifier.contains('left') ||
        modifier.contains('right') ||
        modifier == 'uturn';
  }

  int _nearestPolylineIndex(
    List<RoutePoint> points,
    double latitude,
    double longitude,
  ) {
    var bestIndex = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final distance = Geolocator.distanceBetween(
        latitude,
        longitude,
        point.latitude,
        point.longitude,
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  double _normalizeDelta(double degrees) {
    var delta = degrees % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    return delta;
  }
}
