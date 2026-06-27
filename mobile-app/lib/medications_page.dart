import 'dart:async';

import 'package:flutter/material.dart';

import 'app_route_observer.dart';
import 'l10n/app_localizations.dart';
import 'models/medication_item.dart';
import 'models/medication_reminder_entity.dart';
import 'services/medications_service.dart';
import 'services/voice_assistant_coordinator.dart';
import 'widgets/accessible_focus_region.dart';
import 'widgets/app_back_button.dart';

class MedicationsPage extends StatefulWidget {
  const MedicationsPage({super.key, this.highlightReminderId});

  /// Optional reminder id from a notification tap (highlights that dose).
  final String? highlightReminderId;

  @override
  State<MedicationsPage> createState() => _MedicationsPageState();
}

class _MedicationsPageState extends State<MedicationsPage> with RouteAware {
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _accent = Color(0xFF63C3C4);

  final _service = MedicationsService();
  late final Stream<List<MedicationItem>> _medicationsStream;
  Timer? _overdueRefreshTimer;

  @override
  void initState() {
    super.initState();
    _medicationsStream = _service.watchForCurrentPatient();
    _overdueRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      VoiceAssistantCoordinator.instance.setTopRouteLabel('MedicationsPage');
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
    VoiceAssistantCoordinator.instance.setTopRouteLabel('MedicationsPage');
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    _overdueRefreshTimer?.cancel();
    super.dispose();
  }

  String _medicationLabel(BuildContext context, MedicationItem item) {
    final l10n = context.l10n;
    final status = item.takenToday
        ? l10n.t('medicationTaken')
        : item.status == MedicationReminderEntity.statusMissed || item.isOverdue
            ? l10n.t('medicationOverdue')
            : l10n.t('medicationNotTaken');
    return l10n.t('medicationItemA11y', {
      'name': item.name,
      'time': item.scheduledTime,
      'dosage': item.dosage,
      'status': status,
    });
  }

  Future<void> _toggleTaken(MedicationItem item) async {
    try {
      await _service.setTakenToday(
        reminderId: item.reminderId,
        taken: !item.takenToday,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('couldNotUpdateMedication', {'error': e})),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: AppBackButton.appBarLeadingWidth,
        leading: const AppBackButton(),
        title: Text(
          l10n.t('medication'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<List<MedicationItem>>(
        stream: _medicationsStream,
        initialData: const [],
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final message = l10n.t('couldNotLoadMedicationsMultiline', {
              'error': snapshot.error,
            });
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AccessibleFocusRegion(
                  label: message,
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _subtext, height: 1.4),
                  ),
                ),
              ),
            );
          }

          final meds = snapshot.data ?? const [];
          final waiting =
              snapshot.connectionState == ConnectionState.waiting &&
                  meds.isEmpty;

          if (waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _accent),
            );
          }

          if (meds.isEmpty) {
            final emptyMessage = l10n.t('noMedicationYet');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: AccessibleFocusRegion(
                  label: emptyMessage,
                  child: Text(
                    emptyMessage.replaceFirst('. ', '.\n'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _subtext, fontSize: 15, height: 1.4),
                  ),
                ),
              ),
            );
          }

          final takenCount = meds.where((m) => m.takenToday).length;
          final total = meds.length;
          final progress = total == 0 ? 0.0 : takenCount / total;
          final percent = (progress * 100).round();

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              AccessibleFocusRegion(
                label: l10n.t('todayProgressA11y', {
                  'takenCount': takenCount,
                  'total': total,
                  'percent': percent,
                }),
                child: _TodayProgressCard(
                  takenCount: takenCount,
                  total: total,
                  progress: progress,
                  percent: percent,
                ),
              ),
              const SizedBox(height: 16),
              ...meds.map(
                (med) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AccessibleFocusRegion(
                    label: _medicationLabel(context, med),
                    onActivate: () => _toggleTaken(med),
                    child: _MedicationCard(
                      item: med,
                      highlighted: widget.highlightReminderId != null &&
                          widget.highlightReminderId == med.reminderId,
                      onToggleTaken: () => _toggleTaken(med),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TodayProgressCard extends StatelessWidget {
  const _TodayProgressCard({
    required this.takenCount,
    required this.total,
    required this.progress,
    required this.percent,
  });

  final int takenCount;
  final int total;
  final double progress;
  final int percent;

  static const Color _card = Color(0xFF1A1A1A);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _accent = Color(0xFF63C3C4);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('todayProgress'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.t('medicationTakenProgress', {
                        'takenCount': takenCount,
                        'total': total,
                      }),
                      style: const TextStyle(color: _subtext, fontSize: 14),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: progress,
                      strokeWidth: 5,
                      backgroundColor: const Color(0xFF333333),
                      color: _accent,
                    ),
                    Text(
                      l10n.t('medicationPercentTaken', {'percent': percent}),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFF333333),
              color: _accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({
    required this.item,
    required this.onToggleTaken,
    this.highlighted = false,
  });

  final MedicationItem item;
  final VoidCallback onToggleTaken;
  final bool highlighted;

  static const Color _card = Color(0xFF1A1A1A);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _lime = Color(0xFF9DDC3D);
  static const Color _overdue = Color(0xFFE13636);
  static const Color _overdueCard = Color(0xFF3C1111);

  @override
  Widget build(BuildContext context) {
    final taken = item.takenToday;
    final overdue = !taken &&
        (item.isOverdue || item.status == MedicationReminderEntity.statusMissed);

    final titleColor = taken
        ? Colors.black87
        : overdue
            ? Colors.white
            : Colors.white;
    final detailColor = taken
        ? Colors.black54
        : overdue
            ? const Color(0xFFFFB4B4)
            : _subtext;
    final cardColor = taken
        ? _lime
        : overdue
            ? _overdueCard
            : _card;
    final borderColor = taken
        ? _lime
        : overdue
            ? _overdue
            : _lime;
    final iconBg = taken
        ? Colors.white
        : overdue
            ? _overdue
            : _lime;
    final checkBg = taken ? Colors.black87 : Colors.transparent;
    final checkIconColor = taken
        ? _lime
        : overdue
            ? _overdue
            : _lime;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: highlighted ? Colors.white : borderColor,
          width: highlighted ? 2.5 : (overdue ? 2 : 1.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.medication_outlined,
              color: taken ? Colors.black87 : Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: TextStyle(
                    color: titleColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: detailColor,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.scheduledTime,
                      style: TextStyle(color: detailColor, fontSize: 13),
                    ),
                    Text(
                      '  ·  ',
                      style: TextStyle(color: detailColor, fontSize: 13),
                    ),
                    Expanded(
                      child: Text(
                        item.dosage,
                        style: TextStyle(color: detailColor, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: checkBg,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onToggleTaken,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(
                  taken ? Icons.check : Icons.circle_outlined,
                  color: checkIconColor,
                  size: 22,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
