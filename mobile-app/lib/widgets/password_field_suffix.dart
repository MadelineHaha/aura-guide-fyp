import 'package:flutter/material.dart';

import 'listening_mic_button.dart';

/// Eye toggle plus optional mic control for password fields.
class PasswordFieldSuffix extends StatelessWidget {
  const PasswordFieldSuffix({
    super.key,
    required this.obscured,
    required this.onToggleObscured,
    this.onMic,
    this.micListening = false,
    this.micSize = 44,
    this.showMic = true,
    this.iconColor = Colors.white70,
    this.micWidget,
  });

  final bool obscured;
  final VoidCallback onToggleObscured;
  final VoidCallback? onMic;
  final bool micListening;
  final double micSize;
  final bool showMic;
  final Color iconColor;
  final Widget? micWidget;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onToggleObscured,
          tooltip: obscured ? 'Show password' : 'Hide password',
          icon: Icon(
            obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: iconColor,
            size: 22,
          ),
        ),
        if (showMic)
          micWidget ??
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ListeningMicButton(
                  listening: micListening,
                  onPressed: onMic ?? () {},
                  size: micSize,
                ),
              ),
      ],
    );
  }
}
