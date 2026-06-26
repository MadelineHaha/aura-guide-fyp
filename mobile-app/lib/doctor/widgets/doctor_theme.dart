import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Doctor portal visual tokens — black/teal palette aligned with the patient app.
abstract final class DoctorTheme {
  static const portalAccent = Color(0xFF7ED4D5);
  static const portalGlow = Color(0xFF226A6C);
  static const surface = Color(0xFF121212);
  static const surfaceElevated = Color(0xFF1A1A1A);
  static const surfaceHighlight = Color(0xFF142B2C);
  static const borderSoft = Color(0xFF2A3A3A);
  static const borderAccent = Color(0xFF3D8E96);
  static const dangerSurface = Color(0xFF2A1515);
  static const dangerBorder = Color(0xFFE57373);

  static const modulePatients = Color(0xFF49BFC5);
  static const moduleRecords = Color(0xFF3E99F7);
  static const moduleMedications = Color(0xFF9DDC3D);
  static const moduleAppointments = Color(0xFF59C6D1);
  static const moduleCommunication = Color(0xFF63C3C4);

  static BorderRadius get cardRadius => BorderRadius.circular(16);
  static BorderRadius get tileRadius => BorderRadius.circular(14);

  static BoxDecoration surfaceCard({Color? tint}) {
    return BoxDecoration(
      color: tint ?? surfaceElevated,
      borderRadius: cardRadius,
      border: Border.all(color: borderSoft),
    );
  }

  static BoxDecoration accentCard() {
    return BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF163436), Color(0xFF0D1A1B)],
      ),
      borderRadius: cardRadius,
      border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
    );
  }

  static String greetingForHour(int hour) {
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
