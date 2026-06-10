import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import 'audio_feedback_bounds.dart';
import 'audio_feedback_route_notifier.dart';
import 'audio_feedback_scaffold_registry.dart';

class RegisteredFocusTarget {
  RegisteredFocusTarget({
    required this.id,
    required this.label,
    required this.key,
    required this.order,
    this.routeScope,
    this.onActivate,
  });

  final String id;
  String label;
  final GlobalKey key;
  final int order;
  Route<dynamic>? routeScope;
  VoidCallback? onActivate;
}

/// Tracks [AccessibleFocusRegion] widgets for reliable bounds + reading order.
class AudioFeedbackRegistry extends ChangeNotifier {
  AudioFeedbackRegistry._();

  static final AudioFeedbackRegistry instance = AudioFeedbackRegistry._();

  int _nextOrder = 0;
  final Map<String, RegisteredFocusTarget> _targets = {};
  bool _notifyPending = false;

  void _scheduleNotify() {
    if (_notifyPending) return;
    _notifyPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyPending = false;
      notifyListeners();
    });
  }

  void register({
    required String id,
    required String label,
    required GlobalKey key,
    Route<dynamic>? routeScope,
    VoidCallback? onActivate,
  }) {
    _targets[id] = RegisteredFocusTarget(
      id: id,
      label: label,
      key: key,
      order: _nextOrder++,
      routeScope: routeScope,
      onActivate: onActivate,
    );
    _scheduleNotify();
  }

  void updateRouteScope(String id, Route<dynamic>? routeScope) {
    final target = _targets[id];
    if (target == null || target.routeScope == routeScope) return;
    target.routeScope = routeScope;
    _scheduleNotify();
  }

  void updateOnActivate(String id, VoidCallback? onActivate) {
    final target = _targets[id];
    if (target == null) return;
    target.onActivate = onActivate;
  }

  bool activateForId(String id) {
    final target = _targets[id];
    if (target == null || !_isOnVisibleRoute(target)) return false;

    if (target.onActivate != null) {
      target.onActivate!();
      return true;
    }

    return _performSemanticsTap(target.key.currentContext);
  }

  void updateLabel(String id, String label) {
    final target = _targets[id];
    if (target == null || target.label == label) return;
    target.label = label;
    _scheduleNotify();
  }

  void unregister(String id) {
    if (_targets.remove(id) != null) {
      _scheduleNotify();
    }
  }

  /// True when the target belongs to the route the user is actually viewing.
  bool isTargetOnVisibleRoute(String id) {
    final target = _targets[id];
    if (target == null) return false;
    return _isOnVisibleRoute(target);
  }

  bool _isOnVisibleRoute(RegisteredFocusTarget target) {
    final context = target.key.currentContext;
    if (context == null || !context.mounted) return false;
    if (!AudioFeedbackScaffoldRegistry.shouldIncludeForDrawerState(context)) {
      return false;
    }

    final route = target.routeScope;
    final topRoute = AudioFeedbackRouteNotifier.instance.topRoute;

    if (topRoute != null) {
      return route != null && identical(route, topRoute);
    }

    return route?.isCurrent ?? false;
  }

  List<({String id, String label, VoidCallback? onActivate})>
      registeredOnVisibleRoute() {
    final items = <({String id, String label, VoidCallback? onActivate})>[];

    for (final target in _targets.values) {
      if (!_isOnVisibleRoute(target)) continue;
      final label = target.label.trim();
      if (label.isEmpty) continue;
      if (boundsForId(target.id, checkRoute: false) == null) continue;
      items.add((
        id: target.id,
        label: label,
        onActivate: target.onActivate,
      ));
    }

    return items;
  }

  List<({String id, String text})> collectTargets() {
    final items = <({String id, String text, int order})>[];

    for (final target in _targets.values) {
      if (!_isOnVisibleRoute(target)) continue;

      final text = target.label.trim();
      if (text.isEmpty) continue;
      if (boundsForId(target.id, checkRoute: false) == null) continue;
      items.add((id: target.id, text: text, order: target.order));
    }

    items.sort((a, b) {
      final aRect = boundsForId(a.id);
      final bRect = boundsForId(b.id);
      if (aRect == null || bRect == null) return a.order.compareTo(b.order);
      final y = aRect.top.compareTo(bRect.top);
      if (y != 0) return y;
      final x = aRect.left.compareTo(bRect.left);
      if (x != 0) return x;
      return a.order.compareTo(b.order);
    });

    return items
        .map((item) => (id: item.id, text: item.text))
        .toList(growable: false);
  }

  Rect? boundsForId(String id, {bool checkRoute = true}) {
    final target = _targets[id];
    if (target == null) return null;
    if (checkRoute && !_isOnVisibleRoute(target)) return null;

    final context = target.key.currentContext;
    if (context == null) return null;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        !renderObject.attached) {
      return null;
    }

    final screenSize = AudioFeedbackBounds.screenSizeFor(context);
    return AudioFeedbackBounds.registeredTargetBounds(renderObject, screenSize);
  }

  bool _performSemanticsTap(BuildContext? context) {
    if (context == null) return false;

    final root = context.findRenderObject();
    if (root == null) return false;

    final owner =
        RendererBinding.instance.rootPipelineOwner.semanticsOwner;
    if (owner == null) return false;

    SemanticsNode? tapNode;

    void visit(RenderObject object) {
      if (tapNode != null) return;

      final node = object.debugSemantics;
      if (node != null &&
          !node.isMergedIntoParent &&
          node.getSemanticsData().hasAction(SemanticsAction.tap)) {
        tapNode = node;
        return;
      }

      object.visitChildren(visit);
    }

    visit(root);

    if (tapNode == null) return false;
    owner.performAction(tapNode!.id, SemanticsAction.tap);
    return true;
  }
}
