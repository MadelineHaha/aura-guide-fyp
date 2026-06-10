import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';
import '../services/audio_feedback_bounds.dart';
import '../services/audio_feedback_controller.dart';
import '../services/audio_feedback_registry.dart';
import '../services/audio_feedback_route_notifier.dart';

/// Pass-through host for [MaterialApp.builder]. Inserts an [OverlayEntry] into
/// the [Navigator] overlay so the focus border paints above routes without
/// wrapping the navigator (which causes GlobalKey conflicts).
class AudioFeedbackHost extends StatefulWidget {
  const AudioFeedbackHost({
    super.key,
    required this.child,
    this.navigatorKey,
  });

  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Re-scans focus targets when the main-menu drawer opens or closes.
  static void notifyDrawerChanged() {
    _AudioFeedbackHostState._activeHost?._onDrawerChanged();
  }

  /// Re-scans visible text — call after async page data finishes loading.
  static void requestRefresh() {
    _AudioFeedbackHostState._activeHost?._scheduleRefresh();
  }

  @override
  State<AudioFeedbackHost> createState() => _AudioFeedbackHostState();
}

class _AudioFeedbackHostState extends State<AudioFeedbackHost> {
  static _AudioFeedbackHostState? _activeHost;

  final _settings = AppSettingsService.instance;
  final _controller = AudioFeedbackController.instance;
  final _routeNotifier = AudioFeedbackRouteNotifier.instance;
  OverlayEntry? _entry;
  bool _routeRefreshPending = false;

  @override
  void initState() {
    super.initState();
    _activeHost = this;
    _settings.addListener(_onSettingsChanged);
    _controller.addListener(_onControllerChanged);
    AudioFeedbackRegistry.instance.addListener(_onRegistryChanged);
    _routeNotifier.addListener(_onRouteChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncOverlay();
      _scheduleRefresh(resetFocus: true);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncOverlay();
  }

  @override
  void dispose() {
    if (_activeHost == this) {
      _activeHost = null;
    }
    _removeOverlay();
    _routeNotifier.removeListener(_onRouteChanged);
    AudioFeedbackRegistry.instance.removeListener(_onRegistryChanged);
    _settings.removeListener(_onSettingsChanged);
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  OverlayState? _navigatorOverlay() {
    return widget.navigatorKey?.currentState?.overlay ??
        Navigator.maybeOf(context)?.overlay;
  }

  void _syncOverlay() {
    if (!_settings.settings.audioFeedbackEnabled) {
      _removeOverlay();
      return;
    }
    _ensureOverlay();
    _rebuildOverlay();
  }

  void _ensureOverlay() {
    if (_entry != null) return;

    final overlay = _navigatorOverlay();
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncOverlay();
      });
      return;
    }

    _entry = OverlayEntry(
      builder: (context) => ListenableBuilder(
        listenable: Listenable.merge([
          _controller,
          _settings,
        ]),
        builder: (context, _) => _AudioFeedbackOverlayLayer(
          focusIndex: _controller.index,
          focusTargetId: _controller.currentItem?.targetId ?? '',
          routeGeneration: _routeNotifier.routeGeneration,
        ),
      ),
    );
    overlay.insert(_entry!);
  }

  void _removeOverlay() {
    _entry?.remove();
    _entry?.dispose();
    _entry = null;
  }

  void _rebuildOverlay() => _entry?.markNeedsBuild();

  void _onDrawerChanged() {
    if (!_settings.settings.audioFeedbackEnabled) return;
    _controller.forgetLastSpoken();
    _bringOverlayToFront();
    _scheduleRefresh(resetFocus: true);
    _rebuildOverlay();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bringOverlayToFront();
      _rebuildOverlay();
    });
  }

  void _bringOverlayToFront() {
    final entry = _entry;
    final overlay = _navigatorOverlay();
    if (entry == null || overlay == null || !entry.mounted) return;
    entry.remove();
    overlay.insert(entry);
    entry.markNeedsBuild();
  }

  void _onSettingsChanged() {
    if (!_settings.settings.audioFeedbackEnabled) {
      _controller.reset();
      _removeOverlay();
      return;
    }
    _syncOverlay();
    _scheduleRefresh();
  }

  void _onControllerChanged() {
    _rebuildOverlay();
  }

  void _onRegistryChanged() {
    if (!_settings.settings.audioFeedbackEnabled) return;
    _controller.pruneStaleItems();
    _scheduleRefresh(resetFocus: _routeRefreshPending);
    _rebuildOverlay();
  }

  void _onRouteChanged() {
    if (!_settings.settings.audioFeedbackEnabled) return;
    _routeRefreshPending = true;
    _controller.reset();
    _rebuildOverlay();
    _bringOverlayToFront();
    _scheduleRefresh(resetFocus: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _routeRefreshPending = false;
      _bringOverlayToFront();
      _scheduleRefresh(resetFocus: true);
    });
  }

  void _scheduleRefresh({bool resetFocus = false}) {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybeRefresh(resetFocus: resetFocus),
    );
  }

  Future<void> _maybeRefresh({bool resetFocus = false}) async {
    if (!_settings.settings.audioFeedbackEnabled || !mounted) return;
    await _controller.refresh(
      context,
      resetFocus: resetFocus || _routeRefreshPending,
      routeGeneration: _routeNotifier.routeGeneration,
    );
    if (!mounted) return;
    _bringOverlayToFront();
    _rebuildOverlay();
    if (_controller.hasItems) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_settings.settings.audioFeedbackEnabled) return;
      await _controller.refresh(
        context,
        resetFocus: resetFocus,
        routeGeneration: _routeNotifier.routeGeneration,
      );
      if (mounted) _rebuildOverlay();
    });
  }

  static Future<void> _handleSwipe({
    required double velocity,
    required double distance,
  }) async {
    final host = _activeHost;
    if (host == null || !host._settings.settings.audioFeedbackEnabled) return;
    if (!host._controller.hasItems) return;

    const minVelocity = 40.0;
    const minDistance = 18.0;

    final useVelocity = velocity.abs() >= minVelocity;
    final useDistance = distance.abs() >= minDistance;
    if (!useVelocity && !useDistance) return;

    final delta = useVelocity ? velocity : distance;
    // Swipe right → next item, swipe left → previous item.
    if (delta > 0) {
      await host._controller.next();
    } else {
      await host._controller.previous();
    }
    host._rebuildOverlay();
  }

  static void handleDoubleTap() {
    final host = _activeHost;
    if (host == null || !host._settings.settings.audioFeedbackEnabled) return;
    host._controller.activateCurrentItem();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AudioFeedbackOverlayLayer extends StatelessWidget {
  const _AudioFeedbackOverlayLayer({
    required this.focusIndex,
    required this.focusTargetId,
    required this.routeGeneration,
  });

  final int focusIndex;
  final String focusTargetId;
  final int routeGeneration;

  static final GlobalKey _layerKey = GlobalKey();

  Rect? _focusRectInLayer(Rect globalRect) {
    final layerContext = _layerKey.currentContext;
    final layerBox = layerContext?.findRenderObject();
    if (layerBox is! RenderBox || !layerBox.hasSize) {
      return null;
    }

    final topLeft = layerBox.globalToLocal(globalRect.topLeft);
    final bottomRight = layerBox.globalToLocal(globalRect.bottomRight);
    final rect = Rect.fromPoints(topLeft, bottomRight);
    if (rect.width < 4 || rect.height < 4) return null;

    final screenSize = AudioFeedbackBounds.screenSizeFor(layerContext!);
    if (AudioFeedbackBounds.isScreenFilling(rect, screenSize)) {
      return null;
    }

    return rect;
  }

  @override
  Widget build(BuildContext context) {
    if (!AppSettingsService.instance.settings.audioFeedbackEnabled) {
      return const SizedBox.shrink();
    }

    final controller = AudioFeedbackController.instance;
    final globalRect = controller.resolveHighlightBounds();
    final focusRect =
        globalRect == null ? null : _focusRectInLayer(globalRect);

    return Positioned.fill(
      key: _layerKey,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: _SwipeableOverlaySurface(
          focusRect: focusRect,
          focusIndex: focusIndex,
          onSwipe: _AudioFeedbackHostState._handleSwipe,
          onDoubleTap: _AudioFeedbackHostState.handleDoubleTap,
        ),
      ),
    );
  }
}

/// Blocks all touches, then accepts full-screen swipe and double-tap gestures.
class _SwipeableOverlaySurface extends StatefulWidget {
  const _SwipeableOverlaySurface({
    required this.focusRect,
    required this.focusIndex,
    required this.onSwipe,
    required this.onDoubleTap,
  });

  final Rect? focusRect;
  final int focusIndex;
  final Future<void> Function({
    required double velocity,
    required double distance,
  }) onSwipe;
  final VoidCallback onDoubleTap;

  @override
  State<_SwipeableOverlaySurface> createState() =>
      _SwipeableOverlaySurfaceState();
}

class _SwipeableOverlaySurfaceState extends State<_SwipeableOverlaySurface> {
  double _dragDx = 0;
  bool _tracking = false;
  DateTime? _lastTapTime;
  Offset? _lastTapPos;

  static const _swipeSlop = 8.0;
  static const _doubleTapWindow = Duration(milliseconds: 350);
  static const _doubleTapSlop = 64.0;

  void _onPointerDown(PointerDownEvent event) {
    _tracking = true;
    _dragDx = 0;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_tracking) return;
    _dragDx += event.delta.dx;
  }

  Future<void> _onPointerUp(PointerUpEvent event) async {
    if (!_tracking) return;
    _tracking = false;

    final distance = _dragDx;
    final pos = event.localPosition;

    if (distance.abs() >= _swipeSlop) {
      _lastTapTime = null;
      _lastTapPos = null;
      _dragDx = 0;
      await widget.onSwipe(velocity: distance * 15, distance: distance);
      return;
    }

    _dragDx = 0;

    // Double-tap anywhere activates the currently highlighted item.
    final now = DateTime.now();
    if (_lastTapTime != null &&
        _lastTapPos != null &&
        now.difference(_lastTapTime!) <= _doubleTapWindow &&
        (pos - _lastTapPos!).distance <= _doubleTapSlop) {
      _lastTapTime = null;
      _lastTapPos = null;
      widget.onDoubleTap();
      return;
    }

    _lastTapTime = now;
    _lastTapPos = pos;
  }

  void _onPointerCancel() {
    _tracking = false;
    _dragDx = 0;
  }

  @override
  Widget build(BuildContext context) {
    final focusRect = widget.focusRect;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: (_) => _onPointerCancel(),
      child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            const Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: SizedBox.expand(),
              ),
            ),
            if (focusRect != null)
              Positioned.fromRect(
                rect: focusRect,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
          ],
        ),
    );
  }
}

/// Kept for imports — [AudioFeedbackHost] is the real entry point.
typedef AudioFeedbackOverlay = AudioFeedbackHost;
