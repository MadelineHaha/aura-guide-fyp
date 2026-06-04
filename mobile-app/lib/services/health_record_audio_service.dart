import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/health_record_item.dart';

/// Reads health record text aloud (Firestore stores text/PDF, not audio files).
class HealthRecordAudioService {
  HealthRecordAudioService() : _tts = FlutterTts();

  final FlutterTts _tts;
  bool _ready = false;
  String? playingRecordId;

  static const _pluginRestartHint =
      'Stop the app completely, then run "flutter run" again (not hot reload) '
      'so audio can load.';

  Future<void> ensureReady() async {
    if (_ready) return;
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      try {
        await _tts.setLanguage('en-US');
      } catch (_) {
        // Device default language is fine if en-US is unavailable.
      }
      _ready = true;
    } on MissingPluginException {
      throw StateError(_pluginRestartHint);
    } on PlatformException catch (e) {
      if (e.code == 'MissingPluginException' ||
          '${e.message}'.contains('MissingPlugin')) {
        throw StateError(_pluginRestartHint);
      }
      rethrow;
    }
  }

  static String narrationFor(HealthRecordItem record) {
    return '${record.recordType}. '
        'Date ${record.dateCreated}. '
        '${record.doctorName}. '
        '${record.summary}';
  }

  Future<void> play(HealthRecordItem record) async {
    await ensureReady();
    await _tts.stop();
    playingRecordId = record.recordId;
    await _tts.speak(narrationFor(record));
    playingRecordId = null;
  }

  Future<void> stop() async {
    await _tts.stop();
    playingRecordId = null;
  }

  Future<void> dispose() async {
    await stop();
    await _tts.stop();
  }
}
