import 'package:flutter/material.dart';

import '../../models/therapy_session_item.dart';
import '../../services/staff_profile_service.dart';
import '../../services/therapy_sessions_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/therapist_page_scaffold.dart';

class TherapistReportsPage extends StatelessWidget {
  const TherapistReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final sessionsService = TherapySessionsService();
    final staffService = StaffProfileService();

    return TherapistPageScaffold(
      title: 'Reports',
      body: FutureBuilder<Map<String, dynamic>?>(
        future: staffService.loadCurrentProfile(),
        builder: (context, profileSnap) {
          final staffId = profileSnap.data != null
              ? StaffProfileService.staffIdFromData(profileSnap.data!)
              : null;

          if (staffId == null) {
            return const Center(
              child: Text(
                'Staff profile not found.',
                style: TextStyle(color: AppColors.subtext),
              ),
            );
          }

          return FutureBuilder<List<TherapySessionItem>>(
            future: sessionsService.fetchForStaff(staffId),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                );
              }

              final sessions = snap.data!;
              var completed = 0;
              var cancelled = 0;
              var noShow = 0;
              var improved = 0;
              var stable = 0;
              var training = 0;

              final latestStatusByPatient = <String, String>{};

              for (final session in sessions) {
                final status = session.status.trim().toLowerCase();
                if (status == 'done' || status == 'completed') {
                  completed++;
                  if (session.sessionStatus.isNotEmpty) {
                    latestStatusByPatient[session.patientId] =
                        session.sessionStatus;
                  }
                } else if (status == 'cancelled') {
                  cancelled++;
                } else if (status == 'missed' || status == 'no-show') {
                  noShow++;
                }
              }

              for (final progress in latestStatusByPatient.values) {
                if (progress == 'Improved') {
                  improved++;
                } else if (progress == 'Stable') {
                  stable++;
                } else if (progress == 'Requiring Additional Training') {
                  training++;
                }
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Therapy Activity',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ReportStatCard(label: 'Completed', value: '$completed'),
                    const SizedBox(height: 8),
                    _ReportStatCard(
                      label: 'Cancelled',
                      value: '$cancelled',
                      accent: Colors.redAccent,
                    ),
                    const SizedBox(height: 8),
                    _ReportStatCard(
                      label: 'No-show',
                      value: '$noShow',
                      accent: Colors.orangeAccent,
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Rehabilitation Progress',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ReportStatCard(label: 'Improved', value: '$improved'),
                    const SizedBox(height: 8),
                    _ReportStatCard(label: 'Stable', value: '$stable'),
                    const SizedBox(height: 8),
                    _ReportStatCard(
                      label: 'Requiring Additional Training',
                      value: '$training',
                      accent: Colors.amberAccent,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ReportStatCard extends StatelessWidget {
  const _ReportStatCard({
    required this.label,
    required this.value,
    this.accent,
  });

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: AppColors.subtext, fontSize: 14),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: accent ?? AppColors.accent,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }
}
