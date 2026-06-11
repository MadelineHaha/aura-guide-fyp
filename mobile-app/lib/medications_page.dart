import 'package:flutter/material.dart';

import 'models/medication_item.dart';
import 'services/medications_service.dart';
import 'widgets/accessible_focus_region.dart';
import 'widgets/app_back_button.dart';

class MedicationsPage extends StatefulWidget {
  const MedicationsPage({super.key});

  @override
  State<MedicationsPage> createState() => _MedicationsPageState();
}

class _MedicationsPageState extends State<MedicationsPage> {
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _accent = Color(0xFF63C3C4);

  final _service = MedicationsService();
  late final Stream<List<MedicationItem>> _medicationsStream;

  @override
  void initState() {
    super.initState();
    _medicationsStream = _service.watchForCurrentPatient();
  }

  static String _medicationLabel(MedicationItem item) {
    final status = item.takenToday ? 'Taken' : 'Not taken';
    return '${item.name}. ${item.scheduledTime}. ${item.dosage}. $status';
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
        SnackBar(content: Text('Could not update medication: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: AppBackButton.appBarLeadingWidth,
        leading: const AppBackButton(),
        title: const Text(
          'Medication',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<List<MedicationItem>>(
        stream: _medicationsStream,
        initialData: const [],
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AccessibleFocusRegion(
                  label: 'Could not load medications. ${snapshot.error}',
                  child: Text(
                    'Could not load medications.\n${snapshot.error}',
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
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: AccessibleFocusRegion(
                  label:
                      'There is no medication yet. Your healthcare provider will add prescriptions for you.',
                  child: Text(
                    'There is no medication yet.\n'
                    'Your healthcare provider will add prescriptions for you.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _subtext, fontSize: 15, height: 1.4),
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
                label:
                    "Today's Progress. $takenCount of $total taken. $percent percent.",
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
                    label: _medicationLabel(med),
                    onActivate: () => _toggleTaken(med),
                    child: _MedicationCard(
                      item: med,
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
                    const Text(
                      "Today's Progress",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$takenCount of $total taken',
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
                      '$percent%',
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
  });

  final MedicationItem item;
  final VoidCallback onToggleTaken;

  static const Color _card = Color(0xFF1A1A1A);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _lime = Color(0xFF9DDC3D);

  @override
  Widget build(BuildContext context) {
    final taken = item.takenToday;
    final titleColor = taken ? Colors.black87 : Colors.white;
    final detailColor = taken ? Colors.black54 : _subtext;
    final iconBg = taken ? Colors.white : _lime;
    final checkBg = taken ? Colors.black87 : Colors.transparent;
    final checkIconColor = taken ? _lime : _lime;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: taken ? _lime : _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _lime, width: 1.4),
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
              color: Colors.black87,
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
