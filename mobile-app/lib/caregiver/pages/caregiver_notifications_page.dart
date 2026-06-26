import 'package:flutter/material.dart';

import '../../doctor/widgets/doctor_empty_state.dart';
import '../../doctor/widgets/doctor_page_scaffold.dart';
import '../../doctor/widgets/doctor_theme.dart';
import '../../theme/app_colors.dart';
import '../services/caregiver_notifications_service.dart';
import 'caregiver_communication_page.dart';
import 'caregiver_emergency_page.dart';

class CaregiverNotificationsPage extends StatelessWidget {
  const CaregiverNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CaregiverNotificationsService();
    return DoctorPageScaffold(
      title: 'Notifications',
      body: StreamBuilder<List<CaregiverNotificationItem>>(
        stream: service.watchNotifications(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const DoctorEmptyState(
              icon: Icons.notifications_none_outlined,
              message: 'No new notifications',
              detail: 'Emergency alerts and unread messages will appear here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return _NotificationTile(item: item);
            },
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item});

  final CaregiverNotificationItem item;

  @override
  Widget build(BuildContext context) {
    final isEmergency = item.kind == CaregiverNotificationKind.emergency;
    final accent = isEmergency ? Colors.red.shade300 : DoctorTheme.portalAccent;

    return Material(
      color: DoctorTheme.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: DoctorTheme.cardRadius,
        side: BorderSide(
          color: isEmergency
              ? DoctorTheme.dangerBorder.withValues(alpha: 0.5)
              : DoctorTheme.borderSoft,
        ),
      ),
      child: InkWell(
        borderRadius: DoctorTheme.cardRadius,
        onTap: () {
          final page = isEmergency
              ? const CaregiverEmergencyPage()
              : const CaregiverCommunicationPage();
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (context) => page),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isEmergency
                      ? Icons.emergency_outlined
                      : Icons.forum_outlined,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      style: const TextStyle(
                        color: AppColors.subtext,
                        fontSize: 13,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
