import 'dart:async';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/navigation_destination.dart';
import 'activity_log_actions.dart';
import 'activity_log_service.dart';
import 'navigation_storage.dart';

class NavigationService {
  NavigationService._();

  static final NavigationService instance = NavigationService._();

  NavDestination? _home;
  NavDestination? _work;
  final List<NavDestination> _recents = [];
  var _initialized = false;

  NavDestination? get home => _home;
  NavDestination? get work => _work;
  List<NavDestination> get recents => List.unmodifiable(_recents);

  List<NavDestination> get recentsForDisplay {
    return _recents.where((item) {
      if (_home != null && _isSamePlace(item, _home!)) return false;
      if (_work != null && _isSamePlace(item, _work!)) return false;
      return true;
    }).toList(growable: false);
  }

  Future<void> initialize() async {
    if (_initialized) return;

    _home = await NavigationStorage.loadHome();
    _work = await NavigationStorage.loadWork();
    _recents
      ..clear()
      ..addAll(await NavigationStorage.loadRecents());
    _initialized = true;
  }

  List<NavDestination> search(String query) {
    final matches = searchLocal(query);
    if (matches.isEmpty) {
      matches.add(
        NavDestination(
          label: query.trim(),
          address: query.trim(),
        ),
      );
    }
    return matches;
  }

  /// Saved and recent places matching [query]. Does not add a free-text fallback.
  List<NavDestination> searchLocal(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];

    final matches = <NavDestination>[];
    final seen = <String>{};

    void addIfMatch(NavDestination item) {
      final key = '${item.label}|${item.address}'.toLowerCase();
      if (seen.contains(key)) return;
      if (item.label.toLowerCase().contains(trimmed) ||
          item.address.toLowerCase().contains(trimmed)) {
        seen.add(key);
        matches.add(item);
      }
    }

    if (_home != null) addIfMatch(_home!);
    if (_work != null) addIfMatch(_work!);
    for (final item in _recents) {
      addIfMatch(item);
    }

    return matches;
  }

  Future<void> rememberRecent(NavDestination destination) async {
    final normalized = destination.copyWith(
      isSavedHome: false,
      isSavedWork: false,
    );

    _recents.removeWhere((item) => _isSamePlace(item, normalized));
    _recents.insert(0, normalized);
    if (_recents.length > 8) {
      _recents.removeRange(8, _recents.length);
    }
    await NavigationStorage.saveRecents(_recents);
  }

  Future<NavDestination> setHome(NavDestination destination) async {
    final resolved = await resolveDestination(destination);
    _home = resolved.copyWith(isSavedHome: true, isSavedWork: false);
    await NavigationStorage.saveHome(_home);
    return _home!;
  }

  Future<NavDestination> setWork(NavDestination destination) async {
    final resolved = await resolveDestination(destination);
    _work = resolved.copyWith(isSavedHome: false, isSavedWork: true);
    await NavigationStorage.saveWork(_work);
    return _work!;
  }

  Future<NavDestination?> currentLocationDestination() async {
    try {
      final position = await currentPosition();
      return destinationFromPosition(position);
    } catch (_) {
      return null;
    }
  }

  Future<NavDestination?> destinationFromPosition(Position position) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      final placemark = placemarks.isNotEmpty ? placemarks.first : null;
      final address = _formatPlacemarkAddress(placemark, position);
      return NavDestination(
        label: 'Your location',
        address: address,
        latitude: position.latitude,
        longitude: position.longitude,
      );
    } catch (_) {
      return NavDestination(
        label: 'Your location',
        address:
            '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
        latitude: position.latitude,
        longitude: position.longitude,
      );
    }
  }

  Future<NavDestination> resolveDestination(
    NavDestination destination,
  ) async {
    if (destination.hasCoordinates) return destination;

    final locations = await locationFromAddress(destination.address);
    if (locations.isEmpty) {
      throw StateError('Could not find that destination.');
    }
    final first = locations.first;
    return destination.copyWith(
      latitude: first.latitude,
      longitude: first.longitude,
    );
  }

  Future<Position> currentPosition() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        throw StateError('Location services are disabled.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location permission is required for navigation.');
      }

      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (error) {
      unawaited(
        ActivityLogService.instance.logWarning(
          action: ActivityLogActions.failedGps,
          details: error.toString(),
        ),
      );
      rethrow;
    }
  }

  double bearingToDestination({
    required Position from,
    required double destLat,
    required double destLng,
  }) {
    return Geolocator.bearingBetween(
      from.latitude,
      from.longitude,
      destLat,
      destLng,
    );
  }

  double normalizeDegrees(double degrees) {
    var value = degrees % 360;
    if (value < 0) value += 360;
    return value;
  }

  double shortestTurn(double targetBearing, double deviceHeading) {
    var delta = normalizeDegrees(targetBearing - deviceHeading);
    if (delta > 180) delta -= 360;
    return delta;
  }

  String guidanceHint(double turnDelta) {
    final abs = turnDelta.abs();
    if (abs < 12) return 'Continue straight';
    if (turnDelta > 0) return 'Turn right';
    return 'Turn left';
  }

  String _formatPlacemarkAddress(Placemark? placemark, Position position) {
    if (placemark == null) {
      return '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
    }

    final parts = <String>[
      if (placemark.street != null && placemark.street!.trim().isNotEmpty)
        placemark.street!.trim(),
      if (placemark.subLocality != null &&
          placemark.subLocality!.trim().isNotEmpty)
        placemark.subLocality!.trim(),
      if (placemark.locality != null && placemark.locality!.trim().isNotEmpty)
        placemark.locality!.trim(),
      if (placemark.administrativeArea != null &&
          placemark.administrativeArea!.trim().isNotEmpty)
        placemark.administrativeArea!.trim(),
      if (placemark.country != null && placemark.country!.trim().isNotEmpty)
        placemark.country!.trim(),
    ];

    if (parts.isEmpty) {
      return '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
    }
    return parts.join(', ');
  }

  bool _isSamePlace(NavDestination a, NavDestination b) {
    if (a.hasCoordinates && b.hasCoordinates) {
      final sameLat = (a.latitude! - b.latitude!).abs() < 0.0001;
      final sameLng = (a.longitude! - b.longitude!).abs() < 0.0001;
      if (sameLat && sameLng) return true;
    }
    return a.label.toLowerCase() == b.label.toLowerCase() &&
        a.address.toLowerCase() == b.address.toLowerCase();
  }
}
