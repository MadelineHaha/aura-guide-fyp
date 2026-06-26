import 'package:flutter/material.dart';

import '../../models/doctor_patient_summary.dart';
import '../../models/therapy_session_item.dart';
import '../../services/doctor_patients_service.dart';
import '../../services/staff_profile_service.dart';
import '../../services/therapy_sessions_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/clinic_datetime.dart';

class TherapistDashboardPanel extends StatelessWidget {
  const TherapistDashboardPanel({super.key});

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final patientsService = DoctorPatientsService();
    final sessionsService = TherapySessionsService();
    final staffService = StaffProfileService();

    return FutureBuilder<Map<String, dynamic>?>(
      future: staffService.loadCurrentProfile(),
      builder: (context, profileSnap) {
        final staffId = profileSnap.data != null
            ? StaffProfileService.staffIdFromData(profileSnap.data!)
            : null;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Dashboard',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 12),
            StreamBuilder<List<DoctorPatientSummary>>(
              stream: patientsService.watchPatients(),
              builder: (context, patientsSnap) {
                final count = patientsSnap.data?.length ?? 0;
                return _StatCard(
                  icon: Icons.people_outline,
                  label: 'Active Patients',
                  value: count.toString(),
                );
              },
            ),
            const SizedBox(height: 12),
            if (staffId != null)
              FutureBuilder<List<TherapySessionItem>>(
                future: sessionsService.fetchForStaff(staffId),
                builder: (context, sessionsSnap) {
                  final sessions = sessionsSnap.data ?? [];
                  final today = ClinicDateTime.clinicDayStart(
                    ClinicDateTime.nowClinic(),
                  );
                  final todays = sessions.where((s) {
                    return ClinicDateTime.clinicDayStart(s.dateTime) == today;
                  }).toList();
                  return _StatCard(
                    icon: Icons.fitness_center_outlined,
                    label: "Today's Therapy Sessions",
                    value: todays.length.toString(),
                  );
                },
              ),
            const SizedBox(height: 16),
            const Text(
              "Today's Sessions",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            if (staffId == null)
              const Text(
                'Staff profile not found.',
                style: TextStyle(color: AppColors.subtext),
              )
            else
              FutureBuilder<List<TherapySessionItem>>(
                future: sessionsService.fetchForStaff(staffId),
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(
                          color: AppColors.accent,
                        ),
                      ),
                    );
                  }
                  final today = ClinicDateTime.clinicDayStart(
                    ClinicDateTime.nowClinic(),
                  );
                  final todays = snap.data!.where((s) {
                    return ClinicDateTime.clinicDayStart(s.dateTime) == today;
                  }).toList();

                  if (todays.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: const Text(
                        'No therapy sessions scheduled for today.',
                        style: TextStyle(color: AppColors.subtext),
                      ),
                    );
                  }

                  return Column(
                    children: todays.map((session) {
                      return Card(
                        color: const Color(0xFF12363B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: AppColors.accent.withValues(alpha: 0.5),
                          ),
                        ),
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const Icon(
                            Icons.fitness_center,
                            color: AppColors.accent,
                          ),
                          title: Text(
                            session.sessionName.isNotEmpty
                                ? session.sessionName
                                : 'Therapy Session',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            '${_formatDateTime(session.dateTime)} • ${session.status}',
                            style: const TextStyle(
                              color: AppColors.subtext,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF14242C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accent, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: AppColors.subtext, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
