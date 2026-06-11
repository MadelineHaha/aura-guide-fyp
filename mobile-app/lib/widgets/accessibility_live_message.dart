import 'package:flutter/material.dart';

/// Shows feedback on screen and notifies TalkBack when [message] changes.
class AccessibilityLiveMessage extends StatelessWidget {
  const AccessibilityLiveMessage({
    super.key,
    required this.message,
    this.textColor = const Color(0xFFB0B0B0),
  });

  final String? message;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final text = message?.trim();
    if (text == null || text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Semantics(
        liveRegion: true,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontSize: 15,
            height: 1.35,
          ),
        ),
      ),
    );
  }
}
