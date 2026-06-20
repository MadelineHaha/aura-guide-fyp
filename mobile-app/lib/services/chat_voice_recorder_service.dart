import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class ChatVoiceRecording {
  const ChatVoiceRecording({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
    required this.durationSeconds,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileName;
  final int durationSeconds;
}

/// Short voice clips for chat messages.
class ChatVoiceRecorderService {
  ChatVoiceRecorderService({AudioRecorder? recorder})
      : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  String? _path;
  DateTime? _startedAt;

  Future<bool> get isRecording => _recorder.isRecording();

  Future<bool> start() async {
    if (await _recorder.isRecording()) return true;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) return false;

    final dir = await getTemporaryDirectory();
    _path =
        '${dir.path}/chat_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    _startedAt = DateTime.now();

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 64000,
        sampleRate: 44100,
      ),
      path: _path!,
    );
    return true;
  }

  Future<ChatVoiceRecording?> stop() async {
    final outputPath = await _recorder.stop();
    final path = outputPath ?? _path;
    final startedAt = _startedAt;
    _path = null;
    _startedAt = null;
    if (path == null || path.isEmpty) return null;

    final file = File(path);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    await file.delete();

    final durationSeconds = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inSeconds.clamp(0, 600);

    return ChatVoiceRecording(
      bytes: bytes,
      mimeType: 'audio/mp4',
      fileName: 'voice_message.m4a',
      durationSeconds: durationSeconds,
    );
  }

  Future<void> cancel() async {
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    final path = _path;
    _path = null;
    _startedAt = null;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  Future<void> dispose() async {
    await cancel();
    await _recorder.dispose();
  }
}
