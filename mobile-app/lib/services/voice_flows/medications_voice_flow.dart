import '../../models/medication_item.dart';
import '../app_settings_service.dart';
import '../medications_service.dart';
import '../voice_assistant_coordinator.dart';

/// Voice-only medications page: read today's progress and doses, then accept
/// mark taken / not taken commands.
class MedicationsVoiceFlow {
  MedicationsVoiceFlow();

  final _service = MedicationsService();
  final _assistant = VoiceAssistantCoordinator.instance;
  final _settings = AppSettingsService.instance;

  String _l10n(String key, [Map<String, Object?> params = const {}]) {
    return _settings.localized(key, params);
  }

  Future<void> run() async {
    if (!_settings.isVoiceConversationEnabled) return;

    _assistant.acquireMicLock();
    try {
      await _speakCurrentSummary();

      while (_isOnMedicationsPage()) {
        try {
          final heard = await _assistant.listenForUtterance(
            listeningMessageKey: 'voiceMedicationsListening',
          );
          if (!_isOnMedicationsPage()) return;
          if (heard == null || heard.trim().isEmpty) {
            await _assistant.speakPrompt('voiceMedicationsListenPrompt');
            continue;
          }

          if (await _assistant.tryHandleGlobalNavigationCommand(heard)) {
            return;
          }

          final items = await _fetchItems();
          final action = MedicationsService.parseVoiceAction(heard, items);
          if (action == null) {
            await _assistant.speakPrompt('voiceMedicationsCommandNotRecognized');
            await _assistant.speakPrompt('voiceMedicationsListenPrompt');
            continue;
          }

          try {
            await _service.setTakenToday(
              reminderId: action.item.reminderId,
              taken: action.taken,
            );
          } catch (error) {
            await _assistant.speakPrompt(
              'voiceMedicationsUpdateFailed',
              params: {'error': error.toString()},
            );
            continue;
          }

          await _assistant.speakText(
            _l10n(
              action.taken
                  ? 'voiceMedicationsMarkedTaken'
                  : 'voiceMedicationsMarkedNotTaken',
              {
                'name': action.item.name,
                'time': action.item.scheduledTime,
              },
            ),
          );
          await _speakCurrentSummary();
        } on VoiceFlowNavigationException {
          return;
        }
      }
    } finally {
      _assistant.releaseMicLock();
      _assistant.resumeAfterVoiceFlow();
    }
  }

  Future<void> _speakCurrentSummary() async {
    final items = await _fetchItems();
    await _assistant.speakText(
      MedicationsService.buildVoiceSummary(items, _l10n),
    );
  }

  Future<List<MedicationItem>> _fetchItems() async {
    try {
      return await _service.fetchTodayForCurrentPatient();
    } catch (_) {
      return const [];
    }
  }

  bool _isOnMedicationsPage() {
    final label = _assistant.topRouteLabel;
    return label != null && label.contains('MedicationsPage');
  }
}
