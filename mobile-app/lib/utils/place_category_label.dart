/// Formats OSM / Google place-type strings for display and search.
class PlaceCategoryLabel {
  PlaceCategoryLabel._();

  static const _skipGoogleTypes = {
    'point_of_interest',
    'establishment',
    'geocode',
    'political',
    'premise',
    'route',
    'street_address',
    'plus_code',
  };

  static String? fromGoogleTypes(List<dynamic>? types) {
    if (types == null || types.isEmpty) return null;

    for (final raw in types) {
      if (raw is! String) continue;
      final normalized = raw.trim().toLowerCase();
      if (normalized.isEmpty || _skipGoogleTypes.contains(normalized)) {
        continue;
      }
      return _humanize(normalized);
    }
    return null;
  }

  static String? fromNominatim({
    String? type,
    String? categoryClass,
  }) {
    final raw = (type ?? '').trim();
    if (raw.isNotEmpty) return _humanize(raw);

    final className = (categoryClass ?? '').trim();
    if (className.isNotEmpty) return _humanize(className);
    return null;
  }

  static String _humanize(String value) {
    final spaced = value.replaceAll('_', ' ').replaceAll('-', ' ').trim();
    if (spaced.isEmpty) return value;

    return spaced
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
