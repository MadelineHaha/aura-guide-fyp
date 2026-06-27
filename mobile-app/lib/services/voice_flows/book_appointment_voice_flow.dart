import 'package:flutter/material.dart';

import '../../app_navigator.dart';
import '../../book_appointment_page.dart';
import '../../models/book_appointment_session.dart';
import '../../models/bookable_slot.dart';
import '../../models/staff_option.dart';
import '../../utils/appointment_types.dart';
import '../../utils/appointment_time_slots.dart';
import '../../utils/temporal_parser.dart';
import '../../utils/voice_option_parser.dart';
import '../app_settings_service.dart';
import '../voice_assistant_coordinator.dart';

enum _ModifyPart { role, staff, session, date, time, cancel }

/// Multi-step spoken dialogue for booking an appointment.
class BookAppointmentVoiceFlow {
  BookAppointmentVoiceFlow(this.session);

  final BookAppointmentSession session;
  final _settings = AppSettingsService.instance;
  final _assistant = VoiceAssistantCoordinator.instance;

  String _l10n(String key, [Map<String, Object?> params = const {}]) {
    return _settings.localized(key, params);
  }

  Future<void> run() async {
    try {
      await _ensureBookingDetails();

      while (true) {
        final confirmed = await _confirmBooking();
        if (confirmed == true) {
          await _submitBooking();
          return;
        }
        if (confirmed == false) {
          final part = await _askModifyPart();
          if (part == _ModifyPart.cancel) {
            await _assistant.speakPrompt('voiceFlowBookingCancelled');
            rootNavigatorKey.currentState?.pop();
            return;
          }
          if (part != null) {
            await _applyModification(part);
          }
          continue;
        }
      }
    } on VoiceFlowNavigationException {
      // Navigation already handled (e.g. user said "go back").
    } on VoiceFlowCancelledException {
      await _assistant.speakPrompt('voiceFlowBookingCancelled');
      rootNavigatorKey.currentState?.pop();
    }
  }

  Future<void> _ensureBookingDetails() async {
    if (session.roleKey == null) {
      await session.selectRole(await _askRole());
    }
    if (session.selectedStaff == null) {
      await session.selectStaff(await _askStaff());
    }
    if (session.sessionKey == null) {
      await session.selectSession(await _askSessionType());
    }
    if (session.selectedDate == null) {
      await session.selectDate(await _askDate());
    }
    if (session.selectedSlot == null) {
      session.selectSlot(await _askSlot());
    }
  }

  Future<void> _submitBooking() async {
    final success = await session.submitBooking(
      session.sessionCanonicalTypeForKey(
        session.sessionKey ?? AppointmentTypes.doctorOptions.first.key,
      ),
    );
    if (success) {
      await _assistant.speakPrompt('voiceFlowBookingSuccess');
      rootNavigatorKey.currentState?.pop(true);
    } else {
      await _assistant.speakPrompt('voiceFlowBookingFailed');
    }
  }

  Map<String, Object?> _confirmParams() {
    return {
      'type': session.sessionTitleForKey(
        session.sessionKey ?? AppointmentTypes.doctorOptions.first.key,
        _l10n,
      ),
      'staff': session.selectedStaff?.displayName ?? '',
      'date': _formatDate(session.selectedDate!),
      'time': AppointmentTimeSlots.formatTimeLabel(
        session.selectedSlot!.dateTime,
      ),
    };
  }

  Future<bool?> _confirmBooking() async {
    while (true) {
      final answer = await _assistant.promptAndListen(
        'voiceFlowBookConfirm',
        params: _confirmParams(),
      );
      if (_isAffirmative(answer)) return true;
      if (_isNegative(answer)) return false;
      await _assistant.speakPrompt('voiceFlowBookConfirmRetry');
    }
  }

  Future<_ModifyPart?> _askModifyPart() async {
    String promptKey = 'voiceFlowBookModifyAsk';
    while (true) {
      final answer = await _assistant.promptAndListen(promptKey);
      final parsed = _parseModifyPart(answer);
      if (parsed != null) return parsed;
      promptKey = 'voiceFlowBookModifyRetry';
    }
  }

  Future<void> _applyModification(_ModifyPart part) async {
    switch (part) {
      case _ModifyPart.role:
        session.prepareVoiceModifyRole();
        await session.selectRole(await _askRole());
        await session.selectStaff(await _askStaff());
        await session.selectSession(await _askSessionType());
        await session.selectDate(await _askDate());
        session.selectSlot(await _askSlot());
      case _ModifyPart.staff:
        session.prepareVoiceModifyStaff();
        if (session.roleKey != null) {
          await session.loadStaffForRole(session.roleKey!);
        }
        await session.selectStaff(await _askStaff());
        await session.selectDate(await _askDate());
        session.selectSlot(await _askSlot());
      case _ModifyPart.session:
        session.prepareVoiceModifySession();
        await session.selectSession(await _askSessionType());
        await session.selectDate(await _askDate());
        session.selectSlot(await _askSlot());
      case _ModifyPart.date:
        session.prepareVoiceModifyDate();
        await session.selectDate(await _askDate());
        session.selectSlot(await _askSlot());
      case _ModifyPart.time:
        session.prepareVoiceModifyTime();
        session.selectSlot(await _askSlot());
      case _ModifyPart.cancel:
        break;
    }
  }

  _ModifyPart? _parseModifyPart(String? answer) {
    final raw = (answer ?? '').trim();
    if (raw.isEmpty) return null;

    const parts = [
      _ModifyPart.role,
      _ModifyPart.staff,
      _ModifyPart.session,
      _ModifyPart.date,
      _ModifyPart.time,
      _ModifyPart.cancel,
    ];
    final byOption = VoiceOptionParser.selectByOptionIndex(parts, raw);
    if (byOption != null) return byOption;

    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);

    if (_containsAny(raw, const ['取消', 'batal']) ||
        _containsAny(text, const ['cancel', 'stop', 'quit', 'never mind', 'abort'])) {
      return _ModifyPart.cancel;
    }
    if (_containsAny(raw, const ['类型', '会话']) ||
        _containsAny(text, const ['session type', 'session', 'appointment type', 'type'])) {
      return _ModifyPart.session;
    }
    if (_containsAny(raw, const ['职员', '人员', '医护']) ||
        _containsAny(text, const ['staff', 'provider', 'doctor name', 'therapist name'])) {
      return _ModifyPart.staff;
    }
    if (_containsAny(raw, const ['时间', '时段']) ||
        _containsAny(text, const ['time', 'slot', 'hour'])) {
      return _ModifyPart.time;
    }
    if (_containsAny(raw, const ['日期', '日子']) ||
        _containsAny(text, const ['date', 'day'])) {
      return _ModifyPart.date;
    }
    if (_containsAny(raw, const ['角色', '医生', '治疗师']) ||
        _containsAny(text, const ['role', 'doctor', 'therapist', 'specialist'])) {
      return _ModifyPart.role;
    }
    return null;
  }

  bool _isAffirmative(String? answer) {
    final raw = (answer ?? '').trim();
    if (raw.isEmpty) return false;
    if (_containsAny(raw, const ['是', '好', '确认', '对', '可以'])) return true;
    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);
    return _containsAny(
      text,
      const ['yes', 'yeah', 'yep', 'confirm', 'book', 'ok', 'okay', 'ya', 'sure'],
    );
  }

  bool _isNegative(String? answer) {
    final raw = (answer ?? '').trim();
    if (raw.isEmpty) return false;
    if (_containsAny(raw, const ['不', '否', '不要', '不是', 'tidak'])) return true;
    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);
    return _containsAny(
      text,
      const ['no', 'nope', 'change', 'modify', 'edit', 'wrong', 'not'],
    );
  }

  Future<String> _askSessionType() async {
    final options = BookAppointmentSession.sessionOptionsForRole(session.roleKey);
    final labels = options.map((option) => _l10n(option.titleKey)).toList();
    final optionsText = _numberedList(labels);
    final params = {'options': optionsText};

    while (true) {
      var answer = await _assistant.promptAndListen(
        'voiceFlowAskSessionType',
        params: params,
      );
      final selected = _parseSessionType(answer, options);
      if (selected != null) return selected;

      while (true) {
        final recoveryKey = _sessionTypeRecoveryPromptKey(answer);
        answer = await _assistant.speakPromptAndListen(
          recoveryKey,
          params: params,
        );

        if (_wantsRepeatSessionTypes(answer)) break;

        final fromRecovery = _parseSessionType(answer, options);
        if (fromRecovery != null) return fromRecovery;
      }
    }
  }

  String _sessionTypeRecoveryPromptKey(String? answer) {
    if (answer == null || answer.trim().isEmpty) {
      return 'voiceFlowSessionTypeNotCapturedRepeatOrNumber';
    }
    return 'voiceFlowSessionTypeInvalidRepeatOrNumber';
  }

  bool _wantsRepeatSessionTypes(String? answer) {
    final raw = (answer ?? '').trim();
    if (raw.isEmpty) return false;
    if (_containsAny(raw, const ['是', '好', '重复', '再听', '再说'])) return true;

    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);
    if (text.isEmpty) return false;
    return _containsAny(
      text,
      const [
        'yes',
        'yeah',
        'yep',
        'repeat',
        'again',
        'listen',
        'ulang',
        'dengar',
        'semula',
      ],
    );
  }

  bool _wantsRepeatTimeSlots(String? answer) {
    final raw = (answer ?? '').trim();
    if (raw.isEmpty) return false;
    if (_containsAny(raw, const ['是', '好', '重复', '再听', '再说'])) return true;

    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);
    if (text.isEmpty) return false;
    return _containsAny(
      text,
      const [
        'yes',
        'yeah',
        'yep',
        'repeat',
        'again',
        'listen',
        'ulang',
        'dengar',
        'semula',
        'slots',
      ],
    );
  }

  Future<String> _askRole() async {
    String promptKey = 'voiceFlowAskRole';
    while (true) {
      final answer = await _assistant.promptAndListen(promptKey);
      final parsed = _parseRole(answer);
      if (parsed != null) return parsed;
      promptKey = 'voiceFlowRoleRetry';
    }
  }

  Future<StaffOption> _askStaff() async {
    String promptKey = 'voiceFlowAskStaff';
    while (true) {
      if (session.loadingStaff) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      if (session.staff.isEmpty) {
        await _assistant.speakPrompt('voiceFlowNoStaff');
        throw StateError('No staff available for role');
      }

      final names = session.staff
          .map((member) => member.localizedDisplayName(_settings.settings.languageCode))
          .toList();
      final answer = await _assistant.promptAndListen(
        promptKey,
        params: {'options': _numberedList(names)},
      );
      final picked = _parseStaffChoice(answer, session.staff);
      if (picked != null) return picked;
      promptKey = 'voiceFlowStaffRetry';
    }
  }

  Future<DateTime> _askDate() async {
    String promptKey = 'voiceFlowAskDate';
    while (true) {
      final answer = await _assistant.promptAndListen(promptKey);
      final parsed = _parseDate(answer);
      if (parsed != null) return parsed;
      promptKey = 'voiceFlowDateRetry';
    }
  }

  Future<BookableSlot> _askSlot() async {
    while (true) {
      if (session.loadingSlots) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      if (session.availableSlots.isEmpty) {
        await _assistant.speakPrompt('voiceFlowNoSlots');
        final retryDate = await _askDate();
        await session.selectDate(retryDate);
        continue;
      }

      final slots = session.availableSlots;
      final optionsText = _slotOptionsText(slots);
      var answer = await _assistant.promptAndListen(
        'voiceFlowAskTime',
        params: {'options': optionsText},
      );
      var picked = _parseSlotChoice(answer, slots);
      if (picked != null) return picked;

      while (true) {
        final recoveryKey = _timeRecoveryPromptKey(answer, slots);
        final params = recoveryKey == 'voiceFlowTimeUnavailableRepeatOrChoose'
            ? {'time': _formatRequestedTimeLabel(answer)}
            : const <String, Object?>{};

        answer = await _assistant.speakPromptAndListen(recoveryKey, params: params);

        if (_wantsRepeatTimeSlots(answer)) break;

        picked = _parseSlotChoice(answer, slots);
        if (picked != null) return picked;
      }
    }
  }

  String _slotOptionsText(List<BookableSlot> slots) {
    final labels = slots
        .map((slot) => AppointmentTimeSlots.formatTimeLabel(slot.dateTime))
        .toList();
    return _numberedList(labels);
  }

  String _timeRecoveryPromptKey(String? answer, List<BookableSlot> slots) {
    if (answer == null || answer.trim().isEmpty) {
      return 'voiceFlowTimeNotCapturedRepeatOrChoose';
    }
    if (_looksLikeTimeRequest(answer) && _parseSlotChoice(answer, slots) == null) {
      return 'voiceFlowTimeUnavailableRepeatOrChoose';
    }
    return 'voiceFlowTimeInvalidRepeatOrChoose';
  }

  bool _looksLikeTimeRequest(String answer) {
    return TemporalParser.looksLikeTimeExpression(answer);
  }

  String _formatRequestedTimeLabel(String? answer) {
    final raw = (answer ?? '').trim();
    if (raw.isEmpty) return raw;

    final parsed = TemporalParser.extractTime(raw);
    if (parsed != null) {
      final base = session.selectedDate ?? DateTime.now();
      return AppointmentTimeSlots.formatTimeLabel(
        DateTime(
          base.year,
          base.month,
          base.day,
          parsed.hour,
          parsed.minute ?? 0,
        ),
      );
    }

    return raw;
  }

  String _numberedList(List<String> items) =>
      VoiceOptionParser.formatNumberedList(items);

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String? _parseSessionType(String? answer, List<AppointmentTypeOption> options) {
    final raw = (answer ?? '').trim();
    if (raw.isEmpty) return null;

    final number = VoiceOptionParser.extractOptionNumber(raw, options.length);
    if (number != null) return options[number - 1].key;

    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);
    if (text.isEmpty) return null;

    for (final option in options) {
      final localized = VoiceAssistantCoordinator.normalizeSpeech(_l10n(option.titleKey));
      if (localized.isNotEmpty && text.contains(localized)) return option.key;

      final canonical = VoiceAssistantCoordinator.normalizeSpeech(option.canonicalType);
      if (canonical.isNotEmpty && text.contains(canonical)) return option.key;

      if (_matchesSessionKeywords(text, option.key)) return option.key;
    }
    return null;
  }

  bool _matchesSessionKeywords(String text, String sessionKey) {
    switch (sessionKey) {
      case 'general_checkup':
        return _containsAny(
          text,
          const ['general', 'checkup', 'check up', 'check-up', '常规', '检查', 'umum', 'pemeriksaan'],
        );
      case 'follow_up_consultation':
        return _containsAny(
          text,
          const ['follow up', 'follow-up', 'followup', 'susulan', '复诊', '后续'],
        );
      case 'urgent_consultation':
        return _containsAny(
          text,
          const ['urgent', 'emergency', '紧急', 'kecemasan', 'paling penting'],
        );
      case 'chronic_disease_review':
        return _containsAny(
          text,
          const ['chronic', 'disease', '慢性病', 'penyakit kronik'],
        );
      case 'medication_review':
        return _containsAny(
          text,
          const ['medication', 'medicine', 'drug', '药物', 'ubat', 'perubatan'],
        );
      case 'pre_operative_assessment':
        return _containsAny(
          text,
          const ['pre operative', 'pre-operative', 'preoperative', 'surgery', '手术前', 'pra operasi'],
        );
      case 'physical_therapy':
        return _containsAny(
          text,
          const ['physical therapy', 'physiotherapy', 'fisioterapi', '物理治疗'],
        );
      case 'occupational_therapy':
        return _containsAny(
          text,
          const ['occupational', '职业治疗', 'terapi pekerjaan'],
        );
      case 'rehabilitation':
        return _containsAny(
          text,
          const ['rehabilitation', 'rehab', '复健', 'pemulihan'],
        );
      case 'pain_management':
        return _containsAny(
          text,
          const ['pain management', 'pain', '疼痛', 'kesakitan'],
        );
      case 'speech_therapy':
        return _containsAny(
          text,
          const ['speech therapy', 'speech', '语言治疗', 'terapi pertuturan'],
        );
      case 'mental_health_counseling':
        return _containsAny(
          text,
          const ['mental health', 'counseling', 'counselling', '心理健康', 'kaunseling'],
        );
      default:
        return false;
    }
  }

  String? _parseRole(String? answer) {
    final raw = (answer ?? '').trim();
    if (raw.isEmpty) return null;

    final option = VoiceOptionParser.extractOptionNumber(raw, 2);
    if (option == 1) return 'doctor';
    if (option == 2) return 'therapist';

    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);
    if (text.isEmpty) return null;
    if (_containsAny(text, const ['doctor', 'physician', 'dr', '医生', 'doktor'])) return 'doctor';
    if (_containsAny(text, const ['therapist', 'therapy', '治疗师', 'terapis'])) return 'therapist';
    return null;
  }

  StaffOption? _parseStaffChoice(String? answer, List<StaffOption> options) {
    final raw = (answer ?? '').trim();
    if (raw.isEmpty) return null;

    final number = VoiceOptionParser.extractOptionNumber(raw, options.length);
    if (number != null) return options[number - 1];

    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);
    if (text.isEmpty) return null;

    for (final option in options) {
      final name = VoiceAssistantCoordinator.normalizeSpeech(option.name);
      if (name.isNotEmpty && text.contains(name)) return option;
    }
    return null;
  }

  DateTime? _parseDate(String? answer) {
    final text = VoiceAssistantCoordinator.normalizeSpeech(answer ?? '');
    if (text.isEmpty) return null;

    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    if (_containsAny(text, const ['today', '今天', 'hari ini'])) return todayOnly;
    if (_containsAny(text, const ['tomorrow', '明天', 'esok'])) {
      return todayOnly.add(const Duration(days: 1));
    }

    final iso = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})');
    final isoMatch = iso.firstMatch(text);
    if (isoMatch != null) {
      return DateTime(
        int.parse(isoMatch.group(1)!),
        int.parse(isoMatch.group(2)!),
        int.parse(isoMatch.group(3)!),
      );
    }

    final dmy = RegExp(r'(\d{1,2})\s+(\w+)\s+(\d{4})');
    final dmyMatch = dmy.firstMatch(text);
    if (dmyMatch != null) {
      final day = int.parse(dmyMatch.group(1)!);
      final month = _monthFromName(dmyMatch.group(2)!);
      final year = int.parse(dmyMatch.group(3)!);
      if (month != null) return DateTime(year, month, day);
    }

    if (_containsAny(text, const ['monday', '星期一', 'isnin'])) {
      return _nextWeekday(todayOnly, DateTime.monday);
    }
    if (_containsAny(text, const ['tuesday', '星期二', 'selasa'])) {
      return _nextWeekday(todayOnly, DateTime.tuesday);
    }
    if (_containsAny(text, const ['wednesday', '星期三', 'rabu'])) {
      return _nextWeekday(todayOnly, DateTime.wednesday);
    }
    if (_containsAny(text, const ['thursday', '星期四', 'khamis'])) {
      return _nextWeekday(todayOnly, DateTime.thursday);
    }
    if (_containsAny(text, const ['friday', '星期五', 'jumaat'])) {
      return _nextWeekday(todayOnly, DateTime.friday);
    }

    return null;
  }

  BookableSlot? _parseSlotChoice(String? answer, List<BookableSlot> slots) {
    final raw = (answer ?? '').trim();
    if (raw.isEmpty) return null;

    if (_wantsRepeatTimeSlots(answer)) return null;

    // 1. Explicit option phrases ("option 3", "number one") always win.
    final explicitOption =
        VoiceOptionParser.extractExplicitOptionNumber(raw, slots.length);
    if (explicitOption != null) return slots[explicitOption - 1];

    // 2. Clock times ("9 am", "9 pagi") — not bare option numbers.
    if (TemporalParser.looksLikeTimeExpression(raw)) {
      final fromTime = _parseSlotFromTimeSpeech(raw, slots);
      if (fromTime != null) return fromTime;
    }

    // 3. Bare option numbers ("1", "three", "9" as list index).
    final number = VoiceOptionParser.extractOptionNumber(
      raw,
      slots.length,
      skipIfTimeLike: true,
    );
    if (number != null) return slots[number - 1];

    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);
    if (text.isEmpty) return null;

    if (_containsAny(text, const ['first', 'earliest'])) return slots.first;

    for (final slot in slots) {
      final label = VoiceAssistantCoordinator.normalizeSpeech(
        AppointmentTimeSlots.formatTimeLabel(slot.dateTime),
      );
      if (label.isNotEmpty && text.contains(label.replaceAll(' ', ''))) {
        return slot;
      }
    }

    return null;
  }

  BookableSlot? _parseSlotFromTimeSpeech(String raw, List<BookableSlot> slots) {
    final parsed = TemporalParser.extractTime(raw);
    if (parsed == null) return null;

    final base = session.selectedDate ?? DateTime.now();
    final requested = DateTime(
      base.year,
      base.month,
      base.day,
      parsed.hour,
      parsed.minute ?? 0,
    );
    return _slotMatchingMinute(slots, requested);
  }

  BookableSlot? _slotMatchingMinute(List<BookableSlot> slots, DateTime requested) {
    for (final slot in slots) {
      if (AppointmentTimeSlots.sameMinute(slot.dateTime, requested)) {
        return slot;
      }
    }
    return null;
  }

  int? _monthFromName(String raw) {
    final month = raw.toLowerCase();
    const names = {
      'january': 1,
      'jan': 1,
      'february': 2,
      'feb': 2,
      'march': 3,
      'mar': 3,
      'april': 4,
      'apr': 4,
      'may': 5,
      'june': 6,
      'jun': 6,
      'july': 7,
      'jul': 7,
      'august': 8,
      'aug': 8,
      'september': 9,
      'sep': 9,
      'october': 10,
      'oct': 10,
      'november': 11,
      'nov': 11,
      'december': 12,
      'dec': 12,
    };
    return names[month];
  }

  DateTime _nextWeekday(DateTime from, int weekday) {
    var cursor = from;
    for (var i = 0; i < 14; i++) {
      if (cursor.weekday == weekday && !cursor.isBefore(from)) {
        return cursor;
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return from.add(const Duration(days: 7));
  }

  bool _containsAny(String text, List<String> phrases) {
    return phrases.any(text.contains);
  }
}

void openVoiceGuidedBookAppointmentPage(BookAppointmentSession session) {
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) return;
  navigator.push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'BookAppointmentPage'),
      builder: (context) => BookAppointmentPage(session: session),
    ),
  );
}
