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

  /// Saved-home navigation intent (not the app main menu).
  static bool isGoHomeNavigationQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    const phrases = <String>[
      'go home',
      'go to home',
      'navigate home',
      'navigate to home',
      'take me home',
      'drive home',
      'my home',
      'home address',
      'back home',
      'pulang rumah',
      'ke rumah',
      '回家',
      '回屋',
    ];
    for (final phrase in phrases) {
      if (normalized == phrase || normalized.contains(phrase)) {
        return true;
      }
    }

    return normalized == 'rumah' || normalized == 'home';
  }

  /// Saved-work navigation intent.
  static bool isGoWorkNavigationQuery(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    const phrases = <String>[
      'go to work',
      'go work',
      'navigate to work',
      'navigate work',
      'take me to work',
      'drive to work',
      'my office',
      'work address',
      'to the office',
      'to my office',
      'tempat kerja',
      'ke pejabat',
      'pejabat saya',
      '去上班',
      '去工作',
      '上班',
    ];
    for (final phrase in phrases) {
      if (normalized == phrase || normalized.contains(phrase)) {
        return true;
      }
    }

    return false;
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
    final category = destination.category ?? '';
    final compactLabel = compact(label);
    final compactAddress = compact(address);
    final compactCategory = compact(category);

    if (compactLabel.contains(compactQuery) ||
        compactAddress.contains(compactQuery) ||
        compactCategory.contains(compactQuery)) {
      return true;
    }

    final loweredLabel = label.toLowerCase();
    final loweredAddress = address.toLowerCase();
    final loweredCategory = category.toLowerCase();
    final loweredQuery = trimmed.toLowerCase();
    if (loweredLabel.contains(loweredQuery) ||
        loweredAddress.contains(loweredQuery) ||
        loweredCategory.contains(loweredQuery)) {
      return true;
    }

    final queryTokens = tokens(trimmed).where((token) => token.length >= 2);
    if (queryTokens.isEmpty) return false;

    final combined = '$loweredLabel $loweredAddress $loweredCategory';
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
    final loweredCategory = (destination.category ?? '').toLowerCase();
    final compactCategory = compact(destination.category ?? '');

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
      if (loweredCategory.contains(loweredQuery)) points += 30;
      if (compactCategory.contains(compactQuery)) points += 28;
    }

    return points;
  }
}
