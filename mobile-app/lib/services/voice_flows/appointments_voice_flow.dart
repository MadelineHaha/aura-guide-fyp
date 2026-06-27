import '../../models/appointment_item.dart';
import '../../utils/localized_date_format.dart';
import '../../utils/temporal_parser.dart';
import '../../utils/voice_option_parser.dart';
import '../app_settings_service.dart';
import '../appointments_service.dart';
import '../voice_assistant_coordinator.dart';
import '../voice_flow_coordinator.dart';

enum AppointmentsVoiceChoice { listen, past, book, back }

/// Voice-only appointments page: upcoming count, menu, details, and date/time lookup.
class AppointmentsVoiceFlow {
  AppointmentsVoiceFlow();

  final _service = AppointmentsService();
  final _assistant = VoiceAssistantCoordinator.instance;
  final _settings = AppSettingsService.instance;

  String _l10n(String key, [Map<String, Object?> params = const {}]) {
    return _settings.localized(key, params);
  }

  Future<void> run() async {
    if (!_settings.isVoiceConversationEnabled) return;

    _assistant.acquireMicLock();
    try {
      var promptKey = '';
      var params = <String, Object?>{};

      while (_isOnAppointmentsPage()) {
        final appointments = await _fetchAppointments();
        if (!_isOnAppointmentsPage()) return;

        final upcoming = _upcoming(appointments);
        if (promptKey.isEmpty) {
          promptKey = upcoming.isNotEmpty
              ? 'appointmentsVoiceGreeting'
              : 'appointmentsVoiceGreetingNoUpcoming';
          params = {'count': upcoming.length};
        }

        try {
          await _assistant.speakPrompt(promptKey, params: params);
          final answer = await _listenForPageCommand();
          if (!_isOnAppointmentsPage()) return;

          if (await _assistant.tryHandleGlobalNavigationCommand(answer)) {
            return;
          }

          if (_isAskDateOnlyQuery(answer)) {
            await _assistant.speakPrompt('appointmentsVoiceAskWhichDate');
            final dateAnswer = await _listenForPageCommand();
            await _handleLookup(dateAnswer, appointments);
            promptKey = 'appointmentsVoiceListComplete';
            params = {};
            continue;
          }

          if (TemporalParser.isAppointmentDateQuery(answer) &&
              TemporalParser.extractDate(answer) == null &&
              TemporalParser.extractTime(answer) == null) {
            await _assistant.speakPrompt('appointmentsVoiceAskWhichDate');
            final dateAnswer = await _listenForPageCommand();
            await _handleLookup(dateAnswer, appointments);
            promptKey = 'appointmentsVoiceListComplete';
            params = {};
            continue;
          }

          final choice = _parseChoice(answer, hasUpcoming: upcoming.isNotEmpty);
          if (choice != null) {
            switch (choice) {
              case AppointmentsVoiceChoice.listen:
                await _readAppointments(upcoming);
                break;
              case AppointmentsVoiceChoice.past:
                await _handlePast(appointments);
                break;
              case AppointmentsVoiceChoice.book:
                await VoiceFlowCoordinator.instance.startBookAppointmentFlow();
                return;
              case AppointmentsVoiceChoice.back:
                await _assistant.tryHandleGlobalNavigationCommand('go back');
                return;
            }
            promptKey = 'appointmentsVoiceListComplete';
            params = {};
            continue;
          }

          if (TemporalParser.speechMentionsDateOrTime(answer)) {
            await _handleLookup(answer, appointments);
            promptKey = 'appointmentsVoiceListComplete';
            params = {};
            continue;
          }

          await _assistant.speakPrompt('voiceCaptureInvalid');
        } on VoiceFlowNavigationException {
          return;
        }
      }
    } finally {
      _assistant.releaseMicLock();
      _assistant.resumeAfterVoiceFlow();
    }
  }

  Future<String> _listenForPageCommand() async {
    while (true) {
      final answer = await _assistant.listenForUtterance(
        listeningMessageKey: 'appointmentsVoiceListening',
      );
      if (answer != null && answer.trim().isNotEmpty) {
        return answer.trim();
      }
      await _assistant.speakPrompt('voiceCaptureNotHeard');
    }
  }

  bool _isAskDateOnlyQuery(String speech) {
    final lower = VoiceAssistantCoordinator.normalizeSpeech(speech);
    return lower.contains('say a date') ||
        lower.contains('what date') ||
        lower.contains('check date') ||
        speech.contains('什么日期') ||
        speech.contains('说日期');
  }

  Future<void> _readAppointments(List<AppointmentItem> appointments) async {
    if (appointments.isEmpty) {
      await _assistant.speakPrompt('appointmentsVoiceUpcomingNone');
      return;
    }

    final languageCode = _settings.settings.languageCode;
    for (final appt in appointments) {
      if (!_isOnAppointmentsPage()) return;
      await _assistant.speakText(
        _l10n('appointmentsVoiceDetail', _voiceParams(appt, languageCode)),
      );
    }
  }

  Future<void> _handlePast(List<AppointmentItem> all) async {
    final past = _past(all);
    if (past.isEmpty) {
      await _assistant.speakPrompt('appointmentsVoicePastNone');
      return;
    }

    try {
      await _assistant.speakPrompt(
        'appointmentsVoicePastPrompt',
        params: {'count': past.length},
      );
      final answer = await _listenForPageCommand();
      if (!_isOnAppointmentsPage()) return;

      if (await _assistant.tryHandleGlobalNavigationCommand(answer)) {
        throw const VoiceFlowNavigationException();
      }

      final normalized = VoiceAssistantCoordinator.normalizeSpeech(answer);
      if (_wantsReadAllPast(normalized)) {
        await _readAppointments(past);
        return;
      }

      if (TemporalParser.speechMentionsDateOrTime(answer)) {
        await _handleLookup(answer, past);
        return;
      }

      await _assistant.speakPrompt('voiceCaptureInvalid');
    } on VoiceFlowNavigationException {
      rethrow;
    }
  }

  Future<void> _handleLookup(
    String speech,
    List<AppointmentItem> scope,
  ) async {
    final matches = TemporalParser.findAppointments(speech, scope);
    if (matches.isEmpty) {
      final date = TemporalParser.extractDate(speech);
      if (date != null) {
        final languageCode = _settings.settings.languageCode;
        await _assistant.speakPrompt(
          'appointmentsVoiceNoneOnDate',
          params: {
            'date': LocalizedDateFormat.spokenDate(date, languageCode),
          },
        );
      } else {
        await _assistant.speakPrompt('appointmentsVoiceNotFound');
      }
      return;
    }

    final languageCode = _settings.settings.languageCode;
    for (final appt in matches) {
      if (!_isOnAppointmentsPage()) return;
      await _assistant.speakText(
        _l10n('appointmentsVoiceFound', _voiceParams(appt, languageCode)),
      );
    }
  }

  Map<String, Object?> _voiceParams(AppointmentItem appt, String languageCode) {
    return {
      'date': LocalizedDateFormat.spokenDate(appt.dateTime, languageCode),
      'time': appt.timeLabel,
      'clinic': appt.locationDisplay,
      'doctor': appt.doctorName,
      'type': appt.appointmentType,
    };
  }

  List<AppointmentItem> _upcoming(List<AppointmentItem> all) {
    return all.where((a) => !a.isPast && !a.isCancelled).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  List<AppointmentItem> _past(List<AppointmentItem> all) {
    return all.where((a) => a.isPast && !a.isCancelled).toList()
      ..sort((a, b) => b.dateTime.compareTo(a.dateTime));
  }

  AppointmentsVoiceChoice? _parseChoice(String? text, {required bool hasUpcoming}) {
    if (text == null) return null;

    final maxOptions = hasUpcoming ? 4 : 3;
    final option = VoiceOptionParser.extractOptionNumber(text, maxOptions);
    if (option != null) {
      if (hasUpcoming) {
        return switch (option) {
          1 => AppointmentsVoiceChoice.listen,
          2 => AppointmentsVoiceChoice.past,
          3 => AppointmentsVoiceChoice.book,
          4 => AppointmentsVoiceChoice.back,
          _ => null,
        };
      }
      return switch (option) {
        1 => AppointmentsVoiceChoice.past,
        2 => AppointmentsVoiceChoice.book,
        3 => AppointmentsVoiceChoice.back,
        _ => null,
      };
    }

    final lower = VoiceAssistantCoordinator.normalizeSpeech(text);

    if (lower.contains('listen') ||
        lower.contains('detail') ||
        lower.contains('upcoming') ||
        lower.contains('dengar') ||
        lower.contains('butiran') ||
        lower.contains('akan datang') ||
        lower.contains('听') ||
        lower.contains('详细') ||
        lower.contains('即将')) {
      return AppointmentsVoiceChoice.listen;
    }
    if (lower.contains('past') ||
        lower.contains('history') ||
        lower.contains('previous') ||
        lower.contains('lepas') ||
        lower.contains('lalu') ||
        lower.contains('过去') ||
        lower.contains('以前') ||
        lower.contains('历史')) {
      return AppointmentsVoiceChoice.past;
    }
    if (lower.contains('book') ||
        lower.contains('new appointment') ||
        lower.contains('make appointment') ||
        lower.contains('tempah') ||
        lower.contains('baru') ||
        lower.contains('预订') ||
        lower.contains('预约')) {
      return AppointmentsVoiceChoice.book;
    }
    if (lower.contains('back') ||
        lower.contains('kembali') ||
        lower.contains('返回') ||
        lower.contains('回去')) {
      return AppointmentsVoiceChoice.back;
    }

    return null;
  }

  bool _wantsReadAllPast(String normalized) {
    return normalized.contains('all') ||
        normalized.contains('read') ||
        normalized.contains('semua') ||
        normalized.contains('baca') ||
        normalized.contains('全部') ||
        normalized.contains('读') ||
        normalized == 'yes' ||
        normalized == 'ya' ||
        normalized == '是';
  }

  Future<List<AppointmentItem>> _fetchAppointments() async {
    try {
      return await _service.fetchForCurrentPatient();
    } catch (_) {
      return const [];
    }
  }

  bool _isOnAppointmentsPage() {
    final label = _assistant.topRouteLabel;
    return label != null && label.contains('AppointmentsPage');
  }
}
