import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/walking_route.dart';
import 'app_settings_service.dart';

/// Fetches pedestrian routes from the public OSRM service.
class WalkingRouteService {
  WalkingRouteService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://router.project-osrm.org/route/v1/foot';

  final http.Client _client;

  Future<WalkingRoute> fetchWalkingRoute({
    required double startLat,
    required double startLng,
    required double endLat,
    required double endLng,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/$startLng,$startLat;$endLng,$endLat'
      '?steps=true&geometries=geojson&overview=full',
    );

    final response = await _client.get(uri).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw StateError('Walking route service returned ${response.statusCode}.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Invalid walking route response.');
    }

    final code = decoded['code'] as String? ?? '';
    if (code != 'Ok') {
      throw StateError('No walking route found for this destination.');
    }

    final routes = decoded['routes'];
    if (routes is! List || routes.isEmpty) {
      throw StateError('No walking route found for this destination.');
    }

    final route = routes.first as Map<String, dynamic>;
    final legs = route['legs'];
    if (legs is! List || legs.isEmpty) {
      throw StateError('Walking route had no steps.');
    }

    final leg = legs.first as Map<String, dynamic>;
    final totalDistance =
        ((route['distance'] as num?) ?? (leg['distance'] as num?) ?? 0).toDouble();

    final points = _parseGeometry(route['geometry']);
    final steps = _parseSteps(leg['steps']);

    if (points.isEmpty) {
      throw StateError('Walking route had no path points.');
    }

    return WalkingRoute(
      points: points,
      steps: steps,
      totalDistanceMeters: totalDistance,
    );
  }

  List<RoutePoint> _parseGeometry(dynamic geometry) {
    if (geometry is! Map<String, dynamic>) return const [];
    final coordinates = geometry['coordinates'];
    if (coordinates is! List) return const [];

    return [
      for (final item in coordinates)
        if (item is List && item.length >= 2)
          RoutePoint(
            longitude: (item[0] as num).toDouble(),
            latitude: (item[1] as num).toDouble(),
          ),
    ];
  }

  List<WalkStep> _parseSteps(dynamic rawSteps) {
    if (rawSteps is! List) return const [];

    final parsed = <WalkStep>[];
    for (final item in rawSteps) {
      if (item is! Map<String, dynamic>) continue;
      final maneuver = item['maneuver'];
      if (maneuver is! Map<String, dynamic>) continue;

      final location = maneuver['location'];
      if (location is! List || location.length < 2) continue;

      parsed.add(
        WalkStep(
          instruction: _instructionForStep(maneuver, item),
          longitude: (location[0] as num).toDouble(),
          latitude: (location[1] as num).toDouble(),
          distanceMeters: ((item['distance'] as num?) ?? 0).toDouble(),
        ),
      );
    }

    return parsed;
  }

  String _instructionForStep(
    Map<String, dynamic> maneuver,
    Map<String, dynamic> step,
  ) {
    final settings = AppSettingsService.instance;
    String l10n(String key, [Map<String, Object?> params = const {}]) =>
        settings.localized(key, params);

    final name = (step['name'] as String?)?.trim() ?? '';
    final type = (maneuver['type'] as String?) ?? '';
    final modifier = (maneuver['modifier'] as String?) ?? '';

    if (type == 'arrive') {
      return l10n('arrivedAtDestination');
    }
    if (type == 'depart') {
      return name.isEmpty
          ? l10n('startWalking')
          : l10n('startWalkingOn', {'name': name});
    }

    final turn = switch (modifier) {
      'left' => l10n('turnLeft'),
      'sharp left' => l10n('turnSharpLeft'),
      'slight left' => l10n('turnSlightLeft'),
      'right' => l10n('turnRight'),
      'sharp right' => l10n('turnSharpRight'),
      'slight right' => l10n('turnSlightRight'),
      'uturn' => l10n('makeUturn'),
      _ => l10n('continueStraight'),
    };

    if (name.isEmpty) return turn;
    return l10n('turnOnto', {'turn': turn, 'name': name});
  }

  void dispose() {
    _client.close();
  }
}

final walkingRouteService = WalkingRouteService();
