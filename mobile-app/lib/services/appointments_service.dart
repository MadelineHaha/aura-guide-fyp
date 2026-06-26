import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth_session.dart';
import '../models/appointment_item.dart';
import '../models/bookable_slot.dart';
import '../models/staff_option.dart';
import '../utils/appointment_time_slots.dart';
import '../utils/clinic_datetime.dart';
import 'activity_log_actions.dart';
import 'activity_log_service.dart';
import 'healthcare_staff_service.dart';
import '../utils/localized_staff_name.dart';
import 'app_settings_service.dart';
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

  String _staffDisplayName(Map<String, dynamic>? staff, String staffId) {
    if (staff == null) return staffId.isNotEmpty ? staffId : 'Healthcare provider';
    final name = (staff['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return staffId;
    final role = staff['role']?.toString() ??
        HealthcareStaffService.roleLabelForCategory(
          HealthcareStaffService.categoryFromData(staff) ?? '',
        );
    return LocalizedStaffName.format(
      name,
      AppSettingsService.instance.settings.languageCode,
      role: role,
    );
  }

  String _appointmentType(Map<String, dynamic> data) {
    final value = (data['appointmentType'] as String?)?.trim() ??
        (data['type'] as String?)?.trim();
    if (value != null && value.isNotEmpty) return value;
    return '—';
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
    List<({String docId, Map<String, dynamic> data})> docs, {
    String? excludeDocId,
  }) {
    final booked = <DateTime>[];
    for (final entry in docs) {
      if (excludeDocId != null && entry.docId == excludeDocId) continue;
      if (!_blocksSlot(entry.data['status'] as String?)) continue;
      final dateTime = _parseDateTime(
        entry.data['dateTime'] ?? entry.data['scheduledAt'],
      );
      if (dateTime != null) booked.add(dateTime);
    }
    return AppointmentTimeSlots.dedupeMinutes(booked);
  }

  /// Loads standard clinic slots for [date], hiding times already booked.
  Future<List<BookableSlot>> fetchBookableSlotsForStaffOnDate({
    required String staffId,
    required DateTime date,
    String? excludeAppointmentDocId,
  }) async {
    final calendarDate = DateTime(date.year, date.month, date.day);
    var booked = <DateTime>[];

    try {
      final docs = await _fetchAppointmentDocsForStaffOnDate(
        staffId: staffId,
        date: calendarDate,
      );
      booked = _bookedTimesFromDocs(
        docs,
        excludeDocId: excludeAppointmentDocId,
      );
    } catch (e) {
      // Still show clinic slots if the booked-times query fails (e.g. rules/index).
      assert(() {
        // ignore: avoid_print
        print('AppointmentsService: could not load booked slots: $e');
        return true;
      }());
    }

    final available = <BookableSlot>[];
    for (final dateTime in AppointmentTimeSlots.clinicSlotsOnDate(calendarDate)) {
      if (!ClinicDateTime.isAfterNow(dateTime)) continue;
      final isTaken = booked.any(
        (b) => AppointmentTimeSlots.sameMinute(b, dateTime),
      );
      if (!isTaken) {
        available.add(
          BookableSlot(dateTime: dateTime, firestoreDocId: ''),
        );
      }
    }

    available.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return available;
  }

  Future<void> _assertSlotAvailable({
    required String staffId,
    required DateTime dateTime,
    String? firestoreDocId,
    String? excludeAppointmentDocId,
  }) async {
    final stillAvailable = await fetchBookableSlotsForStaffOnDate(
      staffId: staffId,
      date: dateTime,
      excludeAppointmentDocId: excludeAppointmentDocId,
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

  static int countUpcoming(List<AppointmentItem> items) =>
      items.where((a) => !a.isPast).length;

  /// Live upcoming count for the main menu Appointments tile.
  Stream<int> watchUpcomingAppointmentCount() async* {
    final patientId = await _patientUserId();
    if (patientId == null) {
      yield 0;
      return;
    }

    yield countUpcoming(await fetchForCurrentPatient());

    await for (final _ in _firestore
        .collection(_appointments)
        .where('userId', isEqualTo: patientId)
        .snapshots()) {
      yield countUpcoming(await fetchForCurrentPatient());
    }
  }

  Future<List<AppointmentItem>> fetchForCurrentPatient() async {
    final patientId = await _patientUserId();
    if (patientId == null) return [];
    return fetchForPatient(patientId);
  }

  Future<List<AppointmentItem>> fetchForPatient(String patientId) async {
    final trimmed = patientId.trim();
    if (trimmed.isEmpty) return [];

    final staffLookup = await _staffByStaffId();
    final snap = await _firestore
        .collection(_appointments)
        .where('userId', isEqualTo: trimmed)
        .orderBy('dateTime')
        .get();

    return _mapAppointmentDocs(snap.docs, staffLookup);
  }

  Future<List<AppointmentItem>> fetchForStaff(String staffId) async {
    final trimmedStaffId = staffId.trim();
    if (trimmedStaffId.isEmpty) return [];

    final staffLookup = await _staffByStaffId();
    final seen = <String>{};
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

    Future<void> collect(String field) async {
      final snap = await _firestore
          .collection(_appointments)
          .where(field, isEqualTo: trimmedStaffId)
          .orderBy('dateTime')
          .get();
      for (final doc in snap.docs) {
        if (seen.add(doc.id)) docs.add(doc);
      }
    }

    await collect('staffId');
    await collect('staffID');

    docs.sort((a, b) {
      final aTime = _parseDateTime(a.data()['dateTime']) ??
          _parseDateTime(a.data()['scheduledAt']);
      final bTime = _parseDateTime(b.data()['dateTime']) ??
          _parseDateTime(b.data()['scheduledAt']);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return aTime.compareTo(bTime);
    });

    return _mapAppointmentDocs(docs, staffLookup);
  }

  List<AppointmentItem> _mapAppointmentDocs(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    Map<String, Map<String, dynamic>> staffLookup,
  ) {
    final items = <AppointmentItem>[];
    for (final doc in docs) {
      final data = doc.data();
      final dateTime =
          _parseDateTime(data['dateTime']) ?? _parseDateTime(data['scheduledAt']);
      if (dateTime == null) continue;

      final status = (data['status'] as String?)?.trim() ?? 'Scheduled';
      if (status.toLowerCase() == 'cancelled') continue;

      final docStaffId = _staffIdFromAppointmentData(data) ?? '';
      final staff = staffLookup[docStaffId];

      items.add(
        AppointmentItem(
          id: doc.id,
          staffId: docStaffId,
          doctorName: _staffDisplayName(staff, docStaffId),
          appointmentType: _appointmentType(data),
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
    unawaited(
      ActivityLogService.instance.log(
        action: ActivityLogActions.updateAppointmentStatus,
        details: 'Cancelled appointment $appointmentId.',
      ),
    );
  }

  Future<void> rescheduleAppointment({
    required String appointmentDocId,
    required String staffId,
    required DateTime newDateTime,
  }) async {
    final userId = await _patientUserId();
    if (userId == null) {
      throw StateError('Patient profile not found.');
    }

    final docRef = _firestore.collection(_appointments).doc(appointmentDocId);
    final snap = await docRef.get();
    if (!snap.exists) {
      throw StateError('Appointment not found.');
    }

    final data = snap.data()!;
    if ((data['userId'] as String?)?.trim() != userId) {
      throw StateError('You cannot reschedule this appointment.');
    }

    final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
    if (status != 'scheduled' && status != 'rescheduled') {
      throw StateError('This appointment cannot be rescheduled yet.');
    }

    if (!ClinicDateTime.isAfterNow(newDateTime)) {
      throw StateError('Please choose a future time slot.');
    }

    final currentDateTime = _parseDateTime(data['dateTime'] ?? data['scheduledAt']);
    if (currentDateTime != null &&
        AppointmentTimeSlots.sameMinute(currentDateTime, newDateTime)) {
      throw StateError('Please choose a different date or time.');
    }

    final trimmedStaffId = staffId.trim();
    if (trimmedStaffId.isEmpty) {
      throw StateError('Staff information is missing for this appointment.');
    }

    await _assertSlotAvailable(
      staffId: trimmedStaffId,
      dateTime: newDateTime,
      excludeAppointmentDocId: appointmentDocId,
    );

    await docRef.update({
      'dateTime': ClinicDateTime.toTimestamp(newDateTime),
      'status': 'Rescheduled',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    unawaited(
      ActivityLogService.instance.log(
        action: ActivityLogActions.updateAppointment,
        details:
            'Rescheduled appointment $appointmentDocId to ${_formatClinicDateTime(newDateTime)}.',
        userId: userId,
      ),
    );
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
      final bookedId = existingAppointmentId?.trim().isNotEmpty == true
          ? existingAppointmentId!.trim()
          : trimmedDocId;
      unawaited(
        ActivityLogService.instance.log(
          action: ActivityLogActions.bookAppointment,
          details:
              'Booked $appointmentType on ${_formatClinicDateTime(dateTime)}.',
          userId: userId,
        ),
      );
      return bookedId;
    }

    final counterRef = _firestore.doc(_counterPath);
    final appointmentsRef = _firestore.collection(_appointments);

    final appointmentId = await _firestore.runTransaction<String>((transaction) async {
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
    unawaited(
      ActivityLogService.instance.log(
        action: ActivityLogActions.bookAppointment,
        details:
            'Booked $appointmentType on ${_formatClinicDateTime(dateTime)}.',
        userId: userId,
      ),
    );
    return appointmentId;
  }
}

String _formatClinicDateTime(DateTime dateTime) {
  final y = dateTime.year;
  final m = dateTime.month.toString().padLeft(2, '0');
  final d = dateTime.day.toString().padLeft(2, '0');
  final hh = dateTime.hour.toString().padLeft(2, '0');
  final mm = dateTime.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}
