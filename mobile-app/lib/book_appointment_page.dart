import 'package:flutter/material.dart';

import 'models/bookable_slot.dart';
import 'models/staff_option.dart';
import 'services/appointments_service.dart';
import 'services/healthcare_staff_service.dart';
import 'utils/appointment_time_slots.dart';
import 'utils/clinic_datetime.dart';
import 'widgets/calendar_date_picker_dialog.dart';
import 'widgets/date_select_field.dart';

class BookAppointmentPage extends StatefulWidget {
  const BookAppointmentPage({super.key});

  @override
  State<BookAppointmentPage> createState() => _BookAppointmentPageState();
}

class _BookAppointmentPageState extends State<BookAppointmentPage> {
  static const Color _bg = Color(0xFF000000);
  static const Color _accent = Color(0xFF63C3C4);
  static const Color _subtext = Color(0xFFB0B0B0);

  final _service = AppointmentsService();
  int _step = 0;
  String? _sessionKey;
  String? _roleKey;
  StaffOption? _selectedStaff;
  DateTime? _selectedDate;
  BookableSlot? _selectedSlot;
  List<StaffOption> _staff = [];
  List<BookableSlot> _availableSlots = [];
  bool _loadingStaff = false;
  bool _loadingSlots = false;
  bool _submitting = false;

  static const _sessions = <_Option>[
    _Option('general', 'General Check-up', 'Routine health screening and consultation'),
    _Option('therapist_session', 'Therapist Session', 'Specialized therapy and rehabilitation'),
    _Option('urgent', 'Urgent Consultation', 'Fast-tracked medical attention'),
  ];

  static const _roles = <_Option>[
    _Option('doctor', 'Doctor', ''),
    _Option('therapist', 'Therapist', ''),
    _Option('caregiver', 'Caregiver', ''),
  ];

  String get _stepTitle {
    switch (_step) {
      case 0:
        return 'Choose Session Type';
      case 1:
        return 'Choose Specialist Role';
      case 2:
        return _roleKey == 'doctor'
            ? 'Select Doctor'
            : _roleKey == 'therapist'
                ? 'Select Therapist'
                : 'Select Caregiver';
      default:
        return 'Select Date & Time';
    }
  }

  Future<void> _loadStaffForRole(String roleKey) async {
    setState(() {
      _loadingStaff = true;
      _staff = [];
    });
    try {
      final staff = await _service.fetchBookableStaff(category: roleKey);
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _loadingStaff = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingStaff = false);
      final msg = e.toString().contains('permission-denied')
          ? 'Permission denied reading healthcarestaff. Deploy Firestore rules: firebase deploy --only firestore:rules'
          : 'Could not load staff: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  void _goBack() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      if (_step == 3) {
        _selectedDate = null;
        _selectedSlot = null;
        _availableSlots = [];
        _loadingSlots = false;
      } else if (_step == 2) {
        _selectedStaff = null;
        _staff = [];
        _loadingStaff = false;
      } else if (_step == 1) {
        _roleKey = null;
      }
      _step -= 1;
    });
  }

  void _onSessionSelected(String key) {
    setState(() {
      _sessionKey = key;
      _step = 1;
    });
  }

  void _onRoleSelected(String key) {
    setState(() {
      _roleKey = key;
      _step = 2;
      _selectedStaff = null;
    });
    _loadStaffForRole(key);
  }

  void _onStaffSelected(StaffOption staff) {
    setState(() {
      _selectedStaff = staff;
      _step = 3;
      _selectedDate = null;
      _selectedSlot = null;
      _availableSlots = [];
      _loadingSlots = false;
    });
  }

  Future<void> _loadAvailableSlots() async {
    final staff = _selectedStaff;
    final date = _selectedDate;
    if (staff == null || date == null) {
      setState(() {
        _availableSlots = [];
        _loadingSlots = false;
      });
      return;
    }

    setState(() => _loadingSlots = true);
    try {
      final slots = await _service.fetchBookableSlotsForStaffOnDate(
        staffId: staff.staffId,
        date: date,
      );
      if (!mounted) return;
      setState(() {
        _availableSlots = slots;
        _loadingSlots = false;
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
      setState(() {
        _loadingSlots = false;
        _availableSlots = [];
      });
      final text = e.toString();
      final String msg;
      if (text.contains('failed-precondition')) {
        msg =
            'Firestore index missing for appointments (staffId + dateTime). '
            'Run: firebase deploy --only firestore:indexes';
      } else if (text.contains('permission-denied')) {
        msg =
            'Firestore blocked reading appointments for slot lookup. '
            'Run: firebase deploy --only firestore:rules';
      } else {
        msg = 'Could not load available times: $e';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
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
      title: 'Appointment date',
      initialDate: initial,
      firstDate: first,
      lastDate: last,
      accent: _accent,
    );
    if (picked == null || !mounted) return;

    final dateOnly = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      _selectedDate = dateOnly;
      _selectedSlot = null;
    });
    await _loadAvailableSlots();
  }

  void _onSlotSelected(BookableSlot slot) {
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an appointment date first.')),
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
        const SnackBar(content: Text('This time slot is no longer available.')),
      );
      return;
    }
    setState(() => _selectedSlot = slot);
  }

  /// Firestore `appointmentType` = session label from step 1 (e.g. General Check-up).
  String _sessionAppointmentType() {
    for (final session in _sessions) {
      if (session.key == _sessionKey) return session.title;
    }
    return _sessions.first.title;
  }

  Future<void> _book() async {
    final staff = _selectedStaff;
    final slot = _selectedSlot;
    if (staff == null || slot == null) return;

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
          const SnackBar(
            content: Text('This time slot was just taken. Please choose another.'),
          ),
        );
        return;
      }

      await _service.bookAppointment(
        staffId: staff.staffId,
        appointmentType: _sessionAppointmentType(),
        dateTime: slot.dateTime,
        notes: 'Booked via mobile app',
        existingFirestoreDocId: slot.firestoreDocId,
        existingAppointmentId: slot.appointmentId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Appointment request submitted. Status: Pending until staff confirms.',
          ),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final text = e.toString().contains('permission-denied')
          ? 'Booking was blocked by Firestore rules. Deploy rules: firebase deploy --only firestore:rules'
          : 'Could not book: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(text)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
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
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Text(
          'New Appointment',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            _BookStepProgress(current: _step, total: 4),
            const SizedBox(height: 12),
            const Text(
              'Setup your visit',
              textAlign: TextAlign.center,
              style: TextStyle(color: _subtext, fontSize: 14),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _goBack,
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                    tooltip: _step == 0 ? 'Back' : 'Previous step',
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _stepTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildStepBody()),
            if (_step == 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: FilledButton(
                  onPressed: _selectedSlot != null && !_submitting ? _book : null,
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
                      : const Text(
                          'Book Appointment',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    switch (_step) {
      case 0:
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            for (final s in _sessions)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _OptionCard(
                  title: s.title,
                  subtitle: s.subtitle,
                  onTap: () => _onSessionSelected(s.key),
                ),
              ),
          ],
        );
      case 1:
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            for (final r in _roles)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _OptionCard(
                  title: r.title,
                  subtitle: r.subtitle,
                  onTap: () => _onRoleSelected(r.key),
                ),
              ),
          ],
        );
      case 2:
        if (_loadingStaff) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }
        if (_staff.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No ${HealthcareStaffService.roleLabels[_roleKey] ?? _roleKey} '
                'staff available right now.\n'
                'Try another role or check back later.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _subtext, fontSize: 15, height: 1.4),
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _staff.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final staff = _staff[index];
            return _StaffCard(
              staff: staff,
              onTap: () => _onStaffSelected(staff),
            );
          },
        );
      default:
        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const Text(
              'Choose the day of your visit',
              textAlign: TextAlign.center,
              style: TextStyle(color: _subtext, fontSize: 14, height: 1.35),
            ),
            const SizedBox(height: 16),
            DateSelectField(
              selectedDate: _selectedDate,
              onTap: _pickAppointmentDate,
              placeholder: 'Select Date',
            ),
            const SizedBox(height: 24),
            const Text(
              'Available time slots',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            if (_selectedDate == null)
              const Text(
                'Select a date to see available times.',
                style: TextStyle(color: _subtext, fontSize: 14),
              )
            else if (_loadingSlots)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(color: _accent),
                ),
              )
            else if (_availableSlots.isEmpty)
              const Text(
                'No times available for this date.\n'
                'Taken slots are hidden. Add Available rows in appointments, '
                'or use default hours if none exist yet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _subtext, fontSize: 14, height: 1.4),
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
        );
    }
  }
}

class _Option {
  const _Option(this.key, this.title, this.subtitle);
  final String key;
  final String title;
  final String subtitle;
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
                      staff.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      staff.specialty,
                      style: const TextStyle(color: _subtext, fontSize: 14),
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
