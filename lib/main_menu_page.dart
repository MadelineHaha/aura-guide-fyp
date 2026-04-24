import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'my_profile_page.dart';
import 'start_page.dart';

class MainMenuPage extends StatelessWidget {
  const MainMenuPage({super.key});

  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _text = Color(0xFFEFEFEF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      drawer: const _MainMenuDrawer(),
      drawerEnableOpenDragGesture: true,
      drawerEdgeDragWidth: 96,
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
              const Text(
                'MAIN MENU',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
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
                  children: const [
                    _MenuTile(
                      title: 'Appointments',
                      subtitle: '2 upcoming',
                      icon: Icons.calendar_today_outlined,
                      border: Color(0xFF49BFC5),
                      tile: Color(0xFF12363B),
                      iconCircle: Color(0xFF226A6C),
                    ),
                    _MenuTile(
                      title: 'Health Records',
                      subtitle: '4 records',
                      icon: Icons.description_outlined,
                      border: Color(0xFF3E99F7),
                      tile: Color(0xFF19324F),
                      iconCircle: Color(0xFF2C4F7F),
                    ),
                    _MenuTile(
                      title: 'Medications',
                      subtitle: '3 remaining today',
                      icon: Icons.link_outlined,
                      border: Color(0xFF9DDC3D),
                      tile: Color(0xFF263913),
                      iconCircle: Color(0xFF5C8D29),
                    ),
                    _MenuTile(
                      title: 'Emergency SOS',
                      subtitle: 'Tap for help',
                      icon: Icons.info_outline,
                      border: Color(0xFFE13636),
                      tile: Color(0xFF3C1111),
                      iconCircle: Color(0xFF8E2626),
                    ),
                    _MenuTile(
                      title: 'Navigation',
                      subtitle: 'AI obstacle detection\nand AR guidance',
                      icon: Icons.near_me_outlined,
                      border: Color(0xFFC88423),
                      tile: Color(0xFF3D2A10),
                      iconCircle: Color(0xFF885B1F),
                    ),
                    _MenuTile(
                      title: 'Communication',
                      subtitle: '1 new message',
                      icon: Icons.forum_outlined,
                      border: Color(0xFF59C6D1),
                      tile: Color(0xFF19393D),
                      iconCircle: Color(0xFF3D8E96),
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

class _HeaderSection extends StatelessWidget {
  const _HeaderSection();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Good morning,',
                style: TextStyle(color: MainMenuPage._subtext, fontSize: 15),
              ),
              SizedBox(height: 2),
              Text(
                'Madeline',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Monday, 16 March 2026',
                style: TextStyle(color: MainMenuPage._subtext, fontSize: 15),
              ),
            ],
          ),
        ),
        Container(
          width: 68,
          height: 68,
          decoration: const BoxDecoration(
            color: Color(0xFF50BDC5),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.notifications_none_rounded,
            color: Colors.white,
            size: 30,
          ),
        ),
      ],
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard();

  @override
  Widget build(BuildContext context) {
    return Container(
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
                    color: MainMenuPage._subtext,
                    fontSize: 14,
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

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.border,
    required this.tile,
    required this.iconCircle,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color border;
  final Color tile;
  final Color iconCircle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title is coming soon.')),
        );
      },
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
                  color: MainMenuPage._text,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: MainMenuPage._subtext,
                  fontSize: 14,
                  height: 1.2,
                ),
              ),
            ],
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
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white70),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF3B3B3B),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Hello, Madeline!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Patient ID: U00001',
                style: TextStyle(
                  color: Color(0xFFD0D0D0),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
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
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
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
                  Navigator.of(context).pop();
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
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Settings is coming soon.')),
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
              const SizedBox(height: 14),
              Center(
                child: SizedBox(
                  width: 120,
                  child: FilledButton.icon(
                    onPressed: () async {
                      await FirebaseAuth.instance.signOut();
                      if (!context.mounted) return;
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute<void>(
                          builder: (context) => const StartPage(),
                        ),
                        (route) => false,
                      );
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
    return InkWell(
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
    );
  }
}
