import 'dart:async';

import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';

import '../models/navigation_destination.dart';
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
  });

  final double deviceHeading;
  final double targetBearing;
  final double turnDelta;
  final double distanceMeters;
  final String guidanceHint;
  final bool hasGpsFix;
  final bool hasCompass;

  static const initial = NavigationGuidanceState(
    deviceHeading: 0,
    targetBearing: 0,
    turnDelta: 0,
    distanceMeters: 0,
    guidanceHint: 'Acquiring GPS…',
    hasGpsFix: false,
    hasCompass: false,
  );
}

/// Tracks GPS position and compass heading toward a destination.
class NavigationGuidanceController {
  NavigationGuidanceController({
    NavigationService? navigationService,
  }) : _navigationService = navigationService ?? NavigationService();

  final NavigationService _navigationService;
  final _stateController = StreamController<NavigationGuidanceState>.broadcast();

  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<Position>? _positionSub;

  NavDestination? _destination;
  Position? _currentPosition;
  double _deviceHeading = 0;
  double _targetBearing = 0;
  bool _hasCompass = false;
  NavigationGuidanceState _state = NavigationGuidanceState.initial;

  Stream<NavigationGuidanceState> get states => _stateController.stream;
  NavigationGuidanceState get currentState => _state;
  NavDestination? get destination => _destination;
  Position? get currentPosition => _currentPosition;

  Future<void> start(NavDestination destination) async {
    if (!destination.hasCoordinates) {
      throw StateError('Destination coordinates are required.');
    }

    await stop();
    _destination = destination;
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
        distanceFilter: 2,
      ),
    ).listen(_applyPosition);
  }

  void _applyPosition(Position position) {
    final dest = _destination;
    if (dest == null || !dest.hasCoordinates) return;

    _currentPosition = position;
    _targetBearing = _navigationService.bearingToDestination(
      from: position,
      destLat: dest.latitude!,
      destLng: dest.longitude!,
    );
    _publish();
  }

  void _publish() {
    final dest = _destination;
    if (dest == null || !dest.hasCoordinates) return;

    final distance = _currentPosition == null
        ? 0.0
        : Geolocator.distanceBetween(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            dest.latitude!,
            dest.longitude!,
          );

    final turnDelta = _navigationService.shortestTurn(
      _targetBearing,
      _deviceHeading,
    );

    _state = NavigationGuidanceState(
      deviceHeading: _deviceHeading,
      targetBearing: _targetBearing,
      turnDelta: turnDelta,
      distanceMeters: distance,
      guidanceHint: _currentPosition == null
          ? 'Acquiring GPS…'
          : _navigationService.guidanceHint(turnDelta),
      hasGpsFix: _currentPosition != null,
      hasCompass: _hasCompass,
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
    _destination = null;
    _currentPosition = null;
    _deviceHeading = 0;
    _targetBearing = 0;
    _hasCompass = false;
    _state = NavigationGuidanceState.initial;
  }

  Future<void> dispose() async {
    await stop();
    await _stateController.close();
  }
}
