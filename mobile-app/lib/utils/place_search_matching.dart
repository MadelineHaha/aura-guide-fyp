import '../models/navigation_destination.dart';

/// Keyword matching and relevance scoring for navigation place search.
class PlaceSearchMatcher {
  PlaceSearchMatcher._();

  static String compact(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static List<String> tokens(String query) => query
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList();

  static bool isCurrentLocationQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    const phrases = <String>[
      'current location',
      'my location',
      'my current location',
      'your location',
      'where am i',
      'present location',
      'gps location',
      'here',
    ];
    for (final phrase in phrases) {
      if (normalized == phrase || normalized.contains(phrase)) {
        return true;
      }
    }

    final compactQuery = compact(normalized);
    return compactQuery == 'currentlocation' ||
        compactQuery == 'mylocation' ||
        compactQuery == 'yourlocation';
  }

  static bool matches({
    required String query,
    required NavDestination destination,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return false;

    final compactQuery = compact(trimmed);
    if (compactQuery.isEmpty) return false;

    final label = destination.label;
    final address = destination.address;
    final compactLabel = compact(label);
    final compactAddress = compact(address);

    if (compactLabel.contains(compactQuery) ||
        compactAddress.contains(compactQuery)) {
      return true;
    }

    final loweredLabel = label.toLowerCase();
    final loweredAddress = address.toLowerCase();
    final loweredQuery = trimmed.toLowerCase();
    if (loweredLabel.contains(loweredQuery) ||
        loweredAddress.contains(loweredQuery)) {
      return true;
    }

    final queryTokens = tokens(trimmed).where((token) => token.length >= 2);
    if (queryTokens.isEmpty) return false;

    final combined = '$loweredLabel $loweredAddress';
    return queryTokens.every(combined.contains);
  }

  static int score(String query, NavDestination destination) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return 1;

    if (destination.label.toLowerCase() == 'your location' &&
        isCurrentLocationQuery(query)) {
      return 1000;
    }

    final loweredQuery = trimmed.toLowerCase();
    final compactQuery = compact(trimmed);
    final label = destination.label;
    final loweredLabel = label.toLowerCase();
    final compactLabel = compact(label);
    final loweredAddress = destination.address.toLowerCase();
    final compactAddress = compact(destination.address);

    var points = 1;
    if (matches(query: query, destination: destination)) {
      if (loweredLabel == loweredQuery) points += 100;
      if (compactLabel == compactQuery) points += 95;
      if (loweredLabel.startsWith(loweredQuery)) points += 85;
      if (compactLabel.startsWith(compactQuery)) points += 80;
      if (loweredLabel.contains(loweredQuery)) points += 70;
      if (compactLabel.contains(compactQuery)) points += 65;
      if (loweredAddress.contains(loweredQuery)) points += 40;
      if (compactAddress.contains(compactQuery)) points += 35;
    }

    return points;
  }
}
