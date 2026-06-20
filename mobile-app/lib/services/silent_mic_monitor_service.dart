import 'dart:async';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Monitors microphone levels without using [SpeechRecognizer], so Android
/// does not play the start/stop recognition beep while waiting for speech.
class SilentMicMonitorService {
  SilentMicMonitorService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  StreamSubscription<Amplitude>? _amplitudeSub;
  bool _running = false;
  int _hotFrames = 0;
  DateTime? _cooldownUntil;

  static const _thresholdDb = -48.0;
  static const _requiredHotFrames = 1;
  static const _checkInterval = Duration(milliseconds: 120);
  static const _cooldownAfterTrigger = Duration(milliseconds: 300);

  bool get isRunning => _running;

  Future<void> start(void Function() onVoiceActivity) async {
    if (_running) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return;

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/silent_wake_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );

    _running = true;
    _hotFrames = 0;
    _cooldownUntil = null;

    _amplitudeSub = _recorder
        .onAmplitudeChanged(_checkInterval)
        .listen((amplitude) {
      final now = DateTime.now();
      if (_cooldownUntil != null && now.isBefore(_cooldownUntil!)) {
        return;
      }

      if (amplitude.current > _thresholdDb) {
        _hotFrames++;
        if (_hotFrames >= _requiredHotFrames) {
          _hotFrames = 0;
          _cooldownUntil = now.add(_cooldownAfterTrigger);
          onVoiceActivity();
        }
        return;
      }

      _hotFrames = 0;
    });
  }

  Future<void> stop() async {
    await _amplitudeSub?.cancel();
    _amplitudeSub = null;
    _hotFrames = 0;
    _cooldownUntil = null;

    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    _running = false;
  }

  Future<void> dispose() async {
    await stop();
    await _recorder.dispose();
  }
}
