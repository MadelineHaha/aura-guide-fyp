import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Shared bounds helpers for the audio-feedback focus border.
class AudioFeedbackBounds {
  AudioFeedbackBounds._();

  /// True when a rect covers most of the screen (e.g. scaffold body), not a
  /// full-width card or row.
  static bool isScreenFilling(Rect rect, Size screenSize) {
    if (screenSize.width <= 0 || screenSize.height <= 0) return false;
    final widthRatio = rect.width / screenSize.width;
    final heightRatio = rect.height / screenSize.height;
    final areaRatio =
        (rect.width * rect.height) / (screenSize.width * screenSize.height);
    return (widthRatio > 0.92 && heightRatio > 0.70) || areaRatio > 0.55;
  }

  static Size screenSizeFor(BuildContext context) {
    final view = View.maybeOf(context);
    if (view != null) {
      return view.physicalSize / view.devicePixelRatio;
    }
    final platformView = WidgetsBinding.instance.platformDispatcher.views.first;
    return platformView.physicalSize / platformView.devicePixelRatio;
  }

  /// Bounds for an explicit [AccessibleFocusRegion] — use the region widget size.
  static Rect? registeredTargetBounds(RenderBox box, Size screenSize) {
    final outer = box.localToGlobal(Offset.zero) & box.size;
    if (outer.width < 4 || outer.height < 4) return null;
    if (!isScreenFilling(outer, screenSize)) return outer;

    final inner = _unionVisibleDescendants(box) ?? _unionParagraphs(box);
    if (inner != null && !isScreenFilling(inner, screenSize)) {
      return inner;
    }
    return null;
  }

  static Rect? _unionParagraphs(RenderBox root) {
    Rect? union;

    void visit(RenderObject object) {
      if (object is RenderParagraph && object.hasSize) {
        final rect = object.localToGlobal(Offset.zero) & object.size;
        if (rect.width >= 4 && rect.height >= 4) {
          union = union == null ? rect : union!.expandToInclude(rect);
        }
      }
      object.visitChildren(visit);
    }

    visit(root);
    return union;
  }

  static Rect? _unionVisibleDescendants(RenderBox root) {
    final rootRect = root.localToGlobal(Offset.zero) & root.size;
    final rootArea = rootRect.width * rootRect.height;
    if (rootArea <= 0) return null;

    Rect? union;

    void visit(RenderObject object) {
      if (identical(object, root)) {
        object.visitChildren(visit);
        return;
      }

      if (object is! RenderBox || !object.hasSize) {
        object.visitChildren(visit);
        return;
      }

      final rect = object.localToGlobal(Offset.zero) & object.size;
      final area = rect.width * rect.height;

      if (area >= rootArea * 0.88) {
        object.visitChildren(visit);
        return;
      }

      if (rect.width >= 4 && rect.height >= 4) {
        union = union == null ? rect : union!.expandToInclude(rect);
      }

      object.visitChildren(visit);
    }

    visit(root);
    return union;
  }
}
