import 'package:flutter/foundation.dart';

import '../models/bookable_slot.dart';
import '../models/staff_option.dart';
import '../services/appointments_service.dart';
import '../utils/appointment_time_slots.dart';
import '../utils/appointment_types.dart';
import '../utils/clinic_datetime.dart';

/// Shared booking wizard state for touch UI and guided voice flows.
class BookAppointmentSession extends ChangeNotifier {
  BookAppointmentSession({AppointmentsService? service})
      : _service = service ?? AppointmentsService();

  final AppointmentsService _service;

  static const sessionOptions = AppointmentTypes.allOptions;

  static const roleOptions = <({String key, String titleKey})>[
    (key: 'doctor', titleKey: 'roleDoctor'),
    (key: 'therapist', titleKey: 'roleTherapist'),
  ];

  static List<AppointmentTypeOption> sessionOptionsForRole(String? roleKey) {
    return AppointmentTypes.optionsForRole(roleKey);
  }

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
    final option = AppointmentTypes.optionForKey(key);
    if (option != null) return localize(option.titleKey);
    return localize(AppointmentTypes.doctorOptions.first.titleKey);
  }

  String sessionCanonicalTypeForKey(String key) {
    final option = AppointmentTypes.optionForKey(key);
    return option?.canonicalType ?? AppointmentTypes.doctorOptions.first.canonicalType;
  }

  Future<void> selectRole(String key) async {
    roleKey = key;
    selectedStaff = null;
    sessionKey = null;
    selectedDate = null;
    selectedSlot = null;
    availableSlots = [];
    slotsErrorMessage = null;
    step = 1;
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
    sessionKey = null;
    selectedDate = null;
    selectedSlot = null;
    availableSlots = [];
    slotsErrorMessage = null;
    loadingSlots = false;
    step = 2;
    notifyListeners();
  }

  Future<void> selectSession(String key) async {
    sessionKey = key;
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
      sessionKey = null;
    } else if (step == 1) {
      selectedStaff = null;
      sessionKey = null;
      selectedDate = null;
      selectedSlot = null;
      availableSlots = [];
      loadingSlots = false;
      slotsErrorMessage = null;
      roleKey = null;
      staff = [];
      loadingStaff = false;
    }
    step -= 1;
    notifyListeners();
  }

  void prepareVoiceModifyRole() {
    roleKey = null;
    selectedStaff = null;
    sessionKey = null;
    selectedDate = null;
    selectedSlot = null;
    availableSlots = [];
    staff = [];
    loadingStaff = false;
    loadingSlots = false;
    slotsErrorMessage = null;
    step = 0;
    notifyListeners();
  }

  void prepareVoiceModifyStaff() {
    selectedStaff = null;
    selectedDate = null;
    selectedSlot = null;
    availableSlots = [];
    loadingSlots = false;
    slotsErrorMessage = null;
    step = 1;
    notifyListeners();
  }

  void prepareVoiceModifySession() {
    sessionKey = null;
    selectedDate = null;
    selectedSlot = null;
    availableSlots = [];
    loadingSlots = false;
    slotsErrorMessage = null;
    step = 2;
    notifyListeners();
  }

  void prepareVoiceModifyDate() {
    selectedDate = null;
    selectedSlot = null;
    availableSlots = [];
    loadingSlots = false;
    slotsErrorMessage = null;
    step = 3;
    notifyListeners();
  }

  void prepareVoiceModifyTime() {
    selectedSlot = null;
    step = 3;
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
