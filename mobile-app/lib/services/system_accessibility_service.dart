import 'package:flutter/widgets.dart';

/// Tracks whether a system screen reader (TalkBack, VoiceOver, etc.) is active.
class SystemAccessibilityService extends ChangeNotifier
    with WidgetsBindingObserver {
  SystemAccessibilityService._();

  static final SystemAccessibilityService instance =
      SystemAccessibilityService._();

  bool _attached = false;

  bool get isScreenReaderActive =>
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
          .accessibleNavigation;

  void ensureAttached() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    notifyListeners();
  }
}
