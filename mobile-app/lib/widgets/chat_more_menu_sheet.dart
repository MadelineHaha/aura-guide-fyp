import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class ChatMoreMenuOption {
  const ChatMoreMenuOption({
    required this.id,
    required this.icon,
    required this.label,
    this.color = AppColors.accent,
    this.destructive = false,
  });

  final String id;
  final IconData icon;
  final String label;
  final Color color;
  final bool destructive;
}

/// Bottom sheet with icon + label rows for chat overflow actions.
class ChatMoreMenuSheet extends StatelessWidget {
  const ChatMoreMenuSheet({super.key, required this.options});

  final List<ChatMoreMenuOption> options;

  static Future<String?> show(
    BuildContext context, {
    required List<ChatMoreMenuOption> options,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => ChatMoreMenuSheet(options: options),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF3A3A3A),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 8),
          ...options.map((option) {
            final color =
                option.destructive ? Colors.redAccent : option.color;
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(option.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(option.icon, color: color, size: 24),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Text(
                          option.label,
                          style: TextStyle(
                            color: color,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
