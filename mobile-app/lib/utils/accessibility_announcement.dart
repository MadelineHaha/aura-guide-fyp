import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';

/// Announces a short message through TalkBack / VoiceOver.
class AccessibilityAnnouncement {
  AccessibilityAnnouncement._();

  static Future<void> announce(
    String message, {
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    if (defaultTargetPlatform == TargetPlatform.android) {
      await SemanticsService.tooltip(trimmed);
      return;
    }

    await SemanticsService.announce(trimmed, textDirection);
  }
}
