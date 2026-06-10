import 'package:flutter/material.dart';

import '../services/audio_feedback_registry.dart';
import '../services/audio_feedback_route_notifier.dart';

/// Groups on-screen content into one audio-feedback focus target.
///
/// Does not change child layout — only registers bounds for the overlay.
class AccessibleFocusRegion extends StatefulWidget {
  const AccessibleFocusRegion({
    super.key,
    required this.label,
    required this.child,
    this.onActivate,
  });

  final String label;
  final Widget child;
  final VoidCallback? onActivate;

  @override
  State<AccessibleFocusRegion> createState() => _AccessibleFocusRegionState();
}

class _AccessibleFocusRegionState extends State<AccessibleFocusRegion> {
  final _boundsKey = GlobalKey();
  late final String _id = UniqueKey().toString();
  bool _registered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route =
        ModalRoute.of(context) ?? AudioFeedbackRouteNotifier.instance.topRoute;
    if (!_registered) {
      AudioFeedbackRegistry.instance.register(
        id: _id,
        label: widget.label,
        key: _boundsKey,
        routeScope: route,
        onActivate: widget.onActivate,
      );
      _registered = true;
      return;
    }

    AudioFeedbackRegistry.instance.updateRouteScope(_id, route);
  }

  @override
  void didUpdateWidget(covariant AccessibleFocusRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label) {
      AudioFeedbackRegistry.instance.updateLabel(_id, widget.label);
    }
    if (oldWidget.onActivate != widget.onActivate) {
      AudioFeedbackRegistry.instance.updateOnActivate(_id, widget.onActivate);
    }
  }

  @override
  void dispose() {
    AudioFeedbackRegistry.instance.unregister(_id);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _boundsKey,
      child: widget.child,
    );
  }
}
