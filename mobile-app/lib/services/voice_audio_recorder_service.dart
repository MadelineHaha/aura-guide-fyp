import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Records raw speech audio in parallel with speech-to-text.
class VoiceAudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  Future<void> start() async {
    if (await _recorder.isRecording()) return;

    final dir = await getTemporaryDirectory();
    _path =
        '${dir.path}/voice_capture_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _path!,
    );
  }

  Future<Uint8List?> stop() async {
    final outputPath = await _recorder.stop();
    final path = outputPath ?? _path;
    _path = null;
    if (path == null || path.isEmpty) return null;

    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<void> dispose() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    await _recorder.dispose();
  }
}
