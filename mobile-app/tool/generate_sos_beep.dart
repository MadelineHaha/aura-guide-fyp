import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

Uint8List buildAlertTone() {
  const sampleRate = 44100;
  const durationSeconds = 0.55;
  const frequency = 988.0;
  final sampleCount = (sampleRate * durationSeconds).floor();
  final data = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    final progress = i / sampleCount;
    final attack = progress < 0.05 ? progress / 0.05 : 1.0;
    final decay = math.pow(1.0 - progress, 0.85).toDouble();
    final envelope = attack * decay;
    final sample =
        math.sin(2 * math.pi * frequency * (i / sampleRate)) * envelope;
    final pcm = (sample * 32767).round().clamp(-32768, 32767);
    data.setInt16(i * 2, pcm, Endian.little);
  }
  final header = ByteData(44);
  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      header.setUint8(offset + i, value.codeUnitAt(i));
    }
  }
  writeAscii(0, 'RIFF');
  header.setUint32(4, 36 + data.lengthInBytes, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little);
  header.setUint16(22, 1, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  header.setUint32(40, data.lengthInBytes, Endian.little);
  final bytes = Uint8List(44 + data.lengthInBytes);
  bytes.setRange(0, 44, header.buffer.asUint8List());
  bytes.setRange(44, bytes.length, data.buffer.asUint8List());
  return bytes;
}

void main() {
  final file = File('assets/sounds/sos_beep.wav');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(buildAlertTone());
  stdout.writeln('Wrote ${file.path} (${file.lengthSync()} bytes)');
}
