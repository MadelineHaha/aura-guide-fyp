import 'package:flutter/rendering.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

import 'app_settings_service.dart';
import 'audio_feedback_registry.dart';

class AccessibleTextItem {
  const AccessibleTextItem({
    required this.targetId,
    required this.text,
  });

  final String targetId;
  final String text;
}

/// Collects readable targets on screen and drives swipe navigation + TTS.
class AudioFeedbackController extends ChangeNotifier {
  AudioFeedbackController({AppSettingsService? settings})
      : _settings = settings ?? AppSettingsService.instance;

  final AppSettingsService _settings;

  List<AccessibleTextItem> _items = [];
  int _index = 0;
  bool _scanning = false;

  List<AccessibleTextItem> get items => List.unmodifiable(_items);
  int get index => _index;
  bool get hasItems => _items.isNotEmpty;

  AccessibleTextItem? get currentItem {
    if (_items.isEmpty || _index < 0 || _index >= _items.length) return null;
    return _items[_index];
  }

  Future<void> refresh(BuildContext context) async {
    if (!_settings.settings.audioFeedbackEnabled) return;
    if (_scanning) return;
    _scanning = true;

    try {
      SemanticsBinding.instance.ensureSemantics();
      await WidgetsBinding.instance.endOfFrame;
      RendererBinding.instance.rootPipelineOwner.flushSemantics();
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;

      var collected = _collect(context);
      if (collected.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        await WidgetsBinding.instance.endOfFrame;
        if (!context.mounted) return;
        collected = _collect(context);
      }

      _items = collected;
      _index = 0;
      notifyListeners();

      if (_items.isNotEmpty) {
        await _settings.speak(_items.first.text);
      }
    } finally {
      _scanning = false;
    }
  }

  Future<void> next() async {
    if (_items.isEmpty) return;
    _index = (_index + 1) % _items.length;
    notifyListeners();
    await _speakCurrent();
  }

  Future<void> previous() async {
    if (_items.isEmpty) return;
    _index = (_index - 1 + _items.length) % _items.length;
    notifyListeners();
    await _speakCurrent();
  }

  Future<void> _speakCurrent() async {
    final item = currentItem;
    if (item == null) return;
    await _settings.speak(item.text);
  }

  void reset() {
    _items = [];
    _index = 0;
    notifyListeners();
  }

  List<AccessibleTextItem> _collect(BuildContext context) {
    final fromRegistry = AudioFeedbackRegistry.instance.collectTargets();
    if (fromRegistry.isNotEmpty) {
      return fromRegistry
          .map(
            (item) => AccessibleTextItem(
              targetId: item.id,
              text: item.text,
            ),
          )
          .toList(growable: false);
    }

    return _collectFromSemantics(context);
  }

  List<AccessibleTextItem> _collectFromSemantics(BuildContext context) {
    final owner =
        RendererBinding.instance.rootPipelineOwner.semanticsOwner;
    final root = owner?.rootSemanticsNode;
    if (root == null) return [];

    final screenSize = _screenSizeFor(context);
    final raw = <AccessibleTextItem>[];
    _visitSemanticsNode(root, raw, screenSize);

    return raw;
  }

  Size _screenSizeFor(BuildContext context) {
    final view = View.maybeOf(context);
    if (view != null) {
      return view.physicalSize / view.devicePixelRatio;
    }
    final platformView = WidgetsBinding.instance.platformDispatcher.views.first;
    return platformView.physicalSize / platformView.devicePixelRatio;
  }

  void _visitSemanticsNode(
    SemanticsNode node,
    List<AccessibleTextItem> out,
    Size screenSize,
  ) {
    if (node.hasFlag(SemanticsFlag.isHidden)) return;

    final label = node.label.trim();
    final value = node.value.trim();
    final hint = node.hint.trim();
    final text = [label, value, hint]
        .where((part) => part.isNotEmpty)
        .join('. ')
        .trim();

    if (text.isNotEmpty && !node.isMergedIntoParent) {
      final rect = _semanticsGlobalRect(node);
      final tooWide = rect.width > screenSize.width * 0.82;
      final tooTall = rect.height > screenSize.height * 0.82;
      if (rect.width >= 8 &&
          rect.height >= 8 &&
          !tooWide &&
          !tooTall) {
        out.add(AccessibleTextItem(targetId: '', text: text));
      }
    }

    node.visitChildren((child) {
      _visitSemanticsNode(child, out, screenSize);
      return true;
    });
  }

  Rect _semanticsGlobalRect(SemanticsNode node) {
    Rect rect = node.rect;
    var current = node;
    while (current.parent != null) {
      if (current.transform != null) {
        rect = MatrixUtils.transformRect(current.transform!, rect);
      }
      current = current.parent!;
    }
    return rect;
  }
}
