import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// WhatsApp-style centered date pill above a group of messages.
class ChatDateDivider extends StatelessWidget {
  const ChatDateDivider({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF1E2E2F),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2F4546)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.subtext,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}
