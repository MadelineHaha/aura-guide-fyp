import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Tracks the top [Route] so audio feedback only scans the visible page.
class AudioFeedbackRouteNotifier extends NavigatorObserver {
  AudioFeedbackRouteNotifier._();

  static final AudioFeedbackRouteNotifier instance =
      AudioFeedbackRouteNotifier._();

  Route<dynamic>? _topRoute;
  Route<dynamic>? get topRoute => _topRoute;

  int _routeGeneration = 0;
  int get routeGeneration => _routeGeneration;

  final ObserverList<VoidCallback> _listeners = ObserverList<VoidCallback>();

  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notify() {
    final listeners = List<VoidCallback>.from(_listeners);
    for (final listener in listeners) {
      if (_listeners.contains(listener)) {
        listener();
      }
    }
  }

  void _setTopRoute(Route<dynamic>? route) {
    if (_topRoute == route) return;
    _topRoute = route;
    _routeGeneration++;
    _notify();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setTopRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setTopRoute(previousRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _setTopRoute(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _setTopRoute(newRoute);
  }

  @override
  void didChangeTop(Route<dynamic> topRoute, Route<dynamic>? previousTopRoute) {
    _setTopRoute(topRoute);
  }
}
