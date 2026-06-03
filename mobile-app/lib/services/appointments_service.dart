import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth_session.dart';
import '../models/appointment_item.dart';
import '../models/bookable_slot.dart';
import '../models/staff_option.dart';
import '../utils/appointment_time_slots.dart';
import '../utils/clinic_datetime.dart';
import 'healthcare_staff_service.dart';
import 'user_profile_service.dart';

class AppointmentsService {
  AppointmentsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    UserProfileService? profileService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _profileService = profileService ?? UserProfileService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final UserProfileService _profileService;

  static const _appointments = 'appointments';
  static const _staff = 'healthcarestaff';
  static const _counterPath = 'system/appointmentCounter';
  static const _settingsPath = 'system/appointmentSettings';

  final _staffService = HealthcareStaffService();

  Future<String?> _patientUserId() async {
    final user = AuthSession.resolveUser() ?? _auth.currentUser;
    if (user == null) return null;
    final result = await _profileService.loadProfile(user.uid, syncAuthFirst: false);
    final id = (result.data['userId'] as String?)?.trim();
    return id?.isNotEmpty == true ? id : null;
  }

  Future<Map<String, Map<String, dynamic>>> _staffByStaffId() async {
    final snap = await _firestore
        .collection(_staff)
        .where('status', isEqualTo: 'Active')
        .get();
    final map = <String, Map<String, dynamic>>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final sid = (data['staffID'] as String?)?.trim() ??
          (data['staffId'] as String?)?.trim();
      if (sid != null && sid.isNotEmpty) {
        map[sid] = data;
      }
    }
    return map;
  }

  String _doctorName(Map<String, dynamic>? staff, String staffId) {
    if (staff == null) return staffId.isNotEmpty ? staffId : 'Healthcare provider';
    final name = (staff['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return staffId;
    final category = HealthcareStaffService.categoryFromData(staff);
    if (category == HealthcareStaffService.roleDoctor && !name.startsWith('Dr.')) {
      return 'Dr. $name';
    }
    if (name.startsWith('Dr.')) return name;
    return name;
  }

  String _specialty(Map<String, dynamic>? staff) {
    if (staff == null) return 'General';
    return HealthcareStaffService.specialtyFromData(staff);
  }

  DateTime? _parseDateTime(dynamic value) => ClinicDateTime.fromFirestore(value);

  static const _blockingStatuses = {'pending', 'scheduled', 'rescheduled'};

  bool _blocksSlot(String? status) {
    return _blockingStatuses.contains((status ?? '').trim().toLowerCase());
  }

  String? _staffIdFromAppointmentData(Map<String, dynamic> data) {
    for (final key in ['staffId', 'staffID']) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Open slot row in `appointments`: `dateTime` set, not yet booked by a patient.
  bool _isOpenSlotRecord(Map<String, dynamic> data) {
    final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
    if (_blocksSlot(data['status'] as String?) ||
        status == 'cancelled' ||
        status == 'done') {
      return false;
    }
    if (status == 'available') return true;

    final userId = data['userId']?.toString().trim() ?? '';
    return userId.isEmpty;
  }

  /// All `appointments` for [staffId] on [date] (Firestore `dateTime` field).
  Future<List<({String docId, Map<String, dynamic> data})>>
      _fetchAppointmentDocsForStaffOnDate({
    required String staffId,
    required DateTime date,
  }) async {
    final trimmedStaffId = staffId.trim();
    if (trimmedStaffId.isEmpty) return [];

    final dayStart = ClinicDateTime.clinicDayStart(date);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final seenDocIds = <String>{};
    final docs = <({String docId, Map<String, dynamic> data})>[];

    Future<void> collectFromQuery(String field) async {
      final snap = await _firestore
          .collection(_appointments)
          .where(field, isEqualTo: trimmedStaffId)
          .where(
            'dateTime',
            isGreaterThanOrEqualTo: ClinicDateTime.toTimestamp(dayStart),
          )
          .where(
            'dateTime',
            isLessThan: ClinicDateTime.toTimestamp(dayEnd),
          )
          .get();

      for (final doc in snap.docs) {
        if (!seenDocIds.add(doc.id)) continue;

        final data = doc.data();
        final docStaff = _staffIdFromAppointmentData(data);
        if (docStaff != null && docStaff != trimmedStaffId) continue;

        if (_parseDateTime(data['dateTime'] ?? data['scheduledAt']) == null) {
          continue;
        }

        docs.add((docId: doc.id, data: data));
      }
    }

    await collectFromQuery('staffId');
    await collectFromQuery('staffID');

    return docs;
  }

  List<DateTime> _bookedTimesFromDocs(
    List<({String docId, Map<String, dynamic> data})> docs,
  ) {
    final booked = <DateTime>[];
    for (final entry in docs) {
      if (!_blocksSlot(entry.data['status'] as String?)) continue;
      final dateTime = _parseDateTime(
        entry.data['dateTime'] ?? entry.data['scheduledAt'],
      );
      if (dateTime != null) booked.add(dateTime);
    }
    return AppointmentTimeSlots.dedupeMinutes(booked);
  }

  List<BookableSlot> _openSlotsFromDocs(
    List<({String docId, Map<String, dynamic> data})> docs,
  ) {
    final slots = <BookableSlot>[];
    for (final entry in docs) {
      if (!_isOpenSlotRecord(entry.data)) continue;

      final dateTime = _parseDateTime(
        entry.data['dateTime'] ?? entry.data['scheduledAt'],
      );
      if (dateTime == null) continue;

      slots.add(
        BookableSlot(
          dateTime: dateTime,
          firestoreDocId: entry.docId,
          appointmentId: entry.data['appointmentId']?.toString(),
        ),
      );
    }
    return slots;
  }

  Future<List<DateTime>> _templateTimesForStaffOnDate({
    required String staffId,
    required DateTime calendarDate,
  }) async {
    final trimmedStaffId = staffId.trim();

    if (trimmedStaffId.isNotEmpty) {
      for (final field in ['staffID', 'staffId']) {
        final snap = await _firestore
            .collection(_staff)
            .where(field, isEqualTo: trimmedStaffId)
            .where('status', isEqualTo: 'Active')
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final data = snap.docs.first.data();
          for (final key in [
            'availableTimeSlots',
            'timeSlots',
            'appointmentTimeSlots',
          ]) {
            final slots = AppointmentTimeSlots.parseSlotListForDate(
              data[key],
              calendarDate,
            );
            if (slots.isNotEmpty) return slots;
          }
        }
      }
    }

    final settingsSnap = await _firestore.doc(_settingsPath).get();
    if (settingsSnap.exists) {
      final data = settingsSnap.data();
      for (final key in ['timeSlots', 'availableTimeSlots', 'appointmentTimeSlots']) {
        final slots = AppointmentTimeSlots.parseSlotListForDate(
          data?[key],
          calendarDate,
        );
        if (slots.isNotEmpty) return slots;
      }
    }

    return AppointmentTimeSlots.defaultSlotsOnDate(calendarDate);
  }

  /// Loads slots from Firestore `appointments.dateTime`, hides times already booked.
  Future<List<BookableSlot>> fetchBookableSlotsForStaffOnDate({
    required String staffId,
    required DateTime date,
  }) async {
    final calendarDate = DateTime(date.year, date.month, date.day);
    final docs = await _fetchAppointmentDocsForStaffOnDate(
      staffId: staffId,
      date: calendarDate,
    );
    final booked = _bookedTimesFromDocs(docs);

    var candidates = _openSlotsFromDocs(docs);

    if (candidates.isEmpty) {
      final templates = await _templateTimesForStaffOnDate(
        staffId: staffId,
        calendarDate: calendarDate,
      );
      candidates = templates
          .map(
            (dateTime) => BookableSlot(
              dateTime: dateTime,
              firestoreDocId: '',
            ),
          )
          .toList();
    }

    final available = <BookableSlot>[];
    for (final slot in candidates) {
      if (!ClinicDateTime.isAfterNow(slot.dateTime)) continue;
      final isTaken = booked.any(
        (b) => AppointmentTimeSlots.sameMinute(b, slot.dateTime),
      );
      if (!isTaken) available.add(slot);
    }

    available.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return available;
  }

  Future<void> _assertSlotAvailable({
    required String staffId,
    required DateTime dateTime,
    String? firestoreDocId,
  }) async {
    final stillAvailable = await fetchBookableSlotsForStaffOnDate(
      staffId: staffId,
      date: dateTime,
    );
    final stillFree = stillAvailable.any((slot) {
      if (!AppointmentTimeSlots.sameMinute(slot.dateTime, dateTime)) {
        return false;
      }
      if (firestoreDocId != null &&
          firestoreDocId.isNotEmpty &&
          slot.hasExistingDocument) {
        return slot.firestoreDocId == firestoreDocId;
      }
      return true;
    });
    if (!stillFree) {
      throw StateError(
        'This time slot is no longer available. Please choose another time.',
      );
    }
  }

  Future<List<AppointmentItem>> fetchForCurrentPatient() async {
    final patientId = await _patientUserId();
    if (patientId == null) return [];

    final staffLookup = await _staffByStaffId();
    final snap = await _firestore
        .collection(_appointments)
        .where('userId', isEqualTo: patientId)
        .orderBy('dateTime')
        .get();

    final items = <AppointmentItem>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final dateTime =
          _parseDateTime(data['dateTime']) ?? _parseDateTime(data['scheduledAt']);
      if (dateTime == null) continue;

      final status = (data['status'] as String?)?.trim() ?? 'Scheduled';
      if (status.toLowerCase() == 'cancelled') continue;

      final staffId = _staffIdFromAppointmentData(data) ?? '';
      final staff = staffLookup[staffId];

      items.add(
        AppointmentItem(
          id: doc.id,
          doctorName: _doctorName(staff, staffId),
          specialty: _specialty(staff),
          dateTime: dateTime,
          location: (data['location'] as String?)?.trim() ?? '',
          status: status,
        ),
      );
    }
    return items;
  }

  Future<void> cancelAppointment(String appointmentId) async {
    await _firestore.collection(_appointments).doc(appointmentId).update({
      'status': 'Cancelled',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<List<StaffOption>> fetchBookableStaff({required String category}) async {
    return _staffService.fetchByRole(category);
  }

  Future<Map<String, List<StaffOption>>> fetchStaffGroupedByRole() async {
    return _staffService.fetchGroupedByRole();
  }

  Future<String> bookAppointment({
    required String staffId,
    required String appointmentType,
    required DateTime dateTime,
    String notes = '',
    String? existingFirestoreDocId,
    String? existingAppointmentId,
  }) async {
    final user = AuthSession.resolveUser() ?? _auth.currentUser;
    if (user == null) {
      throw StateError('You must be signed in to book an appointment.');
    }

    final userId = await _patientUserId();
    if (userId == null) {
      throw StateError('Patient profile not found. Complete registration first.');
    }

    await _firestore.collection('users').doc(user.uid).set(
      {'userId': userId},
      SetOptions(merge: true),
    );

    if (!ClinicDateTime.isAfterNow(dateTime)) {
      throw StateError('Please choose a future time slot.');
    }

    await _assertSlotAvailable(
      staffId: staffId,
      dateTime: dateTime,
      firestoreDocId: existingFirestoreDocId,
    );

    final trimmedDocId = existingFirestoreDocId?.trim() ?? '';
    if (trimmedDocId.isNotEmpty) {
      await _firestore.collection(_appointments).doc(trimmedDocId).update({
        'userId': userId,
        'status': 'Pending',
        'appointmentType': appointmentType,
        'notes': notes.trim(),
        'staffId': staffId,
        'dateTime': ClinicDateTime.toTimestamp(dateTime),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return existingAppointmentId?.trim().isNotEmpty == true
          ? existingAppointmentId!.trim()
          : trimmedDocId;
    }

    final counterRef = _firestore.doc(_counterPath);
    final appointmentsRef = _firestore.collection(_appointments);

    return _firestore.runTransaction<String>((transaction) async {
      final counterSnap = await transaction.get(counterRef);
      final next = counterSnap.exists
          ? (counterSnap.data()?['next'] as num?)?.toInt() ?? 1
          : 1;
      final appointmentId = 'A${next.toString().padLeft(5, '0')}';
      final appointmentRef = appointmentsRef.doc(appointmentId);

      transaction.set(counterRef, {'next': next + 1}, SetOptions(merge: true));
      transaction.set(appointmentRef, {
        'appointmentId': appointmentId,
        'dateTime': ClinicDateTime.toTimestamp(dateTime),
        'status': 'Pending',
        'notes': notes.trim(),
        'appointmentType': appointmentType,
        'userId': userId,
        'staffId': staffId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return appointmentId;
    });
  }
}
