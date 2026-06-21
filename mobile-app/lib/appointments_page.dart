import 'package:flutter/material.dart';

import 'book_appointment_page.dart';
import 'l10n/app_localizations.dart';
import 'models/appointment_item.dart';
import 'reschedule_appointment_page.dart';
import 'services/appointments_service.dart';
import 'widgets/accessible_focus_region.dart';
import 'widgets/app_back_button.dart';

class AppointmentsPage extends StatefulWidget {
  const AppointmentsPage({super.key});

  @override
  State<AppointmentsPage> createState() => _AppointmentsPageState();
}

class _AppointmentsPageState extends State<AppointmentsPage> {
  static const Color _bg = Color(0xFF000000);
  static const Color _accent = Color(0xFF63C3C4);
  static const Color _cancelRed = Color(0xFFE85C5C);

  final _service = AppointmentsService();
  int _tabIndex = 0;
  bool _loading = true;
  String? _error;
  List<AppointmentItem> _all = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _service.fetchForCurrentPatient();
      if (!mounted) return;
      setState(() {
        _all = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<AppointmentItem> get _upcoming =>
      _all.where((a) => !a.isPast).toList()..sort((a, b) => a.dateTime.compareTo(b.dateTime));

  List<AppointmentItem> get _past =>
      _all.where((a) => a.isPast).toList()..sort((a, b) => b.dateTime.compareTo(a.dateTime));

  List<AppointmentItem> get _visible => _tabIndex == 0 ? _upcoming : _past;

  Future<void> _onCancel(AppointmentItem item) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(
          l10n.t('cancelAppointmentQuestion'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          l10n.t('cancelVisitWithDoctor', {
            'doctorName': item.doctorName,
            'dateLabel': item.dateLabel,
          }),
          style: const TextStyle(color: Color(0xFFB0B0B0)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.t('keep')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.t('cancelVisit'),
              style: const TextStyle(color: _cancelRed),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.cancelAppointment(item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('appointmentCancelled'))),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('couldNotCancel', {'error': e}))),
      );
    }
  }

  Future<void> _onReschedule(AppointmentItem item) async {
    if (item.staffId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('cannotRescheduleMissingStaff'))),
      );
      return;
    }

    final rescheduled = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => RescheduleAppointmentPage(appointment: item),
      ),
    );
    if (rescheduled == true) await _load();
  }

  Future<void> _onBook() async {
    final booked = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => const BookAppointmentPage(),
      ),
    );
    if (booked == true) await _load();
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
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: AppBackButton.appBarLeadingWidth,
        leading: const AppBackButton(),
        title: Text(
          l10n.t('appointments'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: _TabBar(
                upcomingCount: _upcoming.length,
                pastCount: _past.length,
                selectedIndex: _tabIndex,
                onChanged: (i) => setState(() => _tabIndex = i),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent),
                    )
                  : _error != null
                      ? _ErrorState(message: _error!, onRetry: _load)
                      : _visible.isEmpty
                          ? const _EmptyState()
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                              itemCount: _visible.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                final item = _visible[index];
                                return AccessibleFocusRegion(
                                  label: context.l10n.t('appointmentItemA11y', {
                                    'doctorName': item.doctorName,
                                    'specialty': item.appointmentType,
                                    'dateLabel': item.dateLabel,
                                    'timeLabel': item.timeLabel,
                                    'location': item.locationDisplay,
                                  }),
                                  child: _AppointmentCard(
                                    item: item,
                                    showActions: _tabIndex == 0,
                                    onCancel: () => _onCancel(item),
                                    onReschedule: () => _onReschedule(item),
                                  ),
                                );
                              },
                            ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: AccessibleFocusRegion(
                label: l10n.t('bookAppointment'),
                onActivate: _onBook,
                child: FilledButton(
                  onPressed: _onBook,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    l10n.t('bookAppointment'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.upcomingCount,
    required this.pastCount,
    required this.selectedIndex,
    required this.onChanged,
  });

  final int upcomingCount;
  final int pastCount;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  static const Color _accent = Color(0xFF63C3C4);
  static const Color _tabInactive = Color(0xFF2A2A2A);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final upcomingLabel = l10n.t('upcomingSection', {'count': upcomingCount});
    final pastLabel = l10n.t('pastSection', {'count': pastCount});
    return Row(
      children: [
        Expanded(
          child: AccessibleFocusRegion(
            label: upcomingLabel,
            onActivate: () => onChanged(0),
            child: _TabChip(
              label: upcomingLabel,
              selected: selectedIndex == 0,
              onTap: () => onChanged(0),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AccessibleFocusRegion(
            label: pastLabel,
            onActivate: () => onChanged(1),
            child: _TabChip(
              label: pastLabel,
              selected: selectedIndex == 1,
              onTap: () => onChanged(1),
            ),
          ),
        ),
      ],
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _TabBar._accent : _TabBar._tabInactive,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.item,
    required this.showActions,
    required this.onCancel,
    required this.onReschedule,
  });

  final AppointmentItem item;
  final bool showActions;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;

  static const Color _card = Color(0xFF1C1C1C);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _accent = Color(0xFF63C3C4);
  static const Color _cancelRed = Color(0xFFE85C5C);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.doctorName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.appointmentType,
            style: const TextStyle(color: _subtext, fontSize: 15),
          ),
          if (item.isPending) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF3D3520),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                l10n.t('pendingStaffConfirmation'),
                style: const TextStyle(color: Color(0xFFE8C547), fontSize: 13),
              ),
            ),
          ],
          const SizedBox(height: 14),
          _AppointmentDetails(
            date: item.dateLabel,
            time: item.timeLabel,
            location: item.locationDisplay,
          ),
          if (showActions) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onCancel,
                    style: FilledButton.styleFrom(
                      backgroundColor: _cancelRed,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: Text(
                      l10n.t('cancel'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (!item.isPending) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: onReschedule,
                      style: FilledButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text(
                        l10n.t('reschedule'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Date, time, and location with even vertical spacing.
class _AppointmentDetails extends StatelessWidget {
  const _AppointmentDetails({
    required this.date,
    required this.time,
    required this.location,
  });

  final String date;
  final String time;
  final String location;

  static const double _rowGap = 12;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DetailRow(icon: Icons.calendar_today_outlined, text: date),
        const SizedBox(height: _rowGap),
        _DetailRow(icon: Icons.schedule_outlined, text: time),
        const SizedBox(height: _rowGap),
        _DetailRow(icon: Icons.location_on_outlined, text: location),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  static const double _iconSize = 20;
  static const double _rowHeight = 24;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _rowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _iconSize,
            height: _iconSize,
            child: Icon(icon, color: Colors.white70, size: _iconSize),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          context.l10n.t('noAppointmentsYet'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFB0B0B0), fontSize: 16),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFB0B0B0)),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.t('retry')),
            ),
          ],
        ),
      ),
    );
  }
}
