import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth_session.dart';
import '../models/health_record_item.dart';
import '../utils/clinic_datetime.dart';
import '../utils/localized_date_format.dart';
import '../utils/localized_staff_name.dart';
import '../utils/voice_option_parser.dart';
import 'app_settings_service.dart';
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

  String _staffDisplayName(Map<String, dynamic>? staff, String staffId) {
    if (staff == null) {
      return staffId.isNotEmpty ? staffId : 'Healthcare provider';
    }
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
      doctorName: _staffDisplayName(staff, staffId),
      summary: summary?.isNotEmpty == true ? summary! : '—',
      fileType: (data['fileType'] as String?)?.trim() ?? '',
      filePath: (data['filePath'] as String?)?.trim() ?? '',
      hasInlineFile: hasInlineFile || fileStorage.toLowerCase() == 'firestore',
      userId: userId,
      uploadedAt: ClinicDateTime.fromFirestore(
        data['createdAt'] ?? data['uploadedAt'],
      ),
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

  Future<List<HealthRecordItem>> fetchForPatient(String patientId) async {
    final trimmed = patientId.trim();
    if (trimmed.isEmpty) return [];
    final staffLookup = await _staffByStaffId();
    final snap = await _firestore
        .collection(_collection)
        .where('userId', isEqualTo: trimmed)
        .get();
    return _mapAndSort(snap, staffLookup);
  }

  Stream<List<HealthRecordItem>> watchForPatient(String patientId) {
    final trimmed = patientId.trim();
    if (trimmed.isEmpty) {
      return Stream.value(const []);
    }
    return Stream.multi((controller) async {
      Future<void> emitRecords(
        QuerySnapshot<Map<String, dynamic>> snap,
      ) async {
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
        final recordsSnap = await _firestore
            .collection(_collection)
            .where('userId', isEqualTo: trimmed)
            .get();
        await emitRecords(recordsSnap);

        final recordsSub = _firestore
            .collection(_collection)
            .where('userId', isEqualTo: trimmed)
            .snapshots()
            .listen(
          emitRecords,
          onError: (error) {
            if (_isPermissionDenied(error)) {
              controller.add([]);
            } else if (!controller.isClosed) {
              controller.addError(error);
            }
          },
        );

        controller.onCancel = recordsSub.cancel;
      } catch (e, st) {
        if (_isPermissionDenied(e)) {
          if (!controller.isClosed) controller.add([]);
        } else if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    });
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

  static bool isUploadedToday(HealthRecordItem record) {
    final uploadedAt = record.uploadedAt;
    if (uploadedAt != null) {
      final now = ClinicDateTime.nowClinic();
      return uploadedAt.year == now.year &&
          uploadedAt.month == now.month &&
          uploadedAt.day == now.day;
    }

    final created = record.dateCreated.trim();
    if (created.isEmpty || created == '—') return false;

    final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(created);
    if (isoMatch != null) {
      final now = ClinicDateTime.nowClinic();
      final year = int.tryParse(isoMatch.group(1)!);
      final month = int.tryParse(isoMatch.group(2)!);
      final day = int.tryParse(isoMatch.group(3)!);
      if (year == null || month == null || day == null) return false;
      return year == now.year && month == now.month && day == now.day;
    }

    return created.toLowerCase().contains(
      ClinicDateTime.nowClinic().day.toString(),
    );
  }

  static List<HealthRecordItem> recordsUploadedToday(
    List<HealthRecordItem> records,
  ) {
    return records.where(isUploadedToday).toList();
  }

  static List<HealthRecordItem> recordsUploadedBeforeToday(
    List<HealthRecordItem> records,
  ) {
    return records.where((record) => !isUploadedToday(record)).toList();
  }

  static String buildVoiceIntro(
    List<HealthRecordItem> records,
    String Function(String key, [Map<String, Object?> params]) l10n,
  ) {
    if (records.isEmpty) {
      return l10n('voiceHealthRecordsEmpty');
    }

    final todayCount = recordsUploadedToday(records).length;
    return l10n('voiceHealthRecordsIntro', {'count': todayCount});
  }

  static String buildRecordsListSpeech(
    List<HealthRecordItem> records,
    String Function(String key, [Map<String, Object?> params]) l10n,
    String languageCode,
  ) {
    if (records.isEmpty) {
      return l10n('voiceHealthRecordsListEmpty');
    }

    final parts = <String>[];
    for (var i = 0; i < records.length; i++) {
      parts.add(_formatVoiceListEntry(records[i], i, l10n, languageCode));
    }
    return parts.join(', ');
  }

  static HealthRecordsVoiceChoice? parseVoiceChoice(String speech) {
    final option = VoiceOptionParser.extractOptionNumber(speech, 2);
    if (option == 1) return HealthRecordsVoiceChoice.today;
    if (option == 2) return HealthRecordsVoiceChoice.other;

    final normalized = _normalizeSpeech(speech);
    if (normalized.isEmpty) return null;

    const todayPhrases = [
      'today',
      'todays',
      'today s',
      'today records',
      'today health records',
      'hear today',
      'today only',
      'uploaded today',
      'hari ini',
      '今天',
      '今日',
      '今天的记录',
    ];
    const otherPhrases = [
      'other',
      'other records',
      'other health records',
      'listen to other',
      'hear other',
      'the rest',
      'previous records',
      'older records',
      'not today',
      'lain',
      'rekod lain',
      '其他',
      '其他记录',
    ];

    if (otherPhrases.any(normalized.contains)) {
      return HealthRecordsVoiceChoice.other;
    }
    if (todayPhrases.any(normalized.contains)) {
      return HealthRecordsVoiceChoice.today;
    }
    return null;
  }

  static String _formatVoiceListEntry(
    HealthRecordItem record,
    int index,
    String Function(String key, [Map<String, Object?> params]) l10n,
    String languageCode,
  ) {
    final ordinal = _ordinalLabel(index, l10n);
    final title = _voiceTitle(record);
    final staff = record.doctorName.trim().isEmpty
        ? l10n('voiceHealthRecordsUnknownStaff')
        : record.doctorName;
    final date = _voiceDate(record, languageCode);
    final time = _voiceTime(record, languageCode);

    if (time.isEmpty) {
      return l10n('voiceHealthRecordsListEntryDateOnly', {
        'ordinal': ordinal,
        'title': title,
        'staff': staff,
        'date': date,
      });
    }

    return l10n('voiceHealthRecordsListEntry', {
      'ordinal': ordinal,
      'title': title,
      'staff': staff,
      'date': date,
      'time': time,
    });
  }

  static String _voiceTitle(HealthRecordItem record) {
    final type = record.recordType.trim();
    if (type.isNotEmpty && type != '—' && type.toLowerCase() != 'health record') {
      return type;
    }
    final summary = record.summary.trim();
    if (summary.isNotEmpty && summary != '—') return summary;
    return type.isNotEmpty ? type : 'Health record';
  }

  static String _voiceDate(HealthRecordItem record, String languageCode) {
    final uploadedAt = record.uploadedAt;
    if (uploadedAt != null) {
      return LocalizedDateFormat.spokenDate(uploadedAt, languageCode);
    }
    final created = record.dateCreated.trim();
    return created.isEmpty || created == '—'
        ? LocalizedDateFormat.spokenDate(
            ClinicDateTime.nowClinic(),
            languageCode,
          )
        : created;
  }

  static String _voiceTime(HealthRecordItem record, String languageCode) {
    final uploadedAt = record.uploadedAt;
    if (uploadedAt == null) return '';

    final hour = uploadedAt.hour;
    final minute = uploadedAt.minute.toString().padLeft(2, '0');
    switch (languageCode) {
      case 'zh':
        final period = hour >= 12 ? '下午' : '上午';
        final hour12 = hour % 12 == 0 ? 12 : hour % 12;
        return '$period$hour12点$minute分';
      case 'ms':
        final period = hour >= 12 ? 'PTG' : 'PG';
        final hour12 = hour % 12 == 0 ? 12 : hour % 12;
        return '$hour12:$minute $period';
      default:
        final period = hour >= 12 ? 'PM' : 'AM';
        final hour12 = hour % 12 == 0 ? 12 : hour % 12;
        return '$hour12:$minute $period';
    }
  }

  static String _ordinalLabel(
    int index,
    String Function(String key, [Map<String, Object?> params]) l10n,
  ) {
    const keys = [
      'voiceHealthRecordsOrdinalFirst',
      'voiceHealthRecordsOrdinalSecond',
      'voiceHealthRecordsOrdinalThird',
      'voiceHealthRecordsOrdinalFourth',
      'voiceHealthRecordsOrdinalFifth',
      'voiceHealthRecordsOrdinalSixth',
      'voiceHealthRecordsOrdinalSeventh',
      'voiceHealthRecordsOrdinalEighth',
      'voiceHealthRecordsOrdinalNinth',
      'voiceHealthRecordsOrdinalTenth',
    ];
    if (index >= 0 && index < keys.length) {
      return l10n(keys[index]);
    }
    return l10n('voiceHealthRecordsOrdinalNumber', {'n': index + 1});
  }

  static String _normalizeSpeech(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}

enum HealthRecordsVoiceChoice {
  today,
  other,
}
