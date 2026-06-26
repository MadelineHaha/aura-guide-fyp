import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'appointments_page.dart';
import 'emergency_sos_page.dart';
import 'medications_page.dart';
import 'auth_session.dart';
import 'start_page.dart';
import 'communication_page.dart';
import 'navigation_page.dart';
import 'settings_page.dart';
import 'app_route_observer.dart';
import 'services/voice_assistant_coordinator.dart';
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
import 'services/notifications_service.dart';
import 'services/patient_call_session.dart';
import 'services/step_tracking_service.dart';
import 'services/user_profile_service.dart';
import 'theme/app_colors.dart';
import 'doctor/widgets/doctor_module_tile.dart';
import 'doctor/widgets/doctor_section_header.dart';
import 'doctor/widgets/doctor_theme.dart';
import 'widgets/portal_notification_bell.dart';
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

class _MainMenuPageState extends State<MainMenuPage> with RouteAware {

  final PageController _pageController = PageController();
  int _currentTab = 0;

  // Two-finger swipe gesture tracking variables
  final Map<int, Offset> _pointerStarts = {};
  final Map<int, Offset> _pointerPositions = {};
  bool _gestureTriggered = false;

  @override
  void initState() {
    super.initState();
    PatientCallSession.instance.ensureStarted();
    unawaited(StepTrackingService.instance.start());
    unawaited(MedicationPushService.instance.registerForReminders());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      VoiceAssistantCoordinator.instance.setTopRouteLabel('MainMenuPage');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      VoiceAssistantCoordinator.instance.setTopRouteLabel('MainMenuPage');
    });
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _pageController.dispose();
    super.dispose();
  }

  void _switchToCategory(int index) {
    if (index < 0 || index > 1) return;
    if (_currentTab == index) return;

    setState(() {
      _currentTab = index;
    });

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointerStarts[event.pointer] = event.position;
    _pointerPositions[event.pointer] = event.position;
    if (_pointerStarts.length == 2) {
      // Reset start positions of both pointers to align tracking from this moment
      for (final id in _pointerStarts.keys) {
        _pointerStarts[id] = _pointerPositions[id] ?? _pointerStarts[id]!;
      }
      _gestureTriggered = false;
      setState(() {});
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pointerStarts.containsKey(event.pointer)) {
      _pointerPositions[event.pointer] = event.position;
      _evaluateGesture();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    final wasMulti = _pointerStarts.length >= 2;
    _pointerStarts.remove(event.pointer);
    _pointerPositions.remove(event.pointer);
    if (_pointerStarts.isEmpty) {
      _gestureTriggered = false;
    }
    if (wasMulti && _pointerStarts.length < 2) {
      setState(() {});
    }
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    final wasMulti = _pointerStarts.length >= 2;
    _pointerStarts.remove(event.pointer);
    _pointerPositions.remove(event.pointer);
    if (_pointerStarts.isEmpty) {
      _gestureTriggered = false;
    }
    if (wasMulti && _pointerStarts.length < 2) {
      setState(() {});
    }
  }

  void _evaluateGesture() {
    if (_gestureTriggered) return;

    if (_pointerStarts.length == 2) {
      final keys = _pointerStarts.keys.toList();
      final start1 = _pointerStarts[keys[0]];
      final current1 = _pointerPositions[keys[0]];
      final start2 = _pointerStarts[keys[1]];
      final current2 = _pointerPositions[keys[1]];

      if (start1 != null && current1 != null && start2 != null && current2 != null) {
        final delta1 = current1.dx - start1.dx;
        final delta2 = current2.dx - start2.dx;

        // Ensure both fingers are swiping in the same direction
        final sameDirection = (delta1 > 0 && delta2 > 0) || (delta1 < 0 && delta2 < 0);
        if (sameDirection) {
          final averageDelta = (delta1 + delta2) / 2;
          const double swipeThreshold = 70.0;

          if (averageDelta.abs() > swipeThreshold) {
            if (averageDelta > 0) {
              // Swipe right -> Switch to Health (tab 0)
              if (_currentTab != 0) {
                _switchToCategory(0);
                _gestureTriggered = true;
              }
            } else {
              // Swipe left -> Switch to Assistance (tab 1)
              if (_currentTab != 1) {
                _switchToCategory(1);
                _gestureTriggered = true;
              }
            }
          }
        }
      }
    }
  }

  Widget _buildCategorySelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: DoctorTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DoctorTheme.borderSoft),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildCategoryTab(
              index: 0,
              title: 'Health',
              icon: Icons.medical_services_outlined,
            ),
          ),
          Expanded(
            child: _buildCategoryTab(
              index: 1,
              title: 'Assistance',
              icon: Icons.handshake_outlined,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTab({
    required int index,
    required String title,
    required IconData icon,
  }) {
    final isActive = _currentTab == index;
    final activeColor = DoctorTheme.portalGlow;

    return Semantics(
      selected: isActive,
      label: '$title category',
      hint: isActive ? null : 'Double tap to select $title category',
      child: InkWell(
        onTap: () => _switchToCategory(index),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isActive ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isActive ? Colors.white : const Color(0xFF8E8E8E),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: isActive ? Colors.white : const Color(0xFF8E8E8E),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHealthPage() {
    final physics = _pointerStarts.length >= 2
        ? const NeverScrollableScrollPhysics()
        : const BouncingScrollPhysics();
    return SingleChildScrollView(
      physics: physics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _ReminderCard(),
          const SizedBox(height: 20),
          const DoctorSectionHeader(
            title: 'Health',
            subtitle: 'Medications, records, and appointments',
          ),
          const SizedBox(height: 14),
          GridView.count(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: const [
              _MedicationsMenuTile(),
              _AppointmentsMenuTile(),
              _HealthRecordsMenuTile(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAssistancePage() {
    final physics = _pointerStarts.length >= 2
        ? const NeverScrollableScrollPhysics()
        : const BouncingScrollPhysics();
    return SingleChildScrollView(
      physics: physics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DoctorSectionHeader(
            title: 'Assistance',
            subtitle: 'Navigation and communication',
          ),
          const SizedBox(height: 14),
          GridView.count(
            physics: physics,
            shrinkWrap: true,
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: [
              _MenuTile(
                title: context.l10n.t('navigation'),
                subtitle: context.l10n.t('navigationSubtitle'),
                icon: Icons.near_me_outlined,
                accent: const Color(0xFFC88423),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      settings: const RouteSettings(name: 'NavigationPage'),
                      builder: (context) => const NavigationPage(),
                    ),
                  );
                },
              ),
              const _CommunicationMenuTile(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmergencySosButton() {
    return AccessibleFocusRegion(
      label: '${context.l10n.t('emergencySos')}. ${context.l10n.t('emergencySosSubtitle')}',
      onActivate: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'EmergencySosPage'),
            builder: (context) => const EmergencySosPage(),
          ),
        );
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: 'EmergencySosPage'),
              builder: (context) => const EmergencySosPage(),
            ),
          );
        },
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: DoctorTheme.cardRadius,
            color: DoctorTheme.dangerSurface,
            border: Border.all(color: DoctorTheme.dangerBorder, width: 1.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: DoctorTheme.dangerBorder.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.l10n.t('emergencySos'),
                        style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.l10n.t('emergencySosSubtitle'),
                        style: const TextStyle(
                          color: AppColors.subtext,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: DoctorTheme.dangerBorder,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: MainMenuPage.scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: const _MainMenuDrawer(),
      drawerEnableOpenDragGesture: false,
      body: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerCancel,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _HeaderSection(),
                const SizedBox(height: 16),
                _buildEmergencySosButton(),
                const SizedBox(height: 16),
                _buildCategorySelector(),
                const SizedBox(height: 16),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (index) {
                      if (_currentTab != index) {
                        setState(() {
                          _currentTab = index;
                        });
                      }
                    },
                    children: [
                      _buildHealthPage(),
                      _buildAssistancePage(),
                    ],
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
    final now = ClinicDateTime.nowClinic();
    final dates = _todayLabels(context);
    final greeting = DoctorTheme.greetingForHour(now.hour);

    return StreamBuilder<Map<String, dynamic>>(
      stream: profileService.watchForCurrentUser(),
      initialData: const {},
      builder: (context, snapshot) {
        final profile = snapshot.data ?? const {};
        final name = UserProfileService.greetingName(profile);
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
            const SizedBox(width: 12),
            Expanded(
              child: AccessibleFocusRegion(
                label: a11yLabel,
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
                      name.isEmpty ? '…' : name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Semantics(
                      label: dates.spoken,
                      excludeSemantics: true,
                      child: Text(
                        dates.display,
                        style: const TextStyle(
                          color: AppColors.subtext,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            _PatientNotificationBell(),
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
        color: DoctorTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: DoctorTheme.borderSoft),
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

class _PatientNotificationBell extends StatelessWidget {
  const _PatientNotificationBell();

  @override
  Widget build(BuildContext context) {
    final service = NotificationsService();
    return StreamBuilder<int>(
      stream: service.watchUnreadCount(),
      initialData: 0,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return PortalNotificationBell(
          unreadCount: count,
          tooltip: context.l10n.t('notification'),
          onTap: () {
            unawaited(MedicationPushService.instance.registerForReminders());
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'NotificationsPage'),
                builder: (_) => const NotificationsPage(),
              ),
            );
          },
        );
      },
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
        settings: const RouteSettings(name: 'MedicationsPage'),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: DoctorTheme.surfaceCard(
              tint: DoctorTheme.surfaceHighlight,
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: DoctorTheme.portalAccent.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.medication_outlined,
                    color: DoctorTheme.portalAccent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
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
                        style: const TextStyle(
                          color: AppColors.subtext,
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

        return DoctorModuleTile(
          title: context.l10n.t('appointments'),
          subtitle: subtitle,
          icon: Icons.calendar_today_outlined,
          accent: DoctorTheme.moduleAppointments,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'AppointmentsPage'),
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

        return DoctorModuleTile(
          title: context.l10n.t('medications'),
          subtitle: subtitle,
          icon: Icons.medication_outlined,
          accent: DoctorTheme.moduleMedications,
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

        return DoctorModuleTile(
          title: context.l10n.t('healthRecords'),
          subtitle: subtitle,
          icon: Icons.description_outlined,
          accent: DoctorTheme.moduleRecords,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'HealthRecordsPage'),
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

        return DoctorModuleTile(
          title: context.l10n.t('communication'),
          subtitle: subtitle,
          icon: Icons.forum_outlined,
          accent: DoctorTheme.moduleCommunication,
          badge: count > 0 ? '$count' : null,
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: 'CommunicationPage'),
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
    required this.accent,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return DoctorModuleTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      accent: accent,
      onTap: onTap,
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
                                settings: const RouteSettings(name: 'SettingsPage'),
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
                          if (context.mounted) {
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute<void>(
                                settings: const RouteSettings(name: 'StartPage'),
                                builder: (context) => const StartPage(),
                              ),
                              (route) => false,
                            );
                          }
                        },
                        child: FilledButton.icon(
                          onPressed: () async {
                            AuthSession.markExplicitSignOut();
                            await FirebaseAuth.instance.signOut();
                            if (context.mounted) {
                              Navigator.of(context).pushAndRemoveUntil(
                                MaterialPageRoute<void>(
                                  settings: const RouteSettings(name: 'StartPage'),
                                  builder: (context) => const StartPage(),
                                ),
                                (route) => false,
                              );
                            }
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
