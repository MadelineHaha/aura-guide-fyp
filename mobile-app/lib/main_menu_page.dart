import 'dart:async';

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
import 'l10n/app_localizations.dart';
import 'my_profile_page.dart';
import 'models/medication_item.dart';
import 'services/appointments_service.dart';
import 'services/communication_service.dart';
import 'services/health_records_service.dart';
import 'services/medications_service.dart';
import 'services/medication_push_service.dart';
import 'notifications_page.dart';
import 'services/patient_call_session.dart';
import 'services/step_tracking_service.dart';
import 'widgets/daily_step_card.dart';
import 'services/user_profile_service.dart';
import 'utils/clinic_datetime.dart';
import 'utils/localized_date_format.dart';
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
  void initState() {
    super.initState();
    PatientCallSession.instance.ensureStarted();
    unawaited(StepTrackingService.instance.start());
    unawaited(MedicationPushService.instance.registerForReminders());
  }

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
              const DailyStepCard(),
              const SizedBox(height: 14),
              const _ReminderCard(),
              const SizedBox(height: 18),
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
                      title: context.l10n.t('emergencySos'),
                      subtitle: context.l10n.t('emergencySosSubtitle'),
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
                      title: context.l10n.t('navigation'),
                      subtitle: context.l10n.t('navigationSubtitle'),
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

  static ({String display, String spoken}) _todayLabels(BuildContext context) {
    final languageCode = AppLocalizations.of(context).languageCode;
    final date = ClinicDateTime.nowClinic();
    return (
      display: LocalizedDateFormat.displayDate(date, languageCode),
      spoken: LocalizedDateFormat.spokenDate(date, languageCode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileService = UserProfileService();
    return StreamBuilder<Map<String, dynamic>>(
      stream: profileService.watchForCurrentUser(),
      initialData: const {},
      builder: (context, snapshot) {
        final profile = snapshot.data ?? const {};
        final name = UserProfileService.greetingName(profile);
        final dates = _todayLabels(context);
        final a11yLabel = name.isEmpty
            ? context.l10n.t('goodMorningA11yLabelNoName', {
                'date': dates.spoken,
              })
            : context.l10n.t('goodMorningA11yLabel', {
                'name': name,
                'date': dates.spoken,
              });

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _MenuButton(),
            const SizedBox(width: 10),
            Expanded(
              child: AccessibleFocusRegion(
                label: a11yLabel,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.t('goodMorning'),
                      style: TextStyle(
                        color: _MainMenuPageState._subtext,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      name.isEmpty ? '…' : name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Semantics(
                      label: dates.spoken,
                      excludeSemantics: true,
                      child: Text(
                        dates.display,
                        style: TextStyle(
                          color: _MainMenuPageState._subtext,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            const _NotificationButton(),
          ],
        );
      },
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton();

  void _openDrawer(BuildContext context) {
    MainMenuPage.scaffoldKey.currentState?.openDrawer();
  }

  @override
  Widget build(BuildContext context) {
    return AccessibleFocusRegion(
      label: context.l10n.t('menuOpenHint'),
      onActivate: () => _openDrawer(context),
      child: Material(
        color: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF3A3A3A)),
        ),
        child: InkWell(
          onTap: () => _openDrawer(context),
          borderRadius: BorderRadius.circular(12),
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Icon(
              Icons.menu,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton();

  void _openNotifications(BuildContext context) {
    unawaited(MedicationPushService.instance.registerForReminders());
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const NotificationsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AccessibleFocusRegion(
      label: context.l10n.t('notification'),
      onActivate: () => _openNotifications(context),
      child: Material(
        color: const Color(0xFF50BDC5),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => _openNotifications(context),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Text(
              context.l10n.t('notification'),
              style: const TextStyle(
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
}

class _ReminderCard extends StatefulWidget {
  const _ReminderCard();

  @override
  State<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<_ReminderCard> {
  final _service = MedicationsService();
  late final Stream<List<MedicationItem>> _medicationsStream =
      _service.watchForCurrentPatient();

  void _openMedications() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => const MedicationsPage(),
      ),
    );
  }

  String _subtitle(
    BuildContext context, {
    required List<MedicationItem> items,
  }) {
    final next = MedicationsService.nextPendingToday(items);
    if (next != null) {
      return context.l10n.t('medicationDueAt', {
        'name': next.name,
        'time': next.scheduledTime,
      });
    }
    if (items.isNotEmpty) {
      return context.l10n.t('allTakenToday');
    }
    return context.l10n.t('medicationReminderNoneDue');
  }

  String _a11yLabel(
    BuildContext context, {
    required List<MedicationItem> items,
  }) {
    final next = MedicationsService.nextPendingToday(items);
    if (next != null) {
      return context.l10n.t('medicationReminderA11yDue', {
        'name': next.name,
        'time': next.scheduledTime,
      });
    }
    if (items.isNotEmpty) {
      return context.l10n.t('medicationReminderA11yAllTaken');
    }
    return context.l10n.t('medicationReminderA11yNone');
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<MedicationItem>>(
      stream: _medicationsStream,
      initialData: const [],
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        final subtitle = snapshot.hasError
            ? context.l10n.t('medicationReminderNoneDue')
            : _subtitle(context, items: items);
        final a11yLabel = snapshot.hasError
            ? context.l10n.t('medicationReminderA11yNone')
            : _a11yLabel(context, items: items);

        return AccessibleFocusRegion(
          label: a11yLabel,
          onActivate: _openMedications,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: const Color(0xFF203536),
              border: Border.all(color: const Color(0xFF40595B), width: 1.1),
            ),
            child: Row(
              children: [
                const _IconCircle(
                  bg: Color(0xFF2A666A),
                  icon: Icons.medication_outlined,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.t('medicationReminder'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
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
      },
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

  static String _subtitleForCount(BuildContext context, int count) {
    if (count <= 0) return context.l10n.t('noAppointmentsUpcoming');
    if (count == 1) return context.l10n.t('appointmentsUpcomingOne');
    return context.l10n.t('appointmentsUpcomingMany', {'count': count});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _countStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final subtitle = snapshot.hasError
            ? context.l10n.t('noAppointmentsUpcoming')
            : _subtitleForCount(context, count);

        return _MenuTile(
          title: context.l10n.t('appointments'),
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

  static String _subtitleForCount(BuildContext context, int remaining) {
    if (remaining <= 0) return context.l10n.t('allTakenToday');
    if (remaining == 1) return context.l10n.t('medicationsRemainingOne');
    return context.l10n.t('medicationsRemainingMany', {'remaining': remaining});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _remainingStream,
      builder: (context, snapshot) {
        final remaining = snapshot.data ?? 0;
        final subtitle = snapshot.hasError
            ? context.l10n.t('noMedications')
            : _subtitleForCount(context, remaining);

        return _MenuTile(
          title: context.l10n.t('medications'),
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

  static String _subtitleForCount(BuildContext context, int count) {
    if (count <= 0) return context.l10n.t('noHealthRecord');
    if (count == 1) return context.l10n.t('healthRecordsCountOne');
    return context.l10n.t('healthRecordsCountMany', {'count': count});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _countStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final subtitle = snapshot.hasError
            ? context.l10n.t('noHealthRecord')
            : _subtitleForCount(context, count);

        return _MenuTile(
          title: context.l10n.t('healthRecords'),
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

  static String _subtitleForCount(BuildContext context, int count) {
    if (count <= 0) return context.l10n.t('noMessagesUpcoming');
    if (count == 1) return context.l10n.t('messagesUpcomingOne');
    return context.l10n.t('messagesUpcomingMany', {'count': count});
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _unreadStream,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final subtitle = snapshot.hasError
            ? context.l10n.t('noMessagesUpcoming')
            : _subtitleForCount(context, count);

        return _MenuTile(
          title: context.l10n.t('communication'),
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
        SnackBar(
          content: Text(context.l10n.t('featureComingSoon', {'title': title})),
        ),
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

  String _helloLine(BuildContext context, Map<String, dynamic> profile) {
    final name = UserProfileService.greetingName(profile);
    if (name.isEmpty) return context.l10n.t('helloUserNoName');
    return context.l10n.t('helloUser', {'name': name});
  }

  String _patientIdLine(BuildContext context, Map<String, dynamic> profile) {
    final userId = UserProfileService.patientId(profile);
    if (userId.isEmpty) return context.l10n.t('patientIdUnavailable');
    return context.l10n.t('patientIdLabel', {'userId': userId});
  }

  String _drawerA11yLabel(BuildContext context, Map<String, dynamic> profile) {
    final name = UserProfileService.greetingName(profile);
    final userId = UserProfileService.patientId(profile);
    if (userId.isEmpty) {
      return name.isEmpty
          ? context.l10n.t('helloUserNoName')
          : context.l10n.t('helloUser', {'name': name});
    }
    if (name.isEmpty) {
      return context.l10n.t('helloUserPatientIdA11yNoName', {'userId': userId});
    }
    return context.l10n.t('helloUserPatientIdA11y', {
      'name': name,
      'userId': userId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileService = UserProfileService();
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
            stream: profileService.watchForCurrentUser(),
            initialData: const {},
            builder: (context, snapshot) {
              final profile = snapshot.data ?? const {};
              final avatarInitial = UserProfileService.avatarInitial(profile);

              return Column(
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
                        child: Text(
                          avatarInitial,
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
                        onPressed: () => _closeDrawer(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AccessibleFocusRegion(
                    label: _drawerA11yLabel(context, profile),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _helloLine(context, profile),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _patientIdLine(context, profile),
                          style: const TextStyle(
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
                    label: context.l10n.t('myProfile'),
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
                    label: context.l10n.t('emergencyContacts'),
                    bg: const Color(0xFF4A1111),
                    iconColor: const Color(0xFFE34848),
                    icon: Icons.phone_in_talk_outlined,
                    onTap: () {
                      _closeDrawer(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.l10n.t('emergencyContactsComingSoon'),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: SizedBox(
                      width: 120,
                      child: AccessibleFocusRegion(
                        label: context.l10n.t('setting'),
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
                          label: Text(context.l10n.t('setting')),
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
                        label: context.l10n.t('logOut'),
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
                          label: Text(context.l10n.t('logOut')),
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
              );
            },
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
