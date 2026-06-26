import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../auth_session.dart';
import '../doctor/widgets/doctor_module_tile.dart';
import '../doctor/widgets/doctor_section_header.dart';
import '../doctor/widgets/doctor_theme.dart';
import '../services/communication_service.dart';
import '../start_page.dart';
import '../theme/app_colors.dart';
import '../utils/clinic_datetime.dart';
import '../utils/localized_date_format.dart';
import '../widgets/accessible_focus_region.dart';
import '../widgets/app_back_button.dart';
import 'pages/caregiver_communication_page.dart';
import 'pages/caregiver_emergency_page.dart';
import 'pages/caregiver_patients_page.dart';
import 'services/caregiver_emergency_service.dart';
import 'services/caregiver_patients_service.dart';
import 'services/caregiver_profile_service.dart';
import 'widgets/caregiver_dashboard_panel.dart';
import 'pages/caregiver_notifications_page.dart';
import 'services/caregiver_notifications_service.dart';
import '../widgets/portal_notification_bell.dart';

class CaregiverShellPage extends StatefulWidget {
  const CaregiverShellPage({super.key});

  static final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  State<CaregiverShellPage> createState() => _CaregiverShellPageState();
}

class _CaregiverShellPageState extends State<CaregiverShellPage> {
  final _patientsService = CaregiverPatientsService();
  final _emergencyService = CaregiverEmergencyService();
  final _communicationService = CommunicationService();

  Future<void> _logout() async {
    AuthSession.markExplicitSignOut();
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (context) => const StartPage()),
        (route) => false,
      );
    }
  }

  void _openDrawer() {
    CaregiverShellPage.scaffoldKey.currentState?.openDrawer();
  }

  void _closeDrawer() {
    CaregiverShellPage.scaffoldKey.currentState?.closeDrawer();
  }

  void _push(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: CaregiverShellPage.scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: _CaregiverDrawer(onLogout: _logout, onClose: _closeDrawer),
      drawerEnableOpenDragGesture: false,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CaregiverHeader(onMenuTap: _openDrawer),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const CaregiverDashboardPanel(),
                      const SizedBox(height: 24),
                      const DoctorSectionHeader(
                        title: 'Quick access',
                        subtitle: 'Monitor and support connected patients',
                      ),
                      const SizedBox(height: 14),
                      StreamBuilder(
                        stream: _patientsService.watchConnectedPatients(),
                        builder: (context, patientsSnap) {
                          final patientCount = patientsSnap.data?.length ?? 0;
                          return StreamBuilder(
                            stream: _emergencyService.watchOpenAlerts(),
                            builder: (context, alertsSnap) {
                              final alertCount = alertsSnap.data?.length ?? 0;
                              return StreamBuilder<int>(
                                stream: _communicationService
                                    .watchUnreadMessageCountForCaregiver(),
                                builder: (context, unreadSnap) {
                                  final unread = unreadSnap.data ?? 0;
                                  return _ModuleGrid(
                                    patientCount: patientCount,
                                    alertCount: alertCount,
                                    unreadMessages: unread,
                                    onPatients: () =>
                                        _push(const CaregiverPatientsPage()),
                                    onEmergency: () =>
                                        _push(const CaregiverEmergencyPage()),
                                    onCommunication: () => _push(
                                      const CaregiverCommunicationPage(),
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModuleGrid extends StatelessWidget {
  const _ModuleGrid({
    required this.patientCount,
    required this.alertCount,
    required this.unreadMessages,
    required this.onPatients,
    required this.onEmergency,
    required this.onCommunication,
  });

  final int patientCount;
  final int alertCount;
  final int unreadMessages;
  final VoidCallback onPatients;
  final VoidCallback onEmergency;
  final VoidCallback onCommunication;

  @override
  Widget build(BuildContext context) {
    final commSubtitle = unreadMessages <= 0
        ? 'Messages with patients'
        : unreadMessages == 1
            ? '1 unread message'
            : '$unreadMessages unread messages';

    return GridView.count(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.05,
      children: [
        DoctorModuleTile(
          title: 'Patients',
          subtitle: patientCount == 1
              ? '1 connected patient'
              : '$patientCount connected patients',
          icon: Icons.people_outline,
          accent: DoctorTheme.modulePatients,
          onTap: onPatients,
        ),
        DoctorModuleTile(
          title: 'Emergency',
          subtitle: alertCount == 0
              ? 'No active alerts'
              : alertCount == 1
                  ? '1 active alert'
                  : '$alertCount active alerts',
          icon: Icons.emergency_outlined,
          accent: Colors.red.shade300,
          badge: alertCount > 0 ? '$alertCount' : null,
          onTap: onEmergency,
        ),
        DoctorModuleTile(
          title: 'Communication',
          subtitle: commSubtitle,
          icon: Icons.forum_outlined,
          accent: DoctorTheme.moduleCommunication,
          badge: unreadMessages > 0 ? '$unreadMessages' : null,
          onTap: onCommunication,
        ),
      ],
    );
  }
}

class _CaregiverHeader extends StatelessWidget {
  const _CaregiverHeader({required this.onMenuTap});

  final VoidCallback onMenuTap;

  void _openNotifications(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const CaregiverNotificationsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileService = CaregiverProfileService();
    final notificationsService = CaregiverNotificationsService();
    final now = ClinicDateTime.nowClinic();
    final languageCode = AppLocalizations.of(context).languageCode;
    final displayDate = LocalizedDateFormat.displayDate(now, languageCode);
    final greeting = DoctorTheme.greetingForHour(now.hour);

    return StreamBuilder<Map<String, dynamic>>(
      stream: profileService.watchCurrentProfile(),
      initialData: const {},
      builder: (context, snapshot) {
        final profile = snapshot.data ?? const {};
        final name = CaregiverProfileService.displayName(profile);
        final caregiverId =
            CaregiverProfileService.caregiverIdFromData(profile) ?? '';

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AccessibleFocusRegion(
              label: 'Open menu',
              onActivate: onMenuTap,
              child: Material(
                color: DoctorTheme.surfaceElevated,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: DoctorTheme.borderSoft),
                ),
                child: InkWell(
                  onTap: onMenuTap,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: Icon(Icons.menu, color: Colors.white, size: 24),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    greeting,
                    style: const TextStyle(
                      color: DoctorTheme.portalAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name.isEmpty ? 'Caregiver' : name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (caregiverId.isNotEmpty)
                        _InfoChip(
                          icon: Icons.badge_outlined,
                          label: caregiverId,
                        ),
                      _InfoChip(
                        icon: Icons.calendar_today_outlined,
                        label: displayDate,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            StreamBuilder<int>(
              stream: notificationsService.watchBadgeCount(),
              initialData: 0,
              builder: (context, countSnap) {
                return PortalNotificationBell(
                  unreadCount: countSnap.data ?? 0,
                  onTap: () => _openNotifications(context),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: DoctorTheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DoctorTheme.borderSoft),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.subtext),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: AppColors.subtext, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _CaregiverDrawer extends StatelessWidget {
  const _CaregiverDrawer({
    required this.onLogout,
    required this.onClose,
  });

  final VoidCallback onLogout;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final profileService = CaregiverProfileService();
    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.78,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: StreamBuilder<Map<String, dynamic>>(
            stream: profileService.watchCurrentProfile(),
            initialData: const {},
            builder: (context, snapshot) {
              final profile = snapshot.data ?? const {};
              final name = CaregiverProfileService.displayName(profile);
              final caregiverId =
                  CaregiverProfileService.caregiverIdFromData(profile) ?? '—';
              final email = FirebaseAuth.instance.currentUser?.email ?? '';
              final initial =
                  name.isNotEmpty ? name[0].toUpperCase() : 'C';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              DoctorTheme.portalGlow,
                              DoctorTheme.portalAccent,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      AppBackButton(
                        style: AppBackButtonStyle.filled,
                        color: Colors.white70,
                        onPressed: onClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Caregiver Portal',
                    style: TextStyle(
                      color: DoctorTheme.portalAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name.isEmpty ? 'Caregiver' : name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: DoctorTheme.surfaceCard(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Caregiver ID: $caregiverId',
                          style: const TextStyle(
                            color: AppColors.subtext,
                            fontSize: 13,
                          ),
                        ),
                        if (email.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            email,
                            style: const TextStyle(
                              color: AppColors.subtext,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        onClose();
                        onLogout();
                      },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Log Out'),
                      style: FilledButton.styleFrom(
                        backgroundColor: DoctorTheme.dangerSurface,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color:
                                DoctorTheme.dangerBorder.withValues(alpha: 0.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
