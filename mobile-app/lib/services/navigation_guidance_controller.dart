import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import '../models/navigation_destination.dart';
import '../models/walking_route.dart';
import '../navigation/route_projection.dart';
import 'navigation_announcement_manager.dart';
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
    NavigationAnnouncementManager? announcementManager,
  })  : _navigationService = navigationService ?? NavigationService.instance,
        _announcementManager =
            announcementManager ?? NavigationAnnouncementManager();

  final NavigationService _navigationService;
  final NavigationAnnouncementManager _announcementManager;
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
  int _routeProgressIndex = 0;
  int _routeProgressSegment = 0;
  int _lastClosestIndex = 0;
  RoutePolylineLocation? _routeProjection;
  RoutePoint? _lookaheadTarget;
  NavigationGuidanceState _state = NavigationGuidanceState.initial;

  static const _stepAdvanceMeters = 18;
  static const _routeLookbackSegments = 10;
  static const _directDistanceTrustMeters = 80;

  Stream<NavigationGuidanceState> get states => _stateController.stream;
  NavigationGuidanceState get currentState => _state;
  NavigationAnnouncementManager get announcementManager => _announcementManager;
  NavDestination? get destination => _destination;
  Position? get currentPosition => _currentPosition;
  bool get isWalkMode => _walkingRoute != null && !_walkingRoute!.isEmpty;
  List<RoutePoint> get routePoints => _walkingRoute?.points ?? const [];
  int get routeProgressIndex => _lastClosestIndex;
  RoutePolylineLocation? get routeProjection => _routeProjection;

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
    _routeProgressIndex = 0;
    _routeProgressSegment = 0;
    _lastClosestIndex = 0;
    _routeProjection = null;
    _lookaheadTarget = null;
    _announcementManager.prepareRoute(walkingRoute);
    unawaited(_announcementManager.initialize());
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
        distanceFilter: 1,
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
    final points = route.points;

    _routeProjection = RouteProjection.closestForward(
      userLat: position.latitude,
      userLng: position.longitude,
      points: points,
      progressSegmentIndex: _routeProgressSegment,
      lookbackSegments: _routeLookbackSegments,
    );

    final projection = _routeProjection!;
    if (projection.segmentIndex > _routeProgressSegment) {
      _routeProgressSegment = projection.segmentIndex;
    }
    if (projection.vertexIndex > _routeProgressIndex) {
      _routeProgressIndex = projection.vertexIndex;
    }
    _lastClosestIndex = projection.vertexIndex;

    _lookaheadTarget = RouteProjection.lookaheadPoint(
      points: points,
      from: projection,
      aheadMeters: RouteProjection.defaultLookaheadMeters,
    );

    _targetBearing = Geolocator.bearingBetween(
      position.latitude,
      position.longitude,
      _lookaheadTarget!.latitude,
      _lookaheadTarget!.longitude,
    );

    _advanceWalkStepIfNeeded(position, route);
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

  double _directDistanceToDestination(Position position, NavDestination dest) {
    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      dest.latitude!,
      dest.longitude!,
    );
  }

  double _remainingAlongRoute(Position position) {
    final route = _walkingRoute;
    final projection = _routeProjection;
    if (route == null || route.points.isEmpty || projection == null) return 0;

    return RouteProjection.remainingDistance(
      points: route.points,
      from: projection,
    );
  }

  double _displayWalkDistance(
    Position position,
    NavDestination dest,
    int closestIndex,
    double alongRoute,
  ) {
    final direct = _directDistanceToDestination(position, dest);
    if (direct <= _directDistanceTrustMeters) {
      _routeProgressIndex = math.max(
        _routeProgressIndex,
        (_walkingRoute?.points.length ?? 1) - 1,
      );
      return direct;
    }

    // Route progress can lag GPS (e.g. standing at destination while index is still
    // near the start). Trust straight-line distance when clearly closer.
    if (alongRoute - direct > 150) {
      return direct;
    }

    return alongRoute;
  }

  String _currentStepInstruction() {
    final steps = _walkingRoute?.steps ?? const [];
    if (steps.isEmpty) return 'Continue walking';

    final index = _currentStepIndex.clamp(0, steps.length - 1);
    return steps[index].instruction;
  }

  void _logNavigationDebug({
    required Position? position,
    required NavDestination dest,
    required bool walkMode,
    required double distance,
    int? closestIndex,
    int? targetIndex,
    RoutePoint? targetPoint,
    double? alongRoute,
    double? directToDestination,
  }) {
    final route = _walkingRoute;
    final routeEnd = route != null && route.points.isNotEmpty
        ? route.points.last
        : null;

    debugPrint(
      'NavGuidance DEBUG\n'
      '  CURRENT GPS: lat=${position?.latitude} lng=${position?.longitude}\n'
      '  FINAL DESTINATION: lat=${dest.latitude} lng=${dest.longitude} '
      'label=${dest.label}\n'
      '  ROUTE END: lat=${routeEnd?.latitude} lng=${routeEnd?.longitude} '
      'points=${route?.points.length ?? 0}\n'
      '  CLOSEST ROUTE INDEX: $closestIndex\n'
      '  ROUTE PROGRESS INDEX: $_routeProgressIndex\n'
      '  TARGET ROUTE INDEX: $targetIndex\n'
      '  TARGET ROUTE POINT: lat=${targetPoint?.latitude} '
      'lng=${targetPoint?.longitude}\n'
      '  DISTANCE ALONG ROUTE: ${alongRoute?.toStringAsFixed(1)}m\n'
      '  DISTANCE TO FINAL DESTINATION: '
      '${directToDestination?.toStringAsFixed(1)}m\n'
      '  DISPLAYED DISTANCE: ${distance.toStringAsFixed(1)}m '
      'walkMode=$walkMode',
    );
  }

  void _publish() {
    final dest = _destination;
    if (dest == null || !dest.hasCoordinates) return;

    final position = _currentPosition;
    final walkMode = isWalkMode;
    final stepInstruction =
        walkMode ? _currentStepInstruction() : '';

    double? alongRoute;
    double? directToDestination;
    int? closestIndex;
    RoutePoint? targetPoint;

    final distance = position == null
        ? 0.0
        : walkMode
            ? () {
                directToDestination =
                    _directDistanceToDestination(position, dest);
                closestIndex = _lastClosestIndex;
                targetPoint = _lookaheadTarget;
                alongRoute = _remainingAlongRoute(position);
                return _displayWalkDistance(
                  position,
                  dest,
                  closestIndex!,
                  alongRoute!,
                );
              }()
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

    if (walkMode) {
      _logNavigationDebug(
        position: position,
        dest: dest,
        walkMode: walkMode,
        distance: distance,
        closestIndex: closestIndex,
        targetIndex: _routeProjection?.segmentIndex,
        targetPoint: targetPoint,
        alongRoute: alongRoute,
        directToDestination: directToDestination,
      );
    } else {
      debugPrint(
        'NavGuidance DEBUG\n'
        '  CURRENT GPS: lat=${position?.latitude} lng=${position?.longitude}\n'
        '  FINAL DESTINATION: lat=${dest.latitude} lng=${dest.longitude}\n'
        '  DISPLAYED DISTANCE: ${distance.toStringAsFixed(1)}m '
        'walkMode=false (straight-line bearing)',
      );
    }

    if (position != null) {
      unawaited(
        _announcementManager.updateNavigation(
          position: position,
          destination: dest,
          distanceRemaining: distance,
          closestRouteIndex: _lastClosestIndex,
          currentStepIndex: _currentStepIndex,
          walkMode: walkMode,
        ),
      );
    }

    final guidanceHint = position == null
        ? 'Acquiring GPS…'
        : walkMode
            ? stepInstruction
            : _navigationService.guidanceHint(turnDelta);

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
    await _announcementManager.stop();
    _destination = null;
    _walkingRoute = null;
    _currentPosition = null;
    _deviceHeading = 0;
    _targetBearing = 0;
    _hasCompass = false;
    _currentStepIndex = 0;
    _routeProgressIndex = 0;
    _routeProgressSegment = 0;
    _lastClosestIndex = 0;
    _routeProjection = null;
    _lookaheadTarget = null;
    _state = NavigationGuidanceState.initial;
  }

  Future<void> dispose() async {
    await stop();
    await _announcementManager.dispose();
    await _stateController.close();
  }
}
