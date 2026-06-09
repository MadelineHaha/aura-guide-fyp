import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/navigation_destination.dart';

class NavigationService {
  NavDestination? _home;
  NavDestination? _work;
  final List<NavDestination> _recents = [];

  static const _defaultHome = NavDestination(
    label: 'HOME',
    address: '45 Jalan Bukit Bintang, Kuala Lumpur',
    latitude: 3.1478,
    longitude: 101.7089,
    isSavedHome: true,
  );

  NavigationService() {
    _home = _defaultHome;
    _recents.addAll([
      _defaultHome,
      const NavDestination(
        label: 'After One KL',
        address: '1 Jalan Yap Kwan Seng, Kuala Lumpur',
        latitude: 3.1612,
        longitude: 101.7148,
      ),
      const NavDestination(
        label: 'Ho Kow Hainam Kopitiam',
        address: '1 Jalan Balai Polis, Kuala Lumpur',
        latitude: 3.1436,
        longitude: 101.6974,
      ),
    ]);
  }

  NavDestination? get home => _home;
  NavDestination? get work => _work;
  List<NavDestination> get recents => List.unmodifiable(_recents);

  List<NavDestination> search(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return recents;

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

  void rememberRecent(NavDestination destination) {
    _recents.removeWhere(
      (item) =>
          item.label == destination.label && item.address == destination.address,
    );
    _recents.insert(0, destination);
    if (_recents.length > 8) {
      _recents.removeRange(8, _recents.length);
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
}
