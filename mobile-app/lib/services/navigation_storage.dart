import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/navigation_destination.dart';

/// Persists home, work, and recent navigation destinations locally.
class NavigationStorage {
  NavigationStorage._();

  static const _homeKey = 'navigation_saved_home';
  static const _workKey = 'navigation_saved_work';
  static const _recentsKey = 'navigation_recent_destinations';

  static Future<NavDestination?> loadHome() async {
    return _loadDestination(_homeKey);
  }

  static Future<NavDestination?> loadWork() async {
    return _loadDestination(_workKey);
  }

  static Future<List<NavDestination>> loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recentsKey);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => NavDestination.fromJson(Map<String, dynamic>.from(item)))
          .where((item) => item.label.isNotEmpty && item.address.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveHome(NavDestination? destination) async {
    await _saveDestination(_homeKey, destination);
  }

  static Future<void> saveWork(NavDestination? destination) async {
    await _saveDestination(_workKey, destination);
  }

  static Future<void> saveRecents(List<NavDestination> recents) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(recents.map((item) => item.toJson()).toList());
    await prefs.setString(_recentsKey, encoded);
  }

  static Future<NavDestination?> _loadDestination(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final destination =
          NavDestination.fromJson(Map<String, dynamic>.from(decoded));
      if (destination.label.isEmpty || destination.address.isEmpty) {
        return null;
      }
      return destination;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveDestination(
    String key,
    NavDestination? destination,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    if (destination == null) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, jsonEncode(destination.toJson()));
  }
}
