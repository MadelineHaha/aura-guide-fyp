import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

class RegisteredFocusTarget {
  RegisteredFocusTarget({
    required this.id,
    required this.label,
    required this.key,
    required this.order,
    this.onActivate,
  });

  final String id;
  String label;
  final GlobalKey key;
  final int order;
  VoidCallback? onActivate;
}

/// Tracks [AccessibleFocusRegion] widgets for reliable bounds + reading order.
class AudioFeedbackRegistry extends ChangeNotifier {
  AudioFeedbackRegistry._();

  static final AudioFeedbackRegistry instance = AudioFeedbackRegistry._();

  int _nextOrder = 0;
  final Map<String, RegisteredFocusTarget> _targets = {};

  void register({
    required String id,
    required String label,
    required GlobalKey key,
    VoidCallback? onActivate,
  }) {
    _targets[id] = RegisteredFocusTarget(
      id: id,
      label: label,
      key: key,
      order: _nextOrder++,
      onActivate: onActivate,
    );
    notifyListeners();
  }

  void updateOnActivate(String id, VoidCallback? onActivate) {
    final target = _targets[id];
    if (target == null) return;
    target.onActivate = onActivate;
  }

  /// Activates the focused target (button press / navigation).
  bool activateForId(String id) {
    final target = _targets[id];
    if (target == null) return false;

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
    notifyListeners();
  }

  void unregister(String id) {
    if (_targets.remove(id) != null) {
      notifyListeners();
    }
  }

  List<({String id, String text})> collectTargets() {
    final items = <({String id, String text, int order})>[];

    for (final target in _targets.values) {
      final text = target.label.trim();
      if (text.isEmpty) continue;
      if (boundsForId(target.id) == null) continue;
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

  Rect? boundsForId(String id) {
    final target = _targets[id];
    if (target == null) return null;

    final context = target.key.currentContext;
    if (context == null) return null;

    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.hasSize ||
        !renderObject.attached) {
      return null;
    }

    final screenSize = _screenSizeFor(context);
    return _focusBounds(renderObject, screenSize);
  }

  Size _screenSizeFor(BuildContext context) {
    final view = View.maybeOf(context);
    if (view != null) {
      return view.physicalSize / view.devicePixelRatio;
    }
    final platformView = WidgetsBinding.instance.platformDispatcher.views.first;
    return platformView.physicalSize / platformView.devicePixelRatio;
  }

  bool _isTooLarge(Rect rect, Size screenSize) {
    if (screenSize.width <= 0 || screenSize.height <= 0) return false;
    final widthRatio = rect.width / screenSize.width;
    final heightRatio = rect.height / screenSize.height;
    return widthRatio > 0.82 ||
        heightRatio > 0.82 ||
        (widthRatio > 0.65 && heightRatio > 0.45);
  }

  Rect? _focusBounds(RenderBox box, Size screenSize) {
    final inner =
        _unionVisibleDescendants(box) ?? _unionParagraphs(box);
    if (inner != null && !_isTooLarge(inner, screenSize)) {
      return inner;
    }

    final outer = box.localToGlobal(Offset.zero) & box.size;
    if (!_isTooLarge(outer, screenSize)) {
      return outer;
    }

    return null;
  }

  Rect? _unionParagraphs(RenderBox root) {
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

  Rect? _unionVisibleDescendants(RenderBox root) {
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
