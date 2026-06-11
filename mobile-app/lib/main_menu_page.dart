import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'appointments_page.dart';
import 'emergency_sos_page.dart';
import 'medications_page.dart';
import 'auth_session.dart';
import 'communication_page.dart';
import 'navigation_page.dart';
import 'settings_page.dart';
import 'health_records_page.dart';
import 'my_profile_page.dart';
import 'services/appointments_service.dart';
import 'services/communication_service.dart';
import 'services/health_records_service.dart';
import 'services/medications_service.dart';
import 'widgets/accessible_focus_region.dart';
import 'widgets/app_back_button.dart';

class MainMenuPage extends StatefulWidget {
  const MainMenuPage({super.key});

  static final scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  State<MainMenuPage> createState() => _MainMenuPageState();
}

class _MainMenuPageState extends State<MainMenuPage> {
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _text = Color(0xFFEFEFEF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: MainMenuPage.scaffoldKey,
      backgroundColor: _bg,
      drawer: const _MainMenuDrawer(),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _HeaderSection(),
              const SizedBox(height: 14),
              const _ReminderCard(),
              const SizedBox(height: 18),
              const AccessibleFocusRegion(
                label: 'Main menu',
                child: Text(
                  'MAIN MENU',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: GridView.count(
                  physics: const BouncingScrollPhysics(),
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.02,
                  children: [
                    const _AppointmentsMenuTile(),
                    const _HealthRecordsMenuTile(),
                    const _MedicationsMenuTile(),
                    _MenuTile(
                      title: 'Emergency SOS',
                      subtitle: 'Tap for help',
                      icon: Icons.info_outline,
                      border: const Color(0xFFE13636),
                      tile: const Color(0xFF3C1111),
                      iconCircle: const Color(0xFF8E2626),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => const EmergencySosPage(),
                          ),
                        );
                      },
                    ),
                    _MenuTile(
                      title: 'Navigation',
                      subtitle: 'AI obstacle detection\nand AR guidance',
                      icon: Icons.near_me_outlined,
                      border: const Color(0xFFC88423),
                      tile: const Color(0xFF3D2A10),
                      iconCircle: const Color(0xFF885B1F),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => const NavigationPage(),
                          ),
                        );
                      },
                    ),
                    const _CommunicationMenuTile(),
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

class _HeaderSection extends StatelessWidget {
  const _HeaderSection();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: AccessibleFocusRegion(
            label: 'Good morning, Madeline. Monday, 16 March 2026.',
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good morning,',
                  style: TextStyle(
                    color: _MainMenuPageState._subtext,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Madeline',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Monday, 16 March 2026',
                  style: TextStyle(
                    color: _MainMenuPageState._subtext,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        _NotificationButton(),
      ],
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton();

  @override
  Widget build(BuildContext context) {
    return AccessibleFocusRegion(
      label: 'Notification',
      onActivate: () => _showComingSoon(context),
      child: Material(
        color: const Color(0xFF50BDC5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _showComingSoon(context),
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Text(
              'Notification',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notifications are coming soon.')),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard();

  @override
  Widget build(BuildContext context) {
    return AccessibleFocusRegion(
      label: 'Medication reminder. Vitamin D due at 12:00 PM.',
      onActivate: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (context) => const MedicationsPage(),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFF203536),
          border: Border.all(color: const Color(0xFF40595B), width: 1.1),
        ),
        child: const Row(
          children: [
            _IconCircle(
              bg: Color(0xFF2A666A),
              icon: Icons.medication_outlined,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Medication reminder',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Vitamin D due at 12:00 PM',
                    style: TextStyle(
                      color: _MainMenuPageState._subtext,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppointmentsMenuTile extends StatefulWidget {
  const _AppointmentsMenuTile();

  @override
  State<_AppointmentsMenuTile> createState() => _AppointmentsMenuTileState();
}

class _AppointmentsMenuTileState extends State<_AppointmentsMenuTile> {
  final _service = AppointmentsService();
  late final Stream<int> _countStream = _service.watchUpcomingAppointmentCount();

  static String _subtitleForCount(int count) {
    if (count <= 0) return 'No appointments upcoming';
    if (count == 1) return '1 appointment upcoming';
    return '$count appointments upcoming';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _countStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final subtitle = snapshot.hasError
            ? 'No appointments upcoming'
            : _subtitleForCount(count);

        return _MenuTile(
          title: 'Appointments',
          subtitle: subtitle,
          icon: Icons.calendar_today_outlined,
          border: const Color(0xFF49BFC5),
          tile: const Color(0xFF12363B),
          iconCircle: const Color(0xFF226A6C),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const AppointmentsPage(),
              ),
            );
          },
        );
      },
    );
  }
}

class _MedicationsMenuTile extends StatefulWidget {
  const _MedicationsMenuTile();

  @override
  State<_MedicationsMenuTile> createState() => _MedicationsMenuTileState();
}

class _MedicationsMenuTileState extends State<_MedicationsMenuTile> {
  final _service = MedicationsService();
  late final Stream<int> _remainingStream =
      _service.watchRemainingTodayCount();

  static String _subtitleForCount(int remaining) {
    if (remaining <= 0) return 'All taken today';
    if (remaining == 1) return '1 remaining today';
    return '$remaining remaining today';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _remainingStream,
      builder: (context, snapshot) {
        final remaining = snapshot.data ?? 0;
        final subtitle = snapshot.hasError
            ? 'No medications'
            : _subtitleForCount(remaining);

        return _MenuTile(
          title: 'Medications',
          subtitle: subtitle,
          icon: Icons.link_outlined,
          border: const Color(0xFF9DDC3D),
          tile: const Color(0xFF263913),
          iconCircle: const Color(0xFF5C8D29),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const MedicationsPage(),
              ),
            );
          },
        );
      },
    );
  }
}

class _HealthRecordsMenuTile extends StatefulWidget {
  const _HealthRecordsMenuTile();

  @override
  State<_HealthRecordsMenuTile> createState() => _HealthRecordsMenuTileState();
}

class _HealthRecordsMenuTileState extends State<_HealthRecordsMenuTile> {
  final _service = HealthRecordsService();
  late final Stream<int> _countStream =
      _service.watchForCurrentPatient().map((records) => records.length);

  static String _subtitleForCount(int count) {
    if (count <= 0) return 'No health record';
    if (count == 1) return '1 record';
    return '$count records';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _countStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final subtitle = snapshot.hasError
            ? 'No health record'
            : _subtitleForCount(count);

        return _MenuTile(
          title: 'Health Records',
          subtitle: subtitle,
          icon: Icons.description_outlined,
          border: const Color(0xFF3E99F7),
          tile: const Color(0xFF19324F),
          iconCircle: const Color(0xFF2C4F7F),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const HealthRecordsPage(),
              ),
            );
          },
        );
      },
    );
  }
}

class _CommunicationMenuTile extends StatefulWidget {
  const _CommunicationMenuTile();

  @override
  State<_CommunicationMenuTile> createState() => _CommunicationMenuTileState();
}

class _CommunicationMenuTileState extends State<_CommunicationMenuTile> {
  final _service = CommunicationService();
  late final Stream<int> _unreadStream = _service.watchUnreadMessageCount();

  static String _subtitleForCount(int count) {
    if (count <= 0) return 'No messages upcoming';
    if (count == 1) return '1 message upcoming';
    return '$count messages upcoming';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _unreadStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final subtitle = snapshot.hasError
            ? 'No messages upcoming'
            : _subtitleForCount(count);

        return _MenuTile(
          title: 'Communication',
          subtitle: subtitle,
          icon: Icons.forum_outlined,
          border: const Color(0xFF59C6D1),
          tile: const Color(0xFF19393D),
          iconCircle: const Color(0xFF3D8E96),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const CommunicationPage(),
              ),
            );
          },
        );
      },
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.border,
    required this.tile,
    required this.iconCircle,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color border;
  final Color tile;
  final Color iconCircle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    void onActivate() {
      if (onTap != null) {
        onTap!();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title is coming soon.')),
      );
    }

    return AccessibleFocusRegion(
      label: '$title. $subtitle',
      onActivate: onActivate,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onActivate,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: tile,
            border: Border.all(color: border, width: 1.4),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _IconCircle(bg: iconCircle, icon: icon),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _MainMenuPageState._text,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _MainMenuPageState._subtext,
                    fontSize: 14,
                    height: 1.2,
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

class _IconCircle extends StatelessWidget {
  const _IconCircle({required this.bg, required this.icon});

  final Color bg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white70, size: 34),
    );
  }
}

class _MainMenuDrawer extends StatelessWidget {
  const _MainMenuDrawer();

  void _closeDrawer(BuildContext context) {
    MainMenuPage.scaffoldKey.currentState?.closeDrawer();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.74,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(18)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF62C6CD),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'M',
                      style: TextStyle(
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
                    onPressed: () => _closeDrawer(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const AccessibleFocusRegion(
                label: 'Hello, Madeline. Patient ID U00001.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, Madeline!',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Patient ID: U00001',
                      style: TextStyle(
                        color: Color(0xFFD0D0D0),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF303030), height: 1),
              const SizedBox(height: 18),
              _DrawerAction(
                label: 'My Profile',
                bg: const Color(0xFF0D3F44),
                iconColor: const Color(0xFF66C2BD),
                icon: Icons.person_outline,
                onTap: () {
                  final navigator = Navigator.of(context);
                  _closeDrawer(context);
                  navigator.push(
                    MaterialPageRoute<void>(
                      builder: (context) => const MyProfilePage(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _DrawerAction(
                label: 'Emergency Contacts',
                bg: const Color(0xFF4A1111),
                iconColor: const Color(0xFFE34848),
                icon: Icons.phone_in_talk_outlined,
                onTap: () {
                  _closeDrawer(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Emergency Contacts is coming soon.'),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Center(
                child: SizedBox(
                  width: 120,
                  child: AccessibleFocusRegion(
                    label: 'Setting',
                    onActivate: () {
                      final navigator = Navigator.of(context);
                      _closeDrawer(context);
                      navigator.push(
                        MaterialPageRoute<void>(
                          builder: (context) => const SettingsPage(),
                        ),
                      );
                    },
                    child: FilledButton.icon(
                      onPressed: () {
                        final navigator = Navigator.of(context);
                        _closeDrawer(context);
                        navigator.push(
                          MaterialPageRoute<void>(
                            builder: (context) => const SettingsPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.settings_outlined, size: 20),
                      label: const Text('Setting'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF656565),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: SizedBox(
                  width: 120,
                  child: AccessibleFocusRegion(
                    label: 'Log Out',
                    onActivate: () async {
                      AuthSession.markExplicitSignOut();
                      await FirebaseAuth.instance.signOut();
                    },
                    child: FilledButton.icon(
                      onPressed: () async {
                        AuthSession.markExplicitSignOut();
                        await FirebaseAuth.instance.signOut();
                      },
                      icon: const Icon(Icons.logout, size: 20),
                      label: const Text('Log Out'),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE84343),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
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

class _DrawerAction extends StatelessWidget {
  const _DrawerAction({
    required this.label,
    required this.bg,
    required this.iconColor,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Color bg;
  final Color iconColor;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AccessibleFocusRegion(
      label: label,
      onActivate: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFE6E6E6),
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
