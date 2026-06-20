import 'dart:async';

import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import '../models/navigation_destination.dart';
import '../models/walking_route.dart';
import 'app_settings_service.dart';
import 'navigation_service.dart';

class NavigationGuidanceState {
  const NavigationGuidanceState({
    required this.deviceHeading,
    required this.targetBearing,
    required this.turnDelta,
    required this.distanceMeters,
    required this.guidanceHint,
    required this.hasGpsFix,
    required this.hasCompass,
    required this.walkMode,
    required this.stepInstruction,
  });

  final double deviceHeading;
  final double targetBearing;
  final double turnDelta;
  final double distanceMeters;
  final String guidanceHint;
  final bool hasGpsFix;
  final bool hasCompass;
  final bool walkMode;
  final String stepInstruction;

  static const initial = NavigationGuidanceState(
    deviceHeading: 0,
    targetBearing: 0,
    turnDelta: 0,
    distanceMeters: 0,
    guidanceHint: 'Acquiring GPS…',
    hasGpsFix: false,
    hasCompass: false,
    walkMode: true,
    stepInstruction: '',
  );
}

/// Tracks GPS position and compass heading along a walking route.
class NavigationGuidanceController {
  NavigationGuidanceController({
    NavigationService? navigationService,
  }) : _navigationService = navigationService ?? NavigationService.instance;

  final NavigationService _navigationService;
  final _stateController = StreamController<NavigationGuidanceState>.broadcast();

  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<Position>? _positionSub;

  NavDestination? _destination;
  WalkingRoute? _walkingRoute;
  Position? _currentPosition;
  double _deviceHeading = 0;
  double _targetBearing = 0;
  bool _hasCompass = false;
  int _currentStepIndex = 0;
  String? _lastSpokenInstruction;
  NavigationGuidanceState _state = NavigationGuidanceState.initial;

  static const _stepAdvanceMeters = 18;
  static const _lookaheadPoints = 4;

  Stream<NavigationGuidanceState> get states => _stateController.stream;
  NavigationGuidanceState get currentState => _state;
  NavDestination? get destination => _destination;
  Position? get currentPosition => _currentPosition;
  bool get isWalkMode => _walkingRoute != null && !_walkingRoute!.isEmpty;

  Future<void> start(
    NavDestination destination, {
    WalkingRoute? walkingRoute,
  }) async {
    if (!destination.hasCoordinates) {
      throw StateError('Destination coordinates are required.');
    }

    await stop();
    _destination = destination;
    _walkingRoute = walkingRoute;
    _currentStepIndex = 0;
    _lastSpokenInstruction = null;
    _emit(NavigationGuidanceState.initial);

    _compassSub = FlutterCompass.events?.listen((event) {
      final heading = event.heading;
      if (heading == null) return;
      _hasCompass = true;
      _deviceHeading = heading;
      _publish();
    });

    unawaited(
      _navigationService.currentPosition().then(_applyPosition).catchError((_) {}),
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3,
      ),
    ).listen(_applyPosition);
  }

  void _applyPosition(Position position) {
    final dest = _destination;
    if (dest == null || !dest.hasCoordinates) return;

    _currentPosition = position;

    if (isWalkMode) {
      _updateWalkProgress(position, dest);
    } else {
      _updateDirectProgress(position, dest);
    }

    _publish();
  }

  void _updateDirectProgress(Position position, NavDestination dest) {
    _targetBearing = _navigationService.bearingToDestination(
      from: position,
      destLat: dest.latitude!,
      destLng: dest.longitude!,
    );
  }

  void _updateWalkProgress(Position position, NavDestination dest) {
    final route = _walkingRoute!;
    final closestIndex = _closestPointIndex(position, route.points);
    final targetIndex = (closestIndex + _lookaheadPoints).clamp(
      0,
      route.points.length - 1,
    );
    final target = route.points[targetIndex];

    _targetBearing = Geolocator.bearingBetween(
      position.latitude,
      position.longitude,
      target.latitude,
      target.longitude,
    );

    _advanceWalkStepIfNeeded(position, route);
  }

  int _closestPointIndex(Position position, List<RoutePoint> points) {
    var bestIndex = 0;
    var bestDistance = double.infinity;

    for (var i = 0; i < points.length; i++) {
      final point = points[i];
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
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

  void _advanceWalkStepIfNeeded(Position position, WalkingRoute route) {
    final steps = route.steps;
    if (steps.isEmpty) return;

    while (_currentStepIndex < steps.length - 1) {
      final step = steps[_currentStepIndex];
      final distanceToStep = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        step.latitude,
        step.longitude,
      );
      if (distanceToStep > _stepAdvanceMeters) break;
      _currentStepIndex++;
    }
  }

  double _remainingWalkDistance(Position position) {
    final route = _walkingRoute;
    if (route == null || route.points.isEmpty) return 0;

    final closestIndex = _closestPointIndex(position, route.points);
    var remaining = 0.0;
    for (var i = closestIndex; i < route.points.length - 1; i++) {
      final a = route.points[i];
      final b = route.points[i + 1];
      remaining += Geolocator.distanceBetween(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
    }
    return remaining;
  }

  String _currentStepInstruction() {
    final steps = _walkingRoute?.steps ?? const [];
    if (steps.isEmpty) return 'Continue walking';

    final index = _currentStepIndex.clamp(0, steps.length - 1);
    return steps[index].instruction;
  }

  void _publish() {
    final dest = _destination;
    if (dest == null || !dest.hasCoordinates) return;

    final position = _currentPosition;
    final walkMode = isWalkMode;
    final stepInstruction =
        walkMode ? _currentStepInstruction() : '';

    final distance = position == null
        ? 0.0
        : walkMode
            ? _remainingWalkDistance(position)
            : Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                dest.latitude!,
                dest.longitude!,
              );

    final turnDelta = _navigationService.shortestTurn(
      _targetBearing,
      _deviceHeading,
    );

    final guidanceHint = position == null
        ? 'Acquiring GPS…'
        : walkMode
            ? stepInstruction
            : _navigationService.guidanceHint(turnDelta);

    if (walkMode && stepInstruction.isNotEmpty) {
      unawaited(_announceStepIfNeeded(stepInstruction, distance));
    } else if (distance <= 15 && position != null) {
      unawaited(_announceStepIfNeeded(
        AppSettingsService.instance.localized('arrivedAtDestination'),
        distance,
      ));
    }

    _state = NavigationGuidanceState(
      deviceHeading: _deviceHeading,
      targetBearing: _targetBearing,
      turnDelta: turnDelta,
      distanceMeters: distance,
      guidanceHint: guidanceHint,
      hasGpsFix: position != null,
      hasCompass: _hasCompass,
      walkMode: walkMode,
      stepInstruction: stepInstruction,
    );
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  Future<void> _announceStepIfNeeded(String instruction, double distance) async {
    if (instruction.isEmpty || instruction == _lastSpokenInstruction) return;
    if (instruction ==
            AppSettingsService.instance.localized('arrivedAtDestination') &&
        distance > 20) {
      return;
    }

    _lastSpokenInstruction = instruction;
    await AppSettingsService.instance.speak(instruction);
  }

  void _emit(NavigationGuidanceState state) {
    _state = state;
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }

  Future<void> stop() async {
    await _compassSub?.cancel();
    await _positionSub?.cancel();
    _compassSub = null;
    _positionSub = null;
    _destination = null;
    _walkingRoute = null;
    _currentPosition = null;
    _deviceHeading = 0;
    _targetBearing = 0;
    _hasCompass = false;
    _currentStepIndex = 0;
    _lastSpokenInstruction = null;
    _state = NavigationGuidanceState.initial;
  }

  Future<void> dispose() async {
    await stop();
    await _stateController.close();
  }
}
