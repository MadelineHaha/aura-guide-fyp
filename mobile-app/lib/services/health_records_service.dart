import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth_session.dart';
import '../models/health_record_item.dart';
import 'healthcare_staff_service.dart';
import 'user_profile_service.dart';

class HealthRecordsService {
  HealthRecordsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    UserProfileService? profileService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _profileService = profileService ?? UserProfileService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final UserProfileService _profileService;

  static const _collection = 'healthrecords';
  static const _staff = 'healthcarestaff';

  Future<String?> _patientUserId() async {
    final user = AuthSession.resolveUser() ?? _auth.currentUser;
    if (user == null) return null;
    final result =
        await _profileService.loadProfile(user.uid, syncAuthFirst: false);
    final id = (result.data['userId'] as String?)?.trim() ??
        (result.data['patientId'] as String?)?.trim();
    if (id == null || id.isEmpty) return null;

    await _firestore.collection('users').doc(user.uid).set(
      {'userId': id},
      SetOptions(merge: true),
    );
    return id;
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
    if (staff == null) {
      return staffId.isNotEmpty ? staffId : 'Healthcare provider';
    }
    final name = (staff['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) return staffId;
    final role = HealthcareStaffService.categoryFromData(staff);
    if (role == HealthcareStaffService.roleDoctor && !name.startsWith('Dr.')) {
      return 'Dr. $name';
    }
    return name;
  }

  HealthRecordItem? _mapDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, Map<String, dynamic>> staffLookup,
  ) {
    final data = doc.data();
    final staffId = (data['staffId'] as String?)?.trim() ??
        (data['staffID'] as String?)?.trim() ??
        '';
    final staff = staffLookup[staffId];

    final recordType = (data['recordType'] as String?)?.trim();
    final summary = (data['title'] as String?)?.trim();
    final userId = (data['userId'] as String?)?.trim() ??
        (data['userID'] as String?)?.trim() ??
        '';

    final fileData = data['fileData'];
    final hasInlineFile = fileData != null && fileData.toString().isNotEmpty;
    final fileStorage = (data['fileStorage'] as String?)?.trim() ?? '';

    return HealthRecordItem(
      recordId: (data['recordId'] as String?)?.trim() ?? doc.id,
      recordType: recordType?.isNotEmpty == true ? recordType! : 'Health record',
      dateCreated: (data['dateCreated'] as String?)?.trim() ?? '—',
      doctorName: _doctorName(staff, staffId),
      summary: summary?.isNotEmpty == true ? summary! : '—',
      fileType: (data['fileType'] as String?)?.trim() ?? '',
      filePath: (data['filePath'] as String?)?.trim() ?? '',
      hasInlineFile: hasInlineFile || fileStorage.toLowerCase() == 'firestore',
      userId: userId,
    );
  }

  List<HealthRecordItem> _mapAndSort(
    QuerySnapshot<Map<String, dynamic>> snap,
    Map<String, Map<String, dynamic>> staffLookup,
  ) {
    final items = <HealthRecordItem>[];
    for (final doc in snap.docs) {
      final item = _mapDoc(doc, staffLookup);
      if (item != null) items.add(item);
    }
    items.sort((a, b) => b.dateCreated.compareTo(a.dateCreated));
    return items;
  }

  Future<List<HealthRecordItem>> fetchForCurrentPatient() async {
    final patientId = await _patientUserId();
    if (patientId == null) return [];

    final staffLookup = await _staffByStaffId();
    final snap = await _firestore
        .collection(_collection)
        .where('userId', isEqualTo: patientId)
        .get();

    return _mapAndSort(snap, staffLookup);
  }

  Stream<List<HealthRecordItem>>? _recordsStreamCache;

  Stream<List<HealthRecordItem>> watchForCurrentPatient() {
    return _recordsStreamCache ??= _createWatchStream();
  }

  bool _isPermissionDenied(Object error) {
    if (error is FirebaseException) {
      return error.code == 'permission-denied';
    }
    return error.toString().contains('permission-denied');
  }

  Stream<List<HealthRecordItem>> _createWatchStream() {
    return Stream.multi((controller) async {
      Future<void> emitRecords(QuerySnapshot<Map<String, dynamic>> snap) async {
        if (controller.isClosed) return;
        try {
          final staffLookup = await _staffByStaffId();
          controller.add(_mapAndSort(snap, staffLookup));
        } catch (e) {
          if (_isPermissionDenied(e)) {
            controller.add([]);
          } else if (!controller.isClosed) {
            controller.addError(e);
          }
        }
      }

      try {
        final patientId = await _patientUserId();
        if (patientId == null) {
          controller.add([]);
          await controller.close();
          return;
        }

        QuerySnapshot<Map<String, dynamic>> recordsSnap;
        try {
          recordsSnap = await _firestore
              .collection(_collection)
              .where('userId', isEqualTo: patientId)
              .get();
        } on FirebaseException catch (e) {
          if (_isPermissionDenied(e)) {
            controller.add([]);
            await controller.close();
            return;
          }
          rethrow;
        }

        await emitRecords(recordsSnap);

        final recordsSub = _firestore
            .collection(_collection)
            .where('userId', isEqualTo: patientId)
            .snapshots()
            .listen(
          (snap) => emitRecords(snap),
          onError: (error) {
            if (_isPermissionDenied(error)) {
              controller.add([]);
            } else if (!controller.isClosed) {
              controller.addError(error);
            }
          },
        );

        controller.onCancel = () {
          recordsSub.cancel();
        };
      } catch (e, st) {
        if (_isPermissionDenied(e)) {
          if (!controller.isClosed) controller.add([]);
        } else if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    });
  }
}
