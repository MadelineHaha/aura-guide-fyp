import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../doctor/widgets/doctor_theme.dart';
import '../services/caregiver_emergency_service.dart';
import '../services/caregiver_patients_service.dart';

class CaregiverDashboardPanel extends StatelessWidget {
  const CaregiverDashboardPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final patientsService = CaregiverPatientsService();
    final emergencyService = CaregiverEmergencyService();

    return StreamBuilder(
      stream: patientsService.watchConnectedPatients(),
      builder: (context, patientsSnap) {
        final patientCount = patientsSnap.data?.length ?? 0;
        return StreamBuilder(
          stream: emergencyService.watchOpenAlerts(),
          builder: (context, alertsSnap) {
            final alertCount = alertsSnap.data?.length ?? 0;
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: DoctorTheme.accentCard(),
              child: Row(
                children: [
                  Expanded(
                    child: _StatBlock(
                      label: 'Connected patients',
                      value: patientCount.toString(),
                      icon: Icons.people_outline,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 48,
                    color: DoctorTheme.borderSoft,
                  ),
                  Expanded(
                    child: _StatBlock(
                      label: 'Active emergencies',
                      value: alertCount.toString(),
                      icon: Icons.emergency_outlined,
                      highlight: alertCount > 0,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final color = highlight ? Colors.red.shade300 : DoctorTheme.portalAccent;
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: highlight ? Colors.red.shade200 : Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.subtext, fontSize: 12),
        ),
      ],
    );
  }
}
