import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_settings_service.dart';
import 'audio_feedback_registry.dart';
import 'audio_feedback_text_scanner.dart';

class AccessibleTextItem {
  const AccessibleTextItem({
    required this.targetId,
    required this.text,
    this.bounds,
    this.onActivate,
  });

  final String targetId;
  final String text;
  final Rect? bounds;
  final VoidCallback? onActivate;
}

/// Collects readable targets on screen and drives swipe navigation + TTS.
class AudioFeedbackController extends ChangeNotifier {
  AudioFeedbackController._({AppSettingsService? settings})
      : _settings = settings ?? AppSettingsService.instance;

  static final AudioFeedbackController instance = AudioFeedbackController._();

  final AppSettingsService _settings;

  List<AccessibleTextItem> _items = [];
  int _index = 0;
  bool _scanning = false;
  bool _refreshPending = false;
  int _focusRouteGeneration = -1;
  String? _lastSpokenTargetId;

  List<AccessibleTextItem> get items => List.unmodifiable(_items);
  int get index => _index;
  bool get hasItems => _items.isNotEmpty;

  AccessibleTextItem? get currentItem {
    if (_items.isEmpty || _index < 0 || _index >= _items.length) return null;
    return _items[_index];
  }

  Rect? get currentBounds => resolveHighlightBounds();

  /// Live global bounds for the white focus border.
  Rect? resolveHighlightBounds() {
    final item = currentItem;
    if (item == null) return null;
    if (!item.targetId.startsWith('scan:')) {
      return AudioFeedbackRegistry.instance.boundsForId(item.targetId);
    }
    return item.bounds;
  }

  void activateCurrentItem() {
    final item = currentItem;
    if (item == null) return;
    if (item.onActivate != null) {
      item.onActivate!();
      return;
    }
    if (!item.targetId.startsWith('scan:')) {
      if (AudioFeedbackRegistry.instance.activateForId(item.targetId)) {
        return;
      }
    }
    // Read-only blocks (e.g. greeting) — confirm with speech on double-tap.
    unawaited(_settings.speak(item.text));
  }

  Future<void> refresh(
    BuildContext context, {
    bool resetFocus = false,
    int? routeGeneration,
  }) async {
    if (!_settings.settings.audioFeedbackEnabled) return;
    if (_scanning) {
      _refreshPending = true;
      return;
    }
    _scanning = true;

    final routeChanged = routeGeneration != null &&
        _focusRouteGeneration != routeGeneration;
    if (routeChanged) {
      _focusRouteGeneration = routeGeneration;
      resetFocus = true;
    }

    try {
      await WidgetsBinding.instance.endOfFrame;
      if (!context.mounted) return;

      var collected = _collect(context);
      for (var attempt = 0;
          collected.length <= 1 && attempt < 4;
          attempt++) {
        await Future<void>.delayed(Duration(milliseconds: 80 + attempt * 60));
        await WidgetsBinding.instance.endOfFrame;
        if (!context.mounted) return;
        final retry = _collect(context);
        if (retry.length > collected.length) {
          collected = retry;
        }
      }

      final hadItems = _items.isNotEmpty;
      final previousId = resetFocus ? null : currentItem?.targetId;
      final previousText = resetFocus ? null : currentItem?.text;
      _items = collected;
      if (!hadItems || previousId == null || resetFocus) {
        _index = 0;
      } else {
        final keepIndex =
            collected.indexWhere((i) => i.targetId == previousId);
        _index = keepIndex >= 0 ? keepIndex : 0;
      }
      notifyListeners();

      final currentId = currentItem?.targetId;
      final textChanged = previousId != null &&
          previousId == currentId &&
          previousText != null &&
          previousText != currentItem?.text;
      final shouldSpeak = _items.isNotEmpty &&
          (resetFocus ||
              routeChanged ||
              !hadItems ||
              textChanged ||
              (currentId != null && currentId != _lastSpokenTargetId));
      if (shouldSpeak) {
        await _speakCurrent();
      }
    } finally {
      _scanning = false;
      if (_refreshPending) {
        _refreshPending = false;
        if (context.mounted) {
          await refresh(
            context,
            resetFocus: resetFocus,
            routeGeneration: routeGeneration,
          );
        }
      }
    }
  }

  /// Drops stale items that are no longer on the visible route.
  void pruneStaleItems() {
    if (_items.isEmpty) return;

    final visibleIds = _items
        .where((item) => item.bounds != null || _isRegisteredAndVisible(item))
        .map((item) => item.targetId)
        .toSet();
    if (visibleIds.isEmpty) {
      _items = [];
      _index = 0;
      notifyListeners();
      return;
    }

    final pruned = _items
        .where((item) => visibleIds.contains(item.targetId))
        .toList(growable: false);
    if (pruned.length == _items.length) return;

    _items = pruned;
    if (_index >= _items.length) {
      _index = 0;
    }
    notifyListeners();
  }

  bool _isRegisteredAndVisible(AccessibleTextItem item) {
    if (item.targetId.startsWith('scan:')) {
      return item.bounds != null &&
          item.bounds!.height > 0 &&
          item.bounds!.width > 0;
    }
    return AudioFeedbackRegistry.instance.isTargetOnVisibleRoute(item.targetId);
  }

  Future<void> next() async {
    if (_items.isEmpty) return;
    _index = (_index + 1) % _items.length;
    _syncCurrentItemBounds();
    notifyListeners();
    await _speakCurrent();
  }

  Future<void> previous() async {
    if (_items.isEmpty) return;
    _index = (_index - 1 + _items.length) % _items.length;
    _syncCurrentItemBounds();
    notifyListeners();
    await _speakCurrent();
  }

  void _syncCurrentItemBounds() {
    final item = currentItem;
    if (item == null || item.targetId.startsWith('scan:')) return;
    final bounds = AudioFeedbackRegistry.instance.boundsForId(item.targetId);
    if (bounds == null) return;
    _items[_index] = AccessibleTextItem(
      targetId: item.targetId,
      text: item.text,
      bounds: bounds,
      onActivate: item.onActivate,
    );
  }

  Future<void> _speakCurrent() async {
    final item = currentItem;
    if (item == null) return;
    await _settings.speak(item.text);
    _lastSpokenTargetId = item.targetId;
  }

  void reset() {
    _items = [];
    _index = 0;
    _lastSpokenTargetId = null;
    notifyListeners();
  }

  void forgetLastSpoken() {
    _lastSpokenTargetId = null;
  }

  List<AccessibleTextItem> _collect(BuildContext context) {
    final registry = AudioFeedbackRegistry.instance;
    final registered = registry.registeredOnVisibleRoute();
    final scanned = AudioFeedbackTextScanner.scan(context);
    final items = <AccessibleTextItem>[];
    final regionBounds = <Rect>[];

    // One focus step per [AccessibleFocusRegion] — e.g. greeting block, reminder card.
    for (final reg in registered) {
      final bounds = registry.boundsForId(reg.id);
      if (bounds == null) continue;
      regionBounds.add(bounds);
      items.add(
        AccessibleTextItem(
          targetId: reg.id,
          text: reg.label,
          bounds: bounds,
          onActivate: reg.onActivate,
        ),
      );
    }

    // Only add auto-scanned lines that are not already inside a focus region.
    for (final block in scanned) {
      final insideRegion = regionBounds.any(
        (rect) => rect.overlaps(block.bounds.inflate(2)),
      );
      if (insideRegion) continue;

      items.add(
        AccessibleTextItem(
          targetId: block.id,
          text: block.text,
          bounds: block.bounds,
          onActivate: null,
        ),
      );
    }

    items.sort(_compareByPosition);
    return items;
  }

  int _compareByPosition(AccessibleTextItem a, AccessibleTextItem b) {
    final aRect = a.bounds;
    final bRect = b.bounds;
    if (aRect == null || bRect == null) return 0;
    final y = aRect.top.compareTo(bRect.top);
    if (y != 0) return y;
    return aRect.left.compareTo(bRect.left);
  }
}
