import 'package:flutter/foundation.dart';

import '../models/bookable_slot.dart';
import '../models/staff_option.dart';
import '../services/appointments_service.dart';
import '../utils/appointment_time_slots.dart';
import '../utils/clinic_datetime.dart';

/// Shared booking wizard state for touch UI and guided voice flows.
class BookAppointmentSession extends ChangeNotifier {
  BookAppointmentSession({AppointmentsService? service})
      : _service = service ?? AppointmentsService();

  final AppointmentsService _service;

  static const sessionOptions = <({String key, String titleKey, String subtitleKey})>[
    (key: 'general', titleKey: 'sessionGeneral', subtitleKey: 'sessionGeneralDesc'),
    (
      key: 'therapist_session',
      titleKey: 'sessionTherapist',
      subtitleKey: 'sessionTherapistDesc',
    ),
    (key: 'urgent', titleKey: 'sessionUrgent', subtitleKey: 'sessionUrgentDesc'),
  ];

  static const roleOptions = <({String key, String titleKey})>[
    (key: 'doctor', titleKey: 'roleDoctor'),
    (key: 'therapist', titleKey: 'roleTherapist'),
  ];

  int step = 0;
  String? sessionKey;
  String? roleKey;
  StaffOption? selectedStaff;
  DateTime? selectedDate;
  BookableSlot? selectedSlot;
  List<StaffOption> staff = [];
  List<BookableSlot> availableSlots = [];
  bool loadingStaff = false;
  bool loadingSlots = false;
  bool submitting = false;
  String? slotsErrorMessage;

  String sessionTitleForKey(String key, String Function(String) localize) {
    for (final option in sessionOptions) {
      if (option.key == key) return localize(option.titleKey);
    }
    return localize(sessionOptions.first.titleKey);
  }

  Future<void> selectSession(String key) async {
    sessionKey = key;
    step = 1;
    notifyListeners();
  }

  Future<void> selectRole(String key) async {
    roleKey = key;
    selectedStaff = null;
    step = 2;
    notifyListeners();
    await loadStaffForRole(key);
  }

  Future<void> loadStaffForRole(String role) async {
    loadingStaff = true;
    staff = [];
    notifyListeners();
    try {
      staff = await _service.fetchBookableStaff(category: role);
    } finally {
      loadingStaff = false;
      notifyListeners();
    }
  }

  Future<void> selectStaff(StaffOption option) async {
    selectedStaff = option;
    selectedDate = null;
    selectedSlot = null;
    availableSlots = [];
    slotsErrorMessage = null;
    loadingSlots = false;
    step = 3;
    notifyListeners();
  }

  Future<void> selectDate(DateTime date) async {
    final dateOnly = DateTime(date.year, date.month, date.day);
    selectedDate = dateOnly;
    selectedSlot = null;
    slotsErrorMessage = null;
    notifyListeners();
    await loadAvailableSlots();
  }

  Future<void> loadAvailableSlots() async {
    final staffMember = selectedStaff;
    final date = selectedDate;
    if (staffMember == null || date == null) {
      availableSlots = [];
      loadingSlots = false;
      notifyListeners();
      return;
    }

    loadingSlots = true;
    notifyListeners();
    try {
      final slots = await _service.fetchBookableSlotsForStaffOnDate(
        staffId: staffMember.staffId,
        date: date,
      );
      availableSlots = slots;
      slotsErrorMessage = null;
      if (selectedSlot != null &&
          !slots.any(
            (slot) =>
                AppointmentTimeSlots.sameMinute(slot.dateTime, selectedSlot!.dateTime) &&
                slot.firestoreDocId == selectedSlot!.firestoreDocId,
          )) {
        selectedSlot = null;
      }
    } catch (error) {
      availableSlots = [];
      slotsErrorMessage = error.toString();
    } finally {
      loadingSlots = false;
      notifyListeners();
    }
  }

  void selectSlot(BookableSlot slot) {
    if (selectedDate == null) return;
    final listed = availableSlots.any(
      (item) =>
          item.firestoreDocId == slot.firestoreDocId &&
          AppointmentTimeSlots.sameMinute(item.dateTime, slot.dateTime),
    );
    if (!listed || !ClinicDateTime.isAfterNow(slot.dateTime)) return;
    selectedSlot = slot;
    notifyListeners();
  }

  void goBack() {
    if (step == 0) return;
    if (step == 3) {
      selectedDate = null;
      selectedSlot = null;
      availableSlots = [];
      loadingSlots = false;
      slotsErrorMessage = null;
    } else if (step == 2) {
      selectedStaff = null;
      staff = [];
      loadingStaff = false;
    } else if (step == 1) {
      roleKey = null;
    }
    step -= 1;
    notifyListeners();
  }

  Future<bool> submitBooking(String appointmentTypeLabel) async {
    final staffMember = selectedStaff;
    final slot = selectedSlot;
    if (staffMember == null || slot == null) return false;

    submitting = true;
    notifyListeners();
    try {
      await loadAvailableSlots();
      if (selectedSlot == null ||
          !availableSlots.any(
            (item) =>
                item.firestoreDocId == slot.firestoreDocId &&
                AppointmentTimeSlots.sameMinute(item.dateTime, slot.dateTime),
          )) {
        return false;
      }

      await _service.bookAppointment(
        staffId: staffMember.staffId,
        appointmentType: appointmentTypeLabel,
        dateTime: slot.dateTime,
        notes: 'Booked via mobile app (voice guided)',
        existingFirestoreDocId: slot.firestoreDocId,
        existingAppointmentId: slot.appointmentId,
      );
      return true;
    } finally {
      submitting = false;
      notifyListeners();
    }
  }
}
