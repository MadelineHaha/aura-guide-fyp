import 'package:flutter/material.dart';

import 'accessible_focus_region.dart';

/// App bar title (or section heading) registered for audio feedback.
class AudioFeedbackTitle extends StatelessWidget {
  const AudioFeedbackTitle({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AccessibleFocusRegion(label: label, child: child);
  }
}
