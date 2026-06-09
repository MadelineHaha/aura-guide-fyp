import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';

import '../app_route_observer.dart';
import '../services/app_settings_service.dart';
import '../services/audio_feedback_controller.dart';
import '../services/audio_feedback_registry.dart';

/// Full-screen explore overlay: white focus box, TTS, swipe left/right.
class AudioFeedbackOverlay extends StatefulWidget {
  const AudioFeedbackOverlay({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AudioFeedbackOverlay> createState() => _AudioFeedbackOverlayState();
}

class _AudioFeedbackOverlayState extends State<AudioFeedbackOverlay>
    with RouteAware {
  final _settings = AppSettingsService.instance;
  final _controller = AudioFeedbackController();
  SemanticsHandle? _semanticsHandle;
  bool _routeSubscribed = false;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _controller.addListener(_onControllerChanged);
    AudioFeedbackRegistry.instance.addListener(_onRegistryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncSemantics();
      _scheduleRefresh();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSubscribed) return;
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
      _routeSubscribed = true;
    }
    _scheduleRefresh();
  }

  @override
  void dispose() {
    if (_routeSubscribed) {
      appRouteObserver.unsubscribe(this);
    }
    _semanticsHandle?.dispose();
    AudioFeedbackRegistry.instance.removeListener(_onRegistryChanged);
    _settings.removeListener(_onSettingsChanged);
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didPush() => _scheduleRefresh();
  @override
  void didPopNext() => _scheduleRefresh();

  void _onSettingsChanged() {
    _syncSemantics();
    if (!_settings.settings.audioFeedbackEnabled) {
      _controller.reset();
    }
    _scheduleRefresh();
    setState(() {});
  }

  void _onControllerChanged() => setState(() {});

  void _onRegistryChanged() {
    if (!_settings.settings.audioFeedbackEnabled) return;
    _scheduleRefresh();
    setState(() {});
  }

  void _syncSemantics() {
    if (_settings.settings.audioFeedbackEnabled) {
      _semanticsHandle ??= SemanticsBinding.instance.ensureSemantics();
    } else {
      _semanticsHandle?.dispose();
      _semanticsHandle = null;
    }
  }

  void _scheduleRefresh() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeRefresh());
  }

  Future<void> _maybeRefresh() async {
    if (!_settings.settings.audioFeedbackEnabled || !mounted) return;
    await _controller.refresh(context);
    if (!mounted) return;
    if (_controller.hasItems) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_settings.settings.audioFeedbackEnabled) return;
      await _controller.refresh(context);
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 180) return;
    if (velocity > 0) {
      _controller.next();
    } else {
      _controller.previous();
    }
  }

  void _onDoubleTap() {
    final current = _controller.currentItem;
    if (current == null || current.targetId.isEmpty) return;
    AudioFeedbackRegistry.instance.activateForId(current.targetId);
  }

  Rect? _focusRectInLayer(Rect globalRect, BuildContext layerContext) {
    final layerBox = layerContext.findRenderObject();
    if (layerBox is! RenderBox || !layerBox.hasSize) {
      return null;
    }

    final topLeft = layerBox.globalToLocal(globalRect.topLeft);
    final bottomRight = layerBox.globalToLocal(globalRect.bottomRight);
    final rect = Rect.fromPoints(topLeft, bottomRight);
    if (rect.width < 4 || rect.height < 4) return null;

    final layerSize = layerBox.size;
    if (rect.width > layerSize.width * 0.82 ||
        rect.height > layerSize.height * 0.82) {
      return null;
    }

    return rect;
  }

  @override
  Widget build(BuildContext context) {
    if (!_settings.settings.audioFeedbackEnabled) {
      return widget.child;
    }

    final current = _controller.currentItem;
    final globalRect = current == null || current.targetId.isEmpty
        ? null
        : AudioFeedbackRegistry.instance.boundsForId(current.targetId);

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: Builder(
            builder: (layerContext) {
              final focusRect = globalRect == null
                  ? null
                  : _focusRectInLayer(globalRect, layerContext);

              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: _onDoubleTap,
                onHorizontalDragEnd: _onHorizontalDragEnd,
                child: Stack(
                  fit: StackFit.expand,
                  clipBehavior: Clip.none,
                  children: [
                    if (focusRect != null) _FocusBorder(rect: focusRect),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FocusBorder extends StatelessWidget {
  const _FocusBorder({required this.rect});

  final Rect rect;

  static const double _padding = 4;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: rect.left - _padding,
      top: rect.top - _padding,
      width: rect.width + (_padding * 2),
      height: rect.height + (_padding * 2),
      child: IgnorePointer(
        child: CustomPaint(
          painter: _FocusBorderPainter(),
        ),
      ),
    );
  }
}

class _FocusBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(6),
    );
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
