import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'doctor_theme.dart';

class DoctorEmptyState extends StatelessWidget {
  const DoctorEmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.detail,
  });

  final IconData icon;
  final String message;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: DoctorTheme.surfaceHighlight,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: DoctorTheme.portalAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Icon(icon, color: DoctorTheme.portalAccent, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.subtext, fontSize: 14),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
