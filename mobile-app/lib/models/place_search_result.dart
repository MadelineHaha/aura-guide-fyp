import 'navigation_destination.dart';

/// A destination candidate shown in navigation search results.
class PlaceSearchResult {
  const PlaceSearchResult({
    required this.destination,
    this.distanceMeters,
  });

  final NavDestination destination;
  final double? distanceMeters;

  bool get hasCoordinates => destination.hasCoordinates;

  String get distanceLabel {
    final meters = distanceMeters;
    if (meters == null) return '';
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1)} km';
  }
}
