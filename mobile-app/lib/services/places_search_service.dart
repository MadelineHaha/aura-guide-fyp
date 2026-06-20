import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../config/maps_config.dart';
import '../models/navigation_destination.dart';
import '../models/place_search_result.dart';
import '../utils/place_search_matching.dart';
import 'navigation_service.dart';

/// Searches saved places and online geocoders for navigation destinations.
class PlacesSearchService {
  PlacesSearchService({
    http.Client? client,
    NavigationService? navigationService,
  })  : _client = client ?? http.Client(),
        _navigationService = navigationService ?? NavigationService.instance;

  static const _nominatimUrl = 'https://nominatim.openstreetmap.org/search';
  static const _googlePlacesUrl =
      'https://places.googleapis.com/v1/places:searchText';
  static const _userAgent = 'AuraGuideFYP/1.0 (navigation search)';

  final http.Client _client;
  final NavigationService _navigationService;

  Future<List<PlaceSearchResult>> search({
    required String query,
    double? originLat,
    double? originLng,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final seen = <String>{};
    final results = <PlaceSearchResult>[];

    void addResult(
      NavDestination destination, {
      required bool requireKeywordMatch,
    }) {
      if (!destination.hasCoordinates) return;
      if (requireKeywordMatch &&
          !PlaceSearchMatcher.matches(query: trimmed, destination: destination)) {
        return;
      }

      final key =
          '${destination.latitude!.toStringAsFixed(4)}|${destination.longitude!.toStringAsFixed(4)}';
      if (seen.contains(key)) return;
      seen.add(key);

      double? distanceMeters;
      if (originLat != null && originLng != null) {
        distanceMeters = Geolocator.distanceBetween(
          originLat,
          originLng,
          destination.latitude!,
          destination.longitude!,
        );
      }

      results.add(
        PlaceSearchResult(
          destination: destination,
          distanceMeters: distanceMeters,
        ),
      );
    }

    for (final item in _navigationService.searchLocal(trimmed)) {
      addResult(item, requireKeywordMatch: true);
    }

    final remoteSearches = <Future<List<NavDestination>>>[
      if (MapsConfig.hasGoogleMapsApiKey)
        _searchGooglePlaces(trimmed, originLat, originLng),
      _searchPlatformGeocoder(trimmed),
      _searchNominatim(trimmed, originLat, originLng),
    ];

    final remoteResults = await Future.wait(remoteSearches);
    for (final batch in remoteResults) {
      for (final item in batch) {
        addResult(item, requireKeywordMatch: false);
      }
    }

    final currentLocation = await _currentLocationDestination(
      originLat,
      originLng,
    );
    if (currentLocation != null) {
      final includeCurrentLocation =
          PlaceSearchMatcher.isCurrentLocationQuery(trimmed) ||
              PlaceSearchMatcher.matches(
                query: trimmed,
                destination: currentLocation,
              );
      if (includeCurrentLocation) {
        addResult(currentLocation, requireKeywordMatch: false);
      }
    }

    results.sort((a, b) {
      final scoreA = PlaceSearchMatcher.score(trimmed, a.destination);
      final scoreB = PlaceSearchMatcher.score(trimmed, b.destination);
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);

      final aDistance = a.distanceMeters;
      final bDistance = b.distanceMeters;
      if (aDistance == null && bDistance == null) return 0;
      if (aDistance == null) return 1;
      if (bDistance == null) return -1;
      return aDistance.compareTo(bDistance);
    });

    return results;
  }

  Future<NavDestination?> _currentLocationDestination(
    double? originLat,
    double? originLng,
  ) async {
    if (originLat == null || originLng == null) return null;

    try {
      final placemarks = await placemarkFromCoordinates(originLat, originLng);
      final placemark = placemarks.isNotEmpty ? placemarks.first : null;
      final address = _addressFromPlacemark(
        placemark,
        '$originLat, $originLng',
      );
      return NavDestination(
        label: 'Your location',
        address: address,
        latitude: originLat,
        longitude: originLng,
      );
    } catch (_) {
      return NavDestination(
        label: 'Your location',
        address:
            '${originLat.toStringAsFixed(5)}, ${originLng.toStringAsFixed(5)}',
        latitude: originLat,
        longitude: originLng,
      );
    }
  }

  Future<List<NavDestination>> _searchGooglePlaces(
    String query,
    double? originLat,
    double? originLng,
  ) async {
    final body = <String, dynamic>{
      'textQuery': query,
      'maxResultCount': 10,
      'languageCode': 'en',
    };

    if (originLat != null && originLng != null) {
      body['locationBias'] = {
        'circle': {
          'center': {
            'latitude': originLat,
            'longitude': originLng,
          },
          'radius': 50000.0,
        },
      };
    }

    try {
      final response = await _client
          .post(
            Uri.parse(_googlePlacesUrl),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': MapsConfig.googleMapsApiKey,
              'X-Goog-FieldMask':
                  'places.displayName,places.formattedAddress,places.location',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return const [];

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return const [];

      final places = decoded['places'];
      if (places is! List) return const [];

      final destinations = <NavDestination>[];
      for (final place in places) {
        if (place is! Map<String, dynamic>) continue;
        final destination = _destinationFromGooglePlace(place);
        if (destination != null) destinations.add(destination);
      }
      return destinations;
    } catch (_) {
      return const [];
    }
  }

  NavDestination? _destinationFromGooglePlace(Map<String, dynamic> place) {
    final location = place['location'];
    if (location is! Map<String, dynamic>) return null;

    final lat = (location['latitude'] as num?)?.toDouble();
    final lon = (location['longitude'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;

    final displayName = place['displayName'];
    final label = displayName is Map<String, dynamic>
        ? (displayName['text'] as String? ?? '').trim()
        : '';
    final address = (place['formattedAddress'] as String? ?? '').trim();

    if (label.isEmpty && address.isEmpty) return null;

    return NavDestination(
      label: label.isNotEmpty ? label : address.split(',').first.trim(),
      address: address.isNotEmpty ? address : label,
      latitude: lat,
      longitude: lon,
    );
  }

  Future<List<NavDestination>> _searchNominatim(
    String query,
    double? originLat,
    double? originLng,
  ) async {
    final params = <String, String>{
      'q': query,
      'format': 'json',
      'addressdetails': '1',
      'limit': '15',
    };

    if (originLat != null && originLng != null) {
      params['lat'] = originLat.toString();
      params['lon'] = originLng.toString();
      const biasDegrees = 2.5;
      final left = originLng - biasDegrees;
      final right = originLng + biasDegrees;
      final top = originLat + biasDegrees;
      final bottom = originLat - biasDegrees;
      params['viewbox'] = '$left,$top,$right,$bottom';
      params['bounded'] = '0';
    }

    final uri = Uri.parse(_nominatimUrl).replace(queryParameters: params);
    try {
      final response = await _client
          .get(
            uri,
            headers: const {'User-Agent': _userAgent},
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) return const [];

      final decoded = jsonDecode(response.body);
      if (decoded is! List) return const [];

      final destinations = <NavDestination>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final destination = _destinationFromNominatim(item);
        if (destination != null) destinations.add(destination);
      }
      return destinations;
    } catch (_) {
      return const [];
    }
  }

  NavDestination? _destinationFromNominatim(Map<String, dynamic> item) {
    final lat = double.tryParse(item['lat'] as String? ?? '');
    final lon = double.tryParse(item['lon'] as String? ?? '');
    if (lat == null || lon == null) return null;

    final displayName = item['display_name'] as String? ?? '';
    if (displayName.isEmpty) return null;

    final rawName = (item['name'] as String?)?.trim();
    final label = (rawName != null && rawName.isNotEmpty)
        ? rawName
        : displayName.split(',').first.trim();

    return NavDestination(
      label: label,
      address: displayName,
      latitude: lat,
      longitude: lon,
    );
  }

  Future<List<NavDestination>> _searchPlatformGeocoder(String query) async {
    try {
      final locations = await locationFromAddress(query);
      if (locations.isEmpty) return const [];

      final destinations = <NavDestination>[];
      for (final location in locations) {
        final placemarks = await placemarkFromCoordinates(
          location.latitude,
          location.longitude,
        );
        final placemark = placemarks.isNotEmpty ? placemarks.first : null;
        destinations.add(
          NavDestination(
            label: _labelFromPlacemark(placemark, query),
            address: _addressFromPlacemark(placemark, query),
            latitude: location.latitude,
            longitude: location.longitude,
          ),
        );
      }
      return destinations;
    } catch (_) {
      return const [];
    }
  }

  String _labelFromPlacemark(Placemark? placemark, String fallback) {
    if (placemark == null) return fallback;

    final candidates = [
      placemark.name,
      placemark.street,
      placemark.subLocality,
      placemark.locality,
    ];
    for (final value in candidates) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return fallback;
  }

  String _addressFromPlacemark(Placemark? placemark, String fallback) {
    if (placemark == null) return fallback;

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

    if (parts.isEmpty) return fallback;
    return parts.join(', ');
  }
}
