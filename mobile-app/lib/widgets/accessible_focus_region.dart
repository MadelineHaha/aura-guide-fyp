import 'package:flutter/material.dart';

/// Exposes a labeled region to TalkBack / VoiceOver without custom navigation.
class AccessibleFocusRegion extends StatelessWidget {
  const AccessibleFocusRegion({
    super.key,
    required this.label,
    required this.child,
    this.onActivate,
  });

  final String label;
  final Widget child;
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) {
    if (onActivate != null) {
      return Semantics(
        label: label,
        button: true,
        onTap: onActivate,
        excludeSemantics: true,
        child: child,
      );
    }

    return Semantics(
      label: label,
      child: child,
    );
  }
}
