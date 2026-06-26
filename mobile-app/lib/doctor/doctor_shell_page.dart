import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth_session.dart';
import '../l10n/app_localizations.dart';
import '../services/communication_service.dart';
import '../services/doctor_patients_service.dart';
import '../services/staff_notifications_service.dart';
import '../services/staff_profile_service.dart';
import '../start_page.dart';
import '../theme/app_colors.dart';
import '../utils/clinic_datetime.dart';
import '../utils/localized_date_format.dart';
import '../widgets/accessible_focus_region.dart';
import '../widgets/app_back_button.dart';
import '../staff_notifications_page.dart';
import '../widgets/portal_notification_bell.dart';
import 'pages/doctor_appointments_page.dart';
import 'pages/doctor_communication_page.dart';
import 'pages/doctor_medical_records_page.dart';
import 'pages/doctor_medications_page.dart';
import 'pages/doctor_patients_page.dart';
import 'widgets/doctor_dashboard_panel.dart';
import 'widgets/doctor_module_tile.dart';
import 'widgets/doctor_section_header.dart';
import 'widgets/doctor_theme.dart';

class DoctorShellPage extends StatefulWidget {
  const DoctorShellPage({super.key});

  static final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  State<DoctorShellPage> createState() => _DoctorShellPageState();
}

class _DoctorShellPageState extends State<DoctorShellPage> {
  final _patientsService = DoctorPatientsService();
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
    DoctorShellPage.scaffoldKey.currentState?.openDrawer();
  }

  void _closeDrawer() {
    DoctorShellPage.scaffoldKey.currentState?.closeDrawer();
  }

  void _push(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: DoctorShellPage.scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: _DoctorDrawer(onLogout: _logout, onClose: _closeDrawer),
      drawerEnableOpenDragGesture: false,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DoctorHeader(onMenuTap: _openDrawer),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const DoctorDashboardPanel(),
                      const SizedBox(height: 24),
                      const DoctorSectionHeader(
                        title: 'Quick access',
                        subtitle: 'Open a module to manage care',
                      ),
                      const SizedBox(height: 14),
                      StreamBuilder(
                        stream: _patientsService.watchPatients(),
                        builder: (context, snap) {
                          final count = snap.data?.length ?? 0;
                          return _ModuleGrid(
                            patientCount: count,
                            unreadMessages: _communicationService
                                .watchUnreadMessageCountForStaff(),
                            onPatients: () => _push(const DoctorPatientsPage()),
                            onRecords: () =>
                                _push(const DoctorMedicalRecordsPage()),
                            onMedications: () =>
                                _push(const DoctorMedicationsPage()),
                            onAppointments: () =>
                                _push(const DoctorAppointmentsPage()),
                            onCommunication: () =>
                                _push(const DoctorCommunicationPage()),
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
    required this.unreadMessages,
    required this.onPatients,
    required this.onRecords,
    required this.onMedications,
    required this.onAppointments,
    required this.onCommunication,
  });

  final int patientCount;
  final Stream<int> unreadMessages;
  final VoidCallback onPatients;
  final VoidCallback onRecords;
  final VoidCallback onMedications;
  final VoidCallback onAppointments;
  final VoidCallback onCommunication;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: unreadMessages,
      builder: (context, snap) {
        final unread = snap.data ?? 0;
        final commSubtitle = unread <= 0
            ? 'Messages with patients'
            : unread == 1
                ? '1 unread message'
                : '$unread unread messages';

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
                  ? '1 active patient'
                  : '$patientCount active patients',
              icon: Icons.people_outline,
              accent: DoctorTheme.modulePatients,
              onTap: onPatients,
            ),
            DoctorModuleTile(
              title: 'Medical Records',
              subtitle: 'History & clinical notes',
              icon: Icons.description_outlined,
              accent: DoctorTheme.moduleRecords,
              onTap: onRecords,
            ),
            DoctorModuleTile(
              title: 'Medications',
              subtitle: 'Prescriptions & dosing',
              icon: Icons.medication_outlined,
              accent: DoctorTheme.moduleMedications,
              onTap: onMedications,
            ),
            DoctorModuleTile(
              title: 'Appointments',
              subtitle: 'View your schedule',
              icon: Icons.calendar_today_outlined,
              accent: DoctorTheme.moduleAppointments,
              onTap: onAppointments,
            ),
            DoctorModuleTile(
              title: 'Communication',
              subtitle: commSubtitle,
              icon: Icons.forum_outlined,
              accent: DoctorTheme.moduleCommunication,
              badge: unread > 0 ? '$unread' : null,
              onTap: onCommunication,
            ),
          ],
        );
      },
    );
  }
}

class _DoctorHeader extends StatelessWidget {
  const _DoctorHeader({required this.onMenuTap});

  final VoidCallback onMenuTap;

  void _openNotifications(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const StaffNotificationsPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final staffService = StaffProfileService();
    final notificationsService = StaffNotificationsService();
    final languageCode = AppLocalizations.of(context).languageCode;
    final now = ClinicDateTime.nowClinic();
    final displayDate = LocalizedDateFormat.displayDate(now, languageCode);
    final greeting = DoctorTheme.greetingForHour(now.hour);

    return StreamBuilder<Map<String, dynamic>>(
      stream: staffService.watchCurrentProfile(),
      initialData: const {},
      builder: (context, snapshot) {
        final profile = snapshot.data ?? const {};
        final name = StaffProfileService.displayName(profile);
        final staffId = StaffProfileService.staffIdFromData(profile) ?? '';

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
                    name.isEmpty ? 'Doctor' : name,
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
                      if (staffId.isNotEmpty)
                        _InfoChip(
                          icon: Icons.badge_outlined,
                          label: staffId,
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

class _DoctorDrawer extends StatelessWidget {
  const _DoctorDrawer({
    required this.onLogout,
    required this.onClose,
  });

  final VoidCallback onLogout;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final staffService = StaffProfileService();
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
            stream: staffService.watchCurrentProfile(),
            initialData: const {},
            builder: (context, snapshot) {
              final profile = snapshot.data ?? const {};
              final name = StaffProfileService.displayName(profile);
              final staffId =
                  StaffProfileService.staffIdFromData(profile) ?? '—';
              final email = FirebaseAuth.instance.currentUser?.email ?? '';
              final initial =
                  name.isNotEmpty ? name[0].toUpperCase() : 'D';

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
                            colors: [DoctorTheme.portalGlow, DoctorTheme.portalAccent],
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
                    'Doctor Portal',
                    style: TextStyle(
                      color: DoctorTheme.portalAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name.isEmpty ? 'Doctor' : name,
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
                          'Staff ID: $staffId',
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
                            color: DoctorTheme.dangerBorder.withValues(alpha: 0.4),
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
