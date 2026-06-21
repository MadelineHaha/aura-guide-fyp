import 'package:flutter/material.dart';

import 'l10n/app_localizations.dart';
import 'models/appointment_item.dart';
import 'models/bookable_slot.dart';
import 'services/appointments_service.dart';
import 'utils/appointment_time_slots.dart';
import 'utils/clinic_datetime.dart';
import 'widgets/app_back_button.dart';
import 'widgets/calendar_date_picker_dialog.dart';
import 'widgets/date_select_field.dart';

class RescheduleAppointmentPage extends StatefulWidget {
  const RescheduleAppointmentPage({super.key, required this.appointment});

  final AppointmentItem appointment;

  @override
  State<RescheduleAppointmentPage> createState() =>
      _RescheduleAppointmentPageState();
}

class _RescheduleAppointmentPageState extends State<RescheduleAppointmentPage> {
  static const Color _bg = Color(0xFF000000);
  static const Color _accent = Color(0xFF63C3C4);
  static const Color _card = Color(0xFF1C1C1C);
  static const Color _subtext = Color(0xFFB0B0B0);

  final _service = AppointmentsService();
  DateTime? _selectedDate;
  BookableSlot? _selectedSlot;
  List<BookableSlot> _availableSlots = [];
  bool _loadingSlots = false;
  String? _slotsErrorMessage;
  bool _submitting = false;

  AppointmentItem get _appointment => widget.appointment;

  Future<void> _loadAvailableSlots() async {
    final date = _selectedDate;
    if (date == null) {
      setState(() {
        _availableSlots = [];
        _loadingSlots = false;
      });
      return;
    }

    setState(() => _loadingSlots = true);
    try {
      final slots = await _service.fetchBookableSlotsForStaffOnDate(
        staffId: _appointment.staffId,
        date: date,
        excludeAppointmentDocId: _appointment.id,
      );
      if (!mounted) return;
      setState(() {
        _availableSlots = slots;
        _loadingSlots = false;
        _slotsErrorMessage = null;
        if (_selectedSlot != null &&
            !slots.any(
              (s) =>
                  AppointmentTimeSlots.sameMinute(
                    s.dateTime,
                    _selectedSlot!.dateTime,
                  ) &&
                  s.firestoreDocId == _selectedSlot!.firestoreDocId,
            )) {
          _selectedSlot = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      final text = e.toString();
      final l10n = context.l10n;
      final String msg;
      if (text.contains('failed-precondition')) {
        msg = l10n.t('firestoreIndexAppointments');
      } else if (text.contains('permission-denied')) {
        msg = l10n.t('firestorePermissionAppointments');
      } else {
        msg = l10n.t('couldNotLoadAvailableTimes', {'error': e});
      }
      setState(() {
        _loadingSlots = false;
        _availableSlots = [];
        _slotsErrorMessage = msg;
      });
    }
  }

  DateTime _todayDateOnly() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _pickAppointmentDate() async {
    FocusScope.of(context).unfocus();
    final today = _todayDateOnly();
    final first = today;
    final last = DateTime(today.year + 1, today.month, today.day);
    final initial = clampCalendarDate(
      _selectedDate ?? today,
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

    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
      _selectedSlot = null;
      _slotsErrorMessage = null;
    });
    await _loadAvailableSlots();
  }

  void _onSlotSelected(BookableSlot slot) {
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('pleaseSelectAppointmentDateFirst')),
        ),
      );
      return;
    }
    final isListed = _availableSlots.any(
      (s) =>
          s.firestoreDocId == slot.firestoreDocId &&
          AppointmentTimeSlots.sameMinute(s.dateTime, slot.dateTime),
    );
    if (!isListed || !ClinicDateTime.isAfterNow(slot.dateTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('slotNoLongerAvailable'))),
      );
      return;
    }
    setState(() => _selectedSlot = slot);
  }

  Future<void> _confirmReschedule() async {
    final slot = _selectedSlot;
    if (slot == null) return;

    setState(() => _submitting = true);
    try {
      await _loadAvailableSlots();
      if (_selectedSlot == null ||
          !_availableSlots.any(
            (s) =>
                s.firestoreDocId == slot.firestoreDocId &&
                AppointmentTimeSlots.sameMinute(s.dateTime, slot.dateTime),
          )) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('slotJustTaken'))),
        );
        return;
      }

      await _service.rescheduleAppointment(
        appointmentDocId: _appointment.id,
        staffId: _appointment.staffId,
        newDateTime: slot.dateTime,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('appointmentRescheduled'))),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final l10n = context.l10n;
      final text = e.toString().contains('permission-denied')
          ? l10n.t('firestorePermissionBooking')
          : l10n.t('couldNotReschedule', {'error': e});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
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
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: AppBackButton.appBarLeadingWidth,
        leading: const AppBackButton(),
        title: Text(
          l10n.t('rescheduleAppointment'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _appointment.doctorName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _appointment.appointmentType,
                          style: const TextStyle(color: _subtext, fontSize: 14),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.t('currentAppointmentTime', {
                            'dateLabel': _appointment.dateLabel,
                            'timeLabel': _appointment.timeLabel,
                          }),
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    l10n.t('chooseNewDateAndTime'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: _subtext, fontSize: 14, height: 1.35),
                  ),
                  const SizedBox(height: 16),
                  DateSelectField(
                    selectedDate: _selectedDate,
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
                  if (_selectedDate == null)
                    Text(
                      l10n.t('selectDateForTimes'),
                      style: const TextStyle(color: _subtext, fontSize: 14),
                    )
                  else if (_loadingSlots)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: CircularProgressIndicator(color: _accent),
                      ),
                    )
                  else if (_slotsErrorMessage != null)
                    Text(
                      _slotsErrorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _subtext, fontSize: 14, height: 1.4),
                    )
                  else if (_availableSlots.isEmpty)
                    Text(
                      l10n.t('noTimesForDateDetail'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _subtext, fontSize: 14, height: 1.4),
                    )
                  else
                    for (final slot in _availableSlots)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TimeSlotButton(
                          dateTime: slot.dateTime,
                          selected: _selectedSlot != null &&
                              _selectedSlot!.firestoreDocId == slot.firestoreDocId &&
                              AppointmentTimeSlots.sameMinute(
                                _selectedSlot!.dateTime,
                                slot.dateTime,
                              ),
                          onTap: () => _onSlotSelected(slot),
                        ),
                      ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: FilledButton(
                onPressed: _selectedSlot != null && !_submitting
                    ? _confirmReschedule
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
                child: _submitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : Text(
                        l10n.t('confirmReschedule'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
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
