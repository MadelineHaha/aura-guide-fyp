import 'package:flutter/material.dart';

import '../../models/doctor_patient_summary.dart';
import '../../theme/app_colors.dart';
import 'doctor_theme.dart';

class DoctorPatientListTile extends StatelessWidget {
  const DoctorPatientListTile({
    super.key,
    required this.patient,
    required this.onTap,
  });

  final DoctorPatientSummary patient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initial =
        patient.name.isNotEmpty ? patient.name[0].toUpperCase() : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: DoctorTheme.surfaceCard(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: DoctorTheme.cardRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        DoctorTheme.portalGlow,
                        DoctorTheme.portalAccent.withValues(alpha: 0.7),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        patient.patientId,
                        style: const TextStyle(
                          color: DoctorTheme.portalAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (patient.email.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          patient.email,
                          style: const TextStyle(
                            color: AppColors.subtext,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: DoctorTheme.surfaceHighlight,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: DoctorTheme.borderSoft),
                  ),
                  child: const Icon(
                    Icons.chevron_right,
                    color: AppColors.subtext,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
