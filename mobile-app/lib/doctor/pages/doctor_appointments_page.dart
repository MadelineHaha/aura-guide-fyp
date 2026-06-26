import 'package:flutter/material.dart';

import '../../models/appointment_item.dart';
import '../../services/appointments_service.dart';
import '../../services/staff_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/clinic_datetime.dart';
import '../widgets/doctor_page_scaffold.dart';
import '../widgets/doctor_section_header.dart';
import '../widgets/doctor_theme.dart';

class DoctorAppointmentsPage extends StatelessWidget {
  const DoctorAppointmentsPage({super.key});

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final staffService = StaffProfileService();
    final apptService = AppointmentsService();

    return DoctorPageScaffold(
      title: 'Appointments',
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

          return FutureBuilder<List<AppointmentItem>>(
            future: apptService.fetchForStaff(staffId),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Text(
                    'Error: ${snap.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                );
              }

              final items = snap.data!;
              final now = ClinicDateTime.nowClinic();
              final upcoming = items
                  .where((a) => !ClinicDateTime.isBeforeNow(a.dateTime))
                  .toList();
              final past = items
                  .where((a) => ClinicDateTime.isBeforeNow(a.dateTime))
                  .toList()
                ..sort((a, b) => b.dateTime.compareTo(a.dateTime));

              if (items.isEmpty) {
                return const Center(
                  child: Text(
                    'No appointments scheduled.',
                    style: TextStyle(color: AppColors.subtext),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                children: [
                  if (upcoming.isNotEmpty) ...[
                    const DoctorSectionHeader(
                      title: 'Upcoming',
                      subtitle: 'Scheduled appointments',
                    ),
                    const SizedBox(height: 12),
                    ...upcoming.map((item) => _AppointmentCard(
                          item: item,
                          formatDateTime: _formatDateTime,
                          highlight: true,
                        )),
                    const SizedBox(height: 20),
                  ],
                  if (past.isNotEmpty) ...[
                    const DoctorSectionHeader(title: 'Past'),
                    const SizedBox(height: 12),
                    ...past.map((item) => _AppointmentCard(
                          item: item,
                          formatDateTime: _formatDateTime,
                        )),
                  ],
                  if (upcoming.isEmpty && past.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Text(
                        'No appointments as of ${_formatDateTime(now)}.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.subtext),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.item,
    required this.formatDateTime,
    this.highlight = false,
  });

  final AppointmentItem item;
  final String Function(DateTime) formatDateTime;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: highlight ? DoctorTheme.surfaceHighlight : DoctorTheme.surfaceElevated,
        borderRadius: DoctorTheme.cardRadius,
        border: Border.all(
          color: highlight
              ? DoctorTheme.portalAccent.withValues(alpha: 0.45)
              : DoctorTheme.borderSoft,
          width: 1.2,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: DoctorTheme.portalGlow.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.event, color: DoctorTheme.portalAccent, size: 22),
        ),
        title: Text(
          item.appointmentType,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${formatDateTime(item.dateTime)} • ${item.status}',
          style: const TextStyle(color: AppColors.subtext, fontSize: 13),
        ),
      ),
    );
  }
}
