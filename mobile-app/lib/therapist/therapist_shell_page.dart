import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth_session.dart';
import '../doctor/pages/doctor_communication_page.dart';
import '../l10n/app_localizations.dart';
import '../services/communication_service.dart';
import '../services/doctor_patients_service.dart';
import '../services/staff_profile_service.dart';
import '../start_page.dart';
import '../theme/app_colors.dart';
import '../utils/clinic_datetime.dart';
import '../utils/localized_date_format.dart';
import '../widgets/accessible_focus_region.dart';
import '../staff_notifications_page.dart';
import '../services/staff_notifications_service.dart';
import '../doctor/widgets/doctor_theme.dart';
import '../widgets/app_back_button.dart';
import '../widgets/portal_notification_bell.dart';
import '../widgets/app_menu_tile.dart';
import 'pages/therapist_patients_page.dart';
import 'pages/therapist_rehab_plans_page.dart';
import 'pages/therapist_therapy_sessions_page.dart';
import 'widgets/therapist_dashboard_panel.dart';

class TherapistShellPage extends StatefulWidget {
  const TherapistShellPage({super.key});

  static final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  State<TherapistShellPage> createState() => _TherapistShellPageState();
}

class _TherapistShellPageState extends State<TherapistShellPage> {
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
    TherapistShellPage.scaffoldKey.currentState?.openDrawer();
  }

  void _closeDrawer() {
    TherapistShellPage.scaffoldKey.currentState?.closeDrawer();
  }

  void _push(Widget page) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: TherapistShellPage.scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: _TherapistDrawer(onLogout: _logout, onClose: _closeDrawer),
      drawerEnableOpenDragGesture: false,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TherapistHeader(onMenuTap: _openDrawer),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const TherapistDashboardPanel(),
                      const SizedBox(height: 20),
                      const Text(
                        'Modules',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 12),
                      GridView.count(
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.02,
                        children: [
                          StreamBuilder(
                        stream: _patientsService.watchPatients(),
                        builder: (context, snap) {
                          final count = snap.data?.length ?? 0;
                          return AppMenuTile(
                            title: 'Patients',
                            subtitle: count == 1 ? '1 patient' : '$count patients',
                            icon: Icons.people_outline,
                            border: const Color(0xFF49BFC5),
                            tile: const Color(0xFF12363B),
                            iconCircle: const Color(0xFF226A6C),
                            onTap: () => _push(const TherapistPatientsPage()),
                          );
                        },
                      ),
                      AppMenuTile(
                        title: 'Therapy Sessions',
                        subtitle: 'Record session details',
                        icon: Icons.fitness_center_outlined,
                        border: const Color(0xFF9DDC3D),
                        tile: const Color(0xFF263913),
                        iconCircle: const Color(0xFF5C8D29),
                        onTap: () =>
                            _push(const TherapistTherapySessionsPage()),
                      ),
                      AppMenuTile(
                        title: 'Rehab Plans',
                        subtitle: 'Plan milestone sessions',
                        icon: Icons.event_note_outlined,
                        border: const Color(0xFFC88423),
                        tile: const Color(0xFF3D2A10),
                        iconCircle: const Color(0xFF885B1F),
                        onTap: () => _push(const TherapistRehabPlansPage()),
                      ),
                      StreamBuilder<int>(
                        stream:
                            _communicationService.watchUnreadMessageCountForStaff(),
                        builder: (context, snap) {
                          final unread = snap.data ?? 0;
                          final subtitle = unread <= 0
                              ? 'No unread messages'
                              : unread == 1
                                  ? '1 unread message'
                                  : '$unread unread messages';
                          return AppMenuTile(
                            title: 'Communication',
                            subtitle: subtitle,
                            icon: Icons.forum_outlined,
                            border: const Color(0xFF59C6D1),
                            tile: const Color(0xFF19393D),
                            iconCircle: const Color(0xFF3D8E96),
                            onTap: () =>
                                _push(const DoctorCommunicationPage()),
                          );
                        },
                      ),
                        ],
                      ),
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

class _TherapistHeader extends StatelessWidget {
  const _TherapistHeader({required this.onMenuTap});

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
    final date = ClinicDateTime.nowClinic();
    final displayDate = LocalizedDateFormat.displayDate(date, languageCode);
    final greeting = DoctorTheme.greetingForHour(date.hour);

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
                    name.isEmpty ? 'Therapist' : name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    staffId.isNotEmpty
                        ? 'Staff ID: $staffId • $displayDate'
                        : displayDate,
                    style: const TextStyle(color: AppColors.subtext, fontSize: 13),
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

class _TherapistDrawer extends StatelessWidget {
  const _TherapistDrawer({
    required this.onLogout,
    required this.onClose,
  });

  final VoidCallback onLogout;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final staffService = StaffProfileService();
    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.74,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(18)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
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
                  name.isNotEmpty ? name[0].toUpperCase() : 'T';

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 34,
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
                  const SizedBox(height: 18),
                  Text(
                    'Hello, $name',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Staff ID: $staffId',
                    style: const TextStyle(
                      color: Color(0xFFD0D0D0),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
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
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFF303030), height: 1),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        onClose();
                        onLogout();
                      },
                      icon: const Icon(Icons.logout),
                      label: const Text('Log Out'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF3C1111),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
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
