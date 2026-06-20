/// Optional Google Maps / Places API configuration.
///
/// Pass at build time for Google Maps-style search:
/// `flutter run --dart-define=GOOGLE_MAPS_API_KEY=your_key`
class MapsConfig {
  MapsConfig._();

  static const googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');
  static bool get hasGoogleMapsApiKey => googleMapsApiKey.isNotEmpty;
}
