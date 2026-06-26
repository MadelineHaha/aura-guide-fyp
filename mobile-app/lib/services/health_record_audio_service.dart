import '../models/health_record_item.dart';
import 'app_settings_service.dart';

/// Reads health record text aloud using the app text-to-speech engine.
class HealthRecordAudioService {
  String? playingRecordId;

  static String narrationFor(HealthRecordItem record) {
    final summary = record.summary.trim();
    final safeSummary = summary.isEmpty || summary == '—' ? '' : summary;

    return AppSettingsService.instance.localized(
      'healthRecordNarration',
      {
        'recordType': record.recordType,
        'dateCreated': record.dateCreated,
        'doctorName': record.doctorName,
        'summary': safeSummary,
      },
    ).trim();
  }

  Future<void> play(HealthRecordItem record) async {
    final text = narrationFor(record);
    if (text.isEmpty) return;

    playingRecordId = record.recordId;
    try {
      await AppSettingsService.instance.stopSpeaking();
      await AppSettingsService.instance.speakAndAwaitCompletion(text);
    } finally {
      if (playingRecordId == record.recordId) {
        playingRecordId = null;
      }
    }
  }

  Future<void> stop() async {
    await AppSettingsService.instance.stopSpeaking();
    playingRecordId = null;
  }

  Future<void> dispose() async {
    await stop();
  }
}
