import '../../models/health_record_item.dart';
import '../app_settings_service.dart';
import '../health_records_service.dart';
import '../voice_assistant_coordinator.dart';

/// Voice-only health records page: today's upload count, then today vs other list.
class HealthRecordsVoiceFlow {
  HealthRecordsVoiceFlow();

  final _service = HealthRecordsService();
  final _assistant = VoiceAssistantCoordinator.instance;
  final _settings = AppSettingsService.instance;

  String _l10n(String key, [Map<String, Object?> params = const {}]) {
    return _settings.localized(key, params);
  }

  Future<void> run() async {
    if (!_settings.isVoiceConversationEnabled) return;

    _assistant.acquireMicLock();
    try {
      while (_isOnHealthRecordsPage()) {
        final records = await _fetchRecords();
        if (!_isOnHealthRecordsPage()) return;

        if (records.isEmpty) {
          await _handleEmptyRecords();
          return;
        }

        await _assistant.speakText(
          HealthRecordsService.buildVoiceIntro(records, _l10n),
        );

        try {
          final choice = await _listenForHealthRecordChoice();
          if (choice == null || !_isOnHealthRecordsPage()) return;

          final languageCode = _settings.settings.languageCode;
          final selected = switch (choice) {
            HealthRecordsVoiceChoice.today =>
              HealthRecordsService.recordsUploadedToday(records),
            HealthRecordsVoiceChoice.other =>
              HealthRecordsService.recordsUploadedBeforeToday(records),
          };

          if (selected.isEmpty) {
            await _assistant.speakPrompt(
              choice == HealthRecordsVoiceChoice.today
                  ? 'voiceHealthRecordsNoneToday'
                  : 'voiceHealthRecordsNoneOther',
            );
          } else {
            await _assistant.speakText(
              HealthRecordsService.buildRecordsListSpeech(
                selected,
                _l10n,
                languageCode,
              ),
            );
          }

          await _assistant.speakPrompt('voiceHealthRecordsAfterListPrompt');
        } on VoiceFlowNavigationException {
          return;
        }
      }
    } finally {
      _assistant.releaseMicLock();
      _assistant.resumeAfterVoiceFlow();
    }
  }

  Future<void> _handleEmptyRecords() async {
    await _assistant.speakText(_l10n('voiceHealthRecordsEmpty'));
    while (_isOnHealthRecordsPage()) {
      final heard = await _assistant.listenForUtterance(
        listeningMessageKey: 'voiceHealthRecordsListening',
      );
      if (!_isOnHealthRecordsPage()) return;
      if (heard == null || heard.trim().isEmpty) {
        await _speakNotCapturedThenHealthOptions();
        continue;
      }
      if (await _assistant.tryHandleGlobalNavigationCommand(heard)) return;

      await _assistant.speakPrompt('voiceCaptureInvalid');
      await _assistant.speakPrompt('voiceHealthRecordsChoiceRetry');
    }
  }

  Future<HealthRecordsVoiceChoice?> _listenForHealthRecordChoice() async {
    while (_isOnHealthRecordsPage()) {
      final heard = await _assistant.listenForUtterance(
        listeningMessageKey: 'voiceHealthRecordsListening',
      );
      if (!_isOnHealthRecordsPage()) return null;
      if (heard == null || heard.trim().isEmpty) {
        await _speakNotCapturedThenHealthOptions();
        continue;
      }

      if (await _assistant.tryHandleGlobalNavigationCommand(heard)) {
        return null;
      }

      final choice = HealthRecordsService.parseVoiceChoice(heard);
      if (choice != null) return choice;

      await _assistant.speakPrompt('voiceCaptureInvalid');
      await _assistant.speakPrompt('voiceHealthRecordsChoiceRetry');
    }
    return null;
  }

  Future<void> _speakNotCapturedThenHealthOptions() async {
    await _assistant.speakPrompt('voiceCaptureNotHeard');
    await _assistant.speakPrompt('voiceHealthRecordsChoiceRetry');
  }

  Future<List<HealthRecordItem>> _fetchRecords() async {
    try {
      return await _service.fetchForCurrentPatient();
    } catch (_) {
      return const [];
    }
  }

  bool _isOnHealthRecordsPage() {
    final label = _assistant.topRouteLabel;
    return label != null && label.contains('HealthRecordsPage');
  }
}
