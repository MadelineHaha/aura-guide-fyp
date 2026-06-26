import 'package:flutter/material.dart';

import '../../app_navigator.dart';
import '../../book_appointment_page.dart';
import '../../models/book_appointment_session.dart';
import '../../models/bookable_slot.dart';
import '../../models/staff_option.dart';
import '../../utils/appointment_time_slots.dart';
import '../app_settings_service.dart';
import '../voice_assistant_coordinator.dart';

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
      await session.selectSession(await _askSessionType());
      await session.selectRole(await _askRole());
      await session.selectStaff(await _askStaff());
      final date = await _askDate();
      await session.selectDate(date);
      session.selectSlot(await _askSlot());
      final confirmed = await _assistant.confirmPrompt(
        'voiceFlowBookConfirm',
        params: {
          'type': session.sessionTitleForKey(
            session.sessionKey ?? 'general',
            _l10n,
          ),
          'staff': session.selectedStaff?.displayName ?? '',
          'date': _formatDate(session.selectedDate!),
          'time': AppointmentTimeSlots.formatTimeLabel(
            session.selectedSlot!.dateTime,
          ),
        },
      );
      if (!confirmed) {
        await _assistant.speakPrompt('voiceFlowBookingCancelled');
        return;
      }

      final success = await session.submitBooking(
        session.sessionTitleForKey(session.sessionKey ?? 'general', _l10n),
      );
      if (success) {
        await _assistant.speakPrompt('voiceFlowBookingSuccess');
        rootNavigatorKey.currentState?.pop(true);
      } else {
        await _assistant.speakPrompt('voiceFlowBookingFailed');
      }
    } on VoiceFlowCancelledException {
      await _assistant.speakPrompt('voiceFlowBookingCancelled');
      rootNavigatorKey.currentState?.pop();
    }
  }

  Future<String> _askSessionType() async {
    String promptKey = 'voiceFlowAskSessionType';
    while (true) {
      final answer = await _assistant.promptAndListen(promptKey);
      final parsed = _parseSessionType(answer);
      if (parsed != null) return parsed;
      promptKey = 'voiceFlowSessionTypeRetry';
    }
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
    String promptKey = 'voiceFlowAskTime';
    while (true) {
      if (session.loadingSlots) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        continue;
      }
      if (session.availableSlots.isEmpty) {
        await _assistant.speakPrompt('voiceFlowNoSlots');
        final retryDate = await _askDate();
        await session.selectDate(retryDate);
        promptKey = 'voiceFlowAskTime';
        continue;
      }

      final labels = session.availableSlots
          .map((slot) => AppointmentTimeSlots.formatTimeLabel(slot.dateTime))
          .toList();
      final answer = await _assistant.promptAndListen(
        promptKey,
        params: {'options': _numberedList(labels)},
      );
      final picked = _parseSlotChoice(answer, session.availableSlots);
      if (picked != null) return picked;
      promptKey = 'voiceFlowTimeRetry';
    }
  }

  String _numberedList(List<String> items) {
    return items.asMap().entries.map((entry) {
      return '${entry.key + 1}. ${entry.value}';
    }).join('. ');
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  String? _parseSessionType(String? answer) {
    final text = VoiceAssistantCoordinator.normalizeSpeech(answer ?? '');
    if (text.isEmpty) return null;
    if (_containsAny(text, const ['urgent', 'emergency', '紧急', 'kecemasan', 'paling penting'])) return 'urgent';
    if (_containsAny(text, const ['therapist', 'therapy', 'rehab', '治疗', '复健', 'terapi', 'pemulihan'])) {
      return 'therapist_session';
    }
    if (_containsAny(text, const ['general', 'checkup', 'check up', 'check-up', '常规', '检查', 'umum', 'pemeriksaan'])) {
      return 'general';
    }
    if (text.contains('1') || text.contains('first') || text.contains('一') || text.contains('satu')) return 'general';
    if (text.contains('2') || text.contains('second') || text.contains('二') || text.contains('dua')) return 'therapist_session';
    if (text.contains('3') || text.contains('third') || text.contains('三') || text.contains('tiga')) return 'urgent';
    return null;
  }

  String? _parseRole(String? answer) {
    final text = VoiceAssistantCoordinator.normalizeSpeech(answer ?? '');
    if (text.isEmpty) return null;
    if (_containsAny(text, const ['doctor', 'physician', 'dr', '医生', 'doktor'])) return 'doctor';
    if (_containsAny(text, const ['therapist', 'therapy', '治疗师', 'terapis'])) return 'therapist';
    return null;
  }

  StaffOption? _parseStaffChoice(String? answer, List<StaffOption> options) {
    final text = VoiceAssistantCoordinator.normalizeSpeech(answer ?? '');
    if (text.isEmpty) return null;

    final number = _extractOptionNumber(text);
    if (number != null && number >= 1 && number <= options.length) {
      return options[number - 1];
    }

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
    final text = VoiceAssistantCoordinator.normalizeSpeech(answer ?? '');
    if (text.isEmpty) return null;

    final number = _extractOptionNumber(text);
    if (number != null && number >= 1 && number <= slots.length) {
      return slots[number - 1];
    }

    if (_containsAny(text, const ['first', 'earliest'])) return slots.first;

    for (final slot in slots) {
      final label = VoiceAssistantCoordinator.normalizeSpeech(
        AppointmentTimeSlots.formatTimeLabel(slot.dateTime),
      );
      if (label.isNotEmpty && text.contains(label.replaceAll(' ', ''))) {
        return slot;
      }
      final hourMatch = RegExp(r'(\d{1,2})').firstMatch(text);
      if (hourMatch != null && slot.dateTime.hour == int.parse(hourMatch.group(1)!)) {
        return slot;
      }
    }
    return null;
  }

  int? _extractOptionNumber(String text) {
    final words = {
      'one': 1,
      'first': 1,
      'two': 2,
      'second': 2,
      'three': 3,
      'third': 3,
      'four': 4,
      'fourth': 4,
      'five': 5,
      'fifth': 5,
    };
    for (final entry in words.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    final digit = RegExp(r'\b(\d+)\b').firstMatch(text);
    if (digit != null) return int.tryParse(digit.group(1)!);
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
