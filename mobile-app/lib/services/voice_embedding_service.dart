import 'dart:math';
import 'dart:typed_data';

/// Extracts compact voiceprint vectors from recorded speech audio.
class VoiceEmbeddingService {
  VoiceEmbeddingService._();

  static final VoiceEmbeddingService instance = VoiceEmbeddingService._();

  static const int embeddingSize = 64;
  static const double matchThreshold = 0.72;

  List<double> extractFromWav(Uint8List wavBytes) {
    final decoded = _decodeWav(wavBytes);
    if (decoded == null || decoded.samples.isEmpty) {
      return List<double>.filled(embeddingSize, 0);
    }
    return _extractEmbedding(decoded.samples, decoded.sampleRate);
  }

  Map<String, dynamic> buildFeatures({
    required List<double> vector,
    required int sampleRate,
    required int durationMs,
  }) {
    final energy = vector.isEmpty
        ? 0.0
        : vector.map((v) => v * v).reduce((a, b) => a + b) / vector.length;
    return {
      'sampleRate': sampleRate,
      'durationMs': durationMs,
      'vectorSize': vector.length,
      'energyMean': energy,
      'embeddingVersion': 1,
    };
  }

  double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0;

    var dot = 0.0;
    var normA = 0.0;
    var normB = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  bool matches(List<double> enrolled, List<double> probe) {
    if (!isUsableVoiceprint(enrolled) || !isUsableVoiceprint(probe)) {
      return false;
    }
    return cosineSimilarity(enrolled, probe) >= matchThreshold;
  }

  static bool isUsableVoiceprint(List<double> vector) {
    return vector.isNotEmpty && vector.any((value) => value != 0);
  }

  List<double> _extractEmbedding(List<double> samples, int sampleRate) {
    const frameSize = 400;
    const hop = 160;
    final frames = <List<double>>[];

    for (var start = 0;
        start + frameSize <= samples.length;
        start += hop) {
      frames.add(samples.sublist(start, start + frameSize));
    }

    if (frames.isEmpty) {
      return List<double>.filled(embeddingSize, 0);
    }

    final vector = <double>[];
    final bandCount = 16;

    for (final frame in frames) {
      vector.add(_rms(frame));
      vector.add(_zeroCrossingRate(frame));
      vector.addAll(_spectralBands(frame, bandCount));
    }

    final pooled = List<double>.filled(embeddingSize, 0);
    if (vector.isEmpty) return pooled;

    final chunk = max(1, vector.length ~/ embeddingSize);
    for (var i = 0; i < embeddingSize; i++) {
      final start = i * chunk;
      final end = min(start + chunk, vector.length);
      if (start >= end) continue;
      var sum = 0.0;
      for (var j = start; j < end; j++) {
        sum += vector[j];
      }
      pooled[i] = sum / (end - start);
    }

    return _normalize(pooled);
  }

  List<double> _normalize(List<double> input) {
    var norm = 0.0;
    for (final value in input) {
      norm += value * value;
    }
    norm = sqrt(norm);
    if (norm == 0) return input;
    return input.map((value) => value / norm).toList();
  }

  double _rms(List<double> frame) {
    if (frame.isEmpty) return 0;
    var sum = 0.0;
    for (final sample in frame) {
      sum += sample * sample;
    }
    return sqrt(sum / frame.length);
  }

  double _zeroCrossingRate(List<double> frame) {
    if (frame.length < 2) return 0;
    var crossings = 0;
    for (var i = 1; i < frame.length; i++) {
      if ((frame[i - 1] >= 0 && frame[i] < 0) ||
          (frame[i - 1] < 0 && frame[i] >= 0)) {
        crossings++;
      }
    }
    return crossings / frame.length;
  }

  List<double> _spectralBands(List<double> frame, int bands) {
    final result = List<double>.filled(bands, 0);
    final size = frame.length;
    for (var k = 1; k <= bands; k++) {
      var real = 0.0;
      var imag = 0.0;
      for (var n = 0; n < size; n++) {
        final angle = 2 * pi * k * n / size;
        real += frame[n] * cos(angle);
        imag -= frame[n] * sin(angle);
      }
      result[k - 1] = sqrt(real * real + imag * imag);
    }
    return result;
  }

  _DecodedWav? _decodeWav(Uint8List bytes) {
    if (bytes.length < 44) return null;
    if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF') return null;
    if (String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') return null;

    var offset = 12;
    var sampleRate = 16000;
    Uint8List? data;

    while (offset + 8 <= bytes.length) {
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final chunkSize = ByteData.sublistView(bytes, offset + 4, offset + 8)
          .getUint32(0, Endian.little);
      final chunkStart = offset + 8;

      if (chunkId == 'fmt ' && chunkStart + 16 <= bytes.length) {
        sampleRate = ByteData.sublistView(bytes, chunkStart + 4, chunkStart + 8)
            .getUint32(0, Endian.little);
      } else if (chunkId == 'data') {
        final end = min(chunkStart + chunkSize, bytes.length);
        data = bytes.sublist(chunkStart, end);
      }

      offset = chunkStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (data == null || data.isEmpty) return null;

    final samples = <double>[];
    for (var i = 0; i + 1 < data.length; i += 2) {
      final sample =
          ByteData.sublistView(data, i, i + 2).getInt16(0, Endian.little);
      samples.add(sample / 32768.0);
    }

    return _DecodedWav(samples: samples, sampleRate: sampleRate);
  }
}

class _DecodedWav {
  const _DecodedWav({required this.samples, required this.sampleRate});

  final List<double> samples;
  final int sampleRate;
}
