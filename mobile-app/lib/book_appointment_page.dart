import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'models/book_appointment_session.dart';
import 'models/bookable_slot.dart';
import 'models/staff_option.dart';
import 'utils/appointment_time_slots.dart';
import 'utils/appointment_types.dart';
import 'widgets/calendar_date_picker_dialog.dart';
import 'widgets/centered_back_title_bar.dart';
import 'widgets/date_select_field.dart';

class BookAppointmentPage extends StatefulWidget {
  const BookAppointmentPage({super.key, this.session});

  final BookAppointmentSession? session;

  @override
  State<BookAppointmentPage> createState() => _BookAppointmentPageState();
}

class _BookAppointmentPageState extends State<BookAppointmentPage> {
  static const Color _bg = Color(0xFF000000);
  static const Color _accent = Color(0xFF63C3C4);
  static const Color _subtext = Color(0xFFB0B0B0);

  late final BookAppointmentSession _session;
  late final bool _ownsSession;

  @override
  void initState() {
    super.initState();
    _ownsSession = widget.session == null;
    _session = widget.session ?? BookAppointmentSession();
    _session.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    if (_ownsSession) {
      _session.dispose();
    }
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  String _l10n(BuildContext context, String key) => context.l10n.t(key);

  String _stepTitle(BuildContext context) {
    switch (_session.step) {
      case 0:
        return _l10n(context, 'chooseSpecialistRole');
      case 1:
        return _session.roleKey == 'doctor'
            ? _l10n(context, 'selectDoctor')
            : _session.roleKey == 'therapist'
                ? _l10n(context, 'selectTherapist')
                : _l10n(context, 'selectCaregiver');
      case 2:
        return _l10n(context, 'chooseSessionType');
      default:
        return _l10n(context, 'selectDateAndTime');
    }
  }

  String _roleLabel(BuildContext context, String? roleKey) {
    switch (roleKey) {
      case 'doctor':
        return _l10n(context, 'roleDoctor');
      case 'therapist':
        return _l10n(context, 'roleTherapist');
      case 'caregiver':
        return _l10n(context, 'roleCaregiver');
      default:
        return roleKey ?? '';
    }
  }

  void _goBack() {
    if (_session.step == 0) {
      Navigator.of(context).pop();
      return;
    }
    _session.goBack();
  }

  Future<void> _pickAppointmentDate() async {
    FocusScope.of(context).unfocus();
    final today = _todayDateOnly();
    final first = today;
    final last = DateTime(today.year + 1, today.month, today.day);
    final initial = clampCalendarDate(
      _session.selectedDate ?? today,
      first,
      last,
    );

    final picked = await showCalendarDatePickerDialog(
      context: context,
      title: context.l10n.t('appointmentDate'),
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      accent: _accent,
    );
    if (picked == null || !mounted) return;
    await _session.selectDate(picked);
  }

  void _onSlotSelected(BookableSlot slot) {
    if (_session.selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('pleaseSelectAppointmentDateFirst'))),
      );
      return;
    }
    final before = _session.selectedSlot;
    _session.selectSlot(slot);
    if (_session.selectedSlot == before) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('slotNoLongerAvailable'))),
      );
    }
  }

  String _sessionAppointmentType() {
    return _session.sessionCanonicalTypeForKey(
      _session.sessionKey ?? AppointmentTypes.doctorOptions.first.key,
    );
  }

  Future<void> _book() async {
    try {
      final success = await _session.submitBooking(_sessionAppointmentType());
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('appointmentRequestSubmitted'))),
        );
        Navigator.of(context).pop(true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('slotJustTaken'))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      final l10n = context.l10n;
      final text = e.toString().contains('permission-denied')
          ? l10n.t('firestorePermissionBooking')
          : l10n.t('couldNotBook', {'error': e});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    }
  }

  DateTime _todayDateOnly() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
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
        title: Text(
          l10n.t('newAppointment'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            _BookStepProgress(current: _session.step, total: 4),
            const SizedBox(height: 12),
            Text(
              l10n.t('setupYourVisit'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _subtext, fontSize: 14),
            ),
            const SizedBox(height: 20),
            CenteredBackTitleBar(
              title: _stepTitle(context),
              onBack: _goBack,
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildStepBody(context)),
            if (_session.step == 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: FilledButton(
                  onPressed: _session.selectedSlot != null && !_session.submitting
                      ? _book
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: const Color(0xFF3A3A3A),
                    disabledForegroundColor: _subtext,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _session.submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : Text(
                          l10n.t('bookAppointment'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBody(BuildContext context) {
    final l10n = context.l10n;
    switch (_session.step) {
      case 0:
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            for (final r in BookAppointmentSession.roleOptions)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _OptionCard(
                  title: l10n.t(r.titleKey),
                  subtitle: '',
                  onTap: () => _session.selectRole(r.key),
                ),
              ),
          ],
        );
      case 1:
        if (_session.loadingStaff) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }
        if (_session.staff.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '${l10n.t('noStaffForRole', {'role': _roleLabel(context, _session.roleKey)})}\n'
                '${l10n.t('tryAnotherRole')}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _subtext, fontSize: 15, height: 1.4),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _session.staff.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final staff = _session.staff[index];
            return _StaffCard(
              staff: staff,
              onTap: () => _session.selectStaff(staff),
            );
          },
        );
      case 2:
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            for (final s in BookAppointmentSession.sessionOptionsForRole(_session.roleKey))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _OptionCard(
                  title: l10n.t(s.titleKey),
                  subtitle: s.subtitleKey.isEmpty ? '' : l10n.t(s.subtitleKey),
                  onTap: () => _session.selectSession(s.key),
                ),
              ),
          ],
        );
      default:
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            Text(
              l10n.t('chooseDayOfVisit'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: _subtext, fontSize: 14, height: 1.35),
            ),
            const SizedBox(height: 16),
            DateSelectField(
              selectedDate: _session.selectedDate,
              onTap: _pickAppointmentDate,
              placeholder: l10n.t('selectDate'),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.t('availableTimeSlots'),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            if (_session.selectedDate == null)
              Text(
                l10n.t('selectDateForTimes'),
                style: const TextStyle(color: _subtext, fontSize: 14),
              )
            else if (_session.loadingSlots)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(color: _accent),
                ),
              )
            else if (_session.slotsErrorMessage != null)
              Text(
                _session.slotsErrorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _subtext, fontSize: 14, height: 1.4),
              )
            else if (_session.availableSlots.isEmpty)
              Text(
                l10n.t('noTimesForDateDetail'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _subtext, fontSize: 14, height: 1.4),
              )
            else
              for (final slot in _session.availableSlots)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TimeSlotButton(
                    dateTime: slot.dateTime,
                    selected: _session.selectedSlot != null &&
                        _session.selectedSlot!.firestoreDocId == slot.firestoreDocId &&
                        AppointmentTimeSlots.sameMinute(
                          _session.selectedSlot!.dateTime,
                          slot.dateTime,
                        ),
                    onTap: () => _onSlotSelected(slot),
                  ),
                ),
          ],
        );
    }
  }
}

class _BookStepProgress extends StatelessWidget {
  const _BookStepProgress({required this.current, required this.total});

  final int current;
  final int total;

  static const Color _accent = Color(0xFF63C3C4);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (index) {
        final active = index == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 26 : 6,
          height: 4,
          decoration: BoxDecoration(
            color: active ? _accent : const Color(0xFF4D4D4D),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  static const Color _card = Color(0xFF1C1C1C);
  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        style: const TextStyle(color: _subtext, fontSize: 14, height: 1.3),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  const _StaffCard({required this.staff, required this.onTap});

  final StaffOption staff;
  final VoidCallback onTap;

  static const Color _card = Color(0xFF1C1C1C);
  static const Color _accent = Color(0xFF63C3C4);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _card,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: const Color(0xFF2A4A4C),
                child: Text(
                  staff.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      staff.localizedDisplayName(
                        AppLocalizations.of(context).languageCode,
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star, color: _accent, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          staff.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeSlotButton extends StatelessWidget {
  const _TimeSlotButton({
    required this.dateTime,
    required this.selected,
    required this.onTap,
  });

  final DateTime dateTime;
  final bool selected;
  final VoidCallback onTap;

  static const Color _card = Color(0xFF1C1C1C);
  static const Color _accent = Color(0xFF63C3C4);

  @override
  Widget build(BuildContext context) {
    final label = AppointmentTimeSlots.formatTimeLabel(dateTime);

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: selected ? _accent.withValues(alpha: 0.2) : _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? _accent : const Color(0xFF333333),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: selected ? _accent : Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
