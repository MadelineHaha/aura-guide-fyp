import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Result from the on-device emergency text model.
class EmergencyAnalysisResult {
  const EmergencyAnalysisResult({
    required this.label,
    required this.score,
    required this.source,
  });

  final String label;
  final double score;
  final String source;

  bool get isEmergency => label == 'EMERGENCY';

  static const safe = 'SAFE';
  static const emergency = 'EMERGENCY';
}

/// Classifies spoken text with the trained emergency TFLite model (offline).
class EmergencyAIService {
  static final EmergencyAIService _instance = EmergencyAIService._internal();

  factory EmergencyAIService() => _instance;

  EmergencyAIService._internal();

  Interpreter? _interpreter;
  List<String> _vocabulary = const [];
  List<double> _idfWeights = const [];
  bool _ready = false;

  static const _modelAsset = 'assets/ai/emergency_model.tflite';
  static const _vocabAsset = 'assets/ai/vocabulary.txt';
  static const _idfAsset = 'assets/ai/idf_weights.json';
  static const _threshold = 0.5;

  static const _dangerKeywords = [
    'help',
    'ambulance',
    'pain',
    'hurt',
    'injured',
    'bleeding',
    'dizzy',
    'faint',
    'breathe',
    'tolong',
    'ambulans',
    'cedera',
    'sakit',
    'pening',
    'pengsan',
    '救命',
    '头晕',
    '晕',
    '受伤',
    '疼',
    '痛',
    'emergency',
    'kecemasan',
  ];

  static const _safePhrases = [
    'im fine',
    'i am fine',
    'im okay',
    'i am okay',
    'no emergency',
    'no problem',
    'dont need help',
    "don't need help",
    'everything is fine',
    'everything is okay',
    'saya okay',
    'saya baik',
    'tidak perlu bantuan',
    '我没事',
    '没有问题',
  ];

  Future<void> initialize() async {
    if (_ready) return;

    try {
      _interpreter ??= await Interpreter.fromAsset(_modelAsset);

      final vocabText = await rootBundle.loadString(_vocabAsset);
      _vocabulary = vocabText
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      final idfJson = await rootBundle.loadString(_idfAsset);
      final decoded = jsonDecode(idfJson);
      if (decoded is List) {
        _idfWeights = decoded
            .map((value) => (value as num).toDouble())
            .toList(growable: false);
      }

      _ready =
          _interpreter != null &&
          _vocabulary.isNotEmpty &&
          _idfWeights.length == _vocabulary.length;

      if (kDebugMode) {
        debugPrint(
          'EmergencyAIService ready=$_ready vocab=${_vocabulary.length}',
        );
      }
    } catch (error, stack) {
      _ready = false;
      debugPrint('EmergencyAIService initialize failed: $error\n$stack');
    }
  }

  Future<EmergencyAnalysisResult> analyze(String text) async {
    final normalized = _normalize(text);
    if (normalized.isEmpty) {
      return const EmergencyAnalysisResult(
        label: EmergencyAnalysisResult.safe,
        score: 0,
        source: 'empty',
      );
    }

    final keyword = _keywordResult(normalized);
    if (keyword != null) return keyword;

    if (!_ready) {
      await initialize();
    }
    if (!_ready || _interpreter == null) {
      return EmergencyAnalysisResult(
        label: EmergencyAnalysisResult.safe,
        score: 0,
        source: 'model_unavailable',
      );
    }

    final vector = _buildTfidfVector(normalized);
    final output = List.generate(1, (_) => List<double>.filled(1, 0));
    _interpreter!.run([vector], output);
    final score = output[0][0];
    final label = score > _threshold
        ? EmergencyAnalysisResult.emergency
        : EmergencyAnalysisResult.safe;

    if (kDebugMode) {
      debugPrint(
        'EmergencyAIService "$normalized" -> $label (${score.toStringAsFixed(3)})',
      );
    }

    return EmergencyAnalysisResult(
      label: label,
      score: score,
      source: 'tflite',
    );
  }

  /// Backwards-compatible API used by SOS and fall detection.
  Future<String> classify(String text) async {
    final result = await analyze(text);
    return result.label;
  }

  EmergencyAnalysisResult? _keywordResult(String normalized) {
    for (final phrase in _safePhrases) {
      if (normalized.contains(phrase)) {
        return const EmergencyAnalysisResult(
          label: EmergencyAnalysisResult.safe,
          score: 0,
          source: 'safe_phrase',
        );
      }
    }

    for (final word in _dangerKeywords) {
      if (RegExp('\\b${RegExp.escape(word)}\\b').hasMatch(normalized)) {
        return const EmergencyAnalysisResult(
          label: EmergencyAnalysisResult.emergency,
          score: 1,
          source: 'keyword',
        );
      }
    }

    return null;
  }

  String _normalize(String raw) {
    return raw
        .toLowerCase()
        .replaceAll("'", '')
        .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fff\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<double> _buildTfidfVector(String normalized) {
    final counts = <String, int>{};
    for (final token in normalized.split(' ')) {
      if (token.isEmpty) continue;
      counts[token] = (counts[token] ?? 0) + 1;
    }

    final vector = List<double>.filled(_vocabulary.length, 0);
    counts.forEach((token, count) {
      final index = _vocabulary.indexOf(token);
      if (index < 0 || index >= _idfWeights.length) return;
      vector[index] = count * _idfWeights[index];
    });
    return vector;
  }
}
