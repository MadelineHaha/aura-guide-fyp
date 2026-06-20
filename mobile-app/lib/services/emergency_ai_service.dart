import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class EmergencyAIService {
  static final EmergencyAIService _instance =
  EmergencyAIService._internal();

  factory EmergencyAIService() => _instance;

  EmergencyAIService._internal();

  Interpreter? _interpreter;
  List<String> _vocabulary = [];

  Future<void> initialize() async {
    _interpreter ??=
    await Interpreter.fromAsset(
      'assets/ai/emergency_model.tflite',
    );

    final vocabText =
    await rootBundle.loadString(
      'assets/ai/vocabulary.txt',
    );

    _vocabulary =
        const LineSplitter().convert(vocabText);

    print(
      "Emergency AI Loaded. Vocabulary size: "
          "${_vocabulary.length}",
    );
  }

  Future<String> classify(
      String text,
      ) async {
    if (_interpreter == null) {
      await initialize();
    }

    final vector =
    _textToVector(text);

    final output = [
      [0.0]
    ];

    _interpreter!.run(
      [vector],
      output,
    );

    final score =
    output[0][0];

    print(
      "Emergency Score: $score",
    );

    return score > 0.5
        ? "EMERGENCY"
        : "SAFE";
  }

  List<double> _textToVector(
      String text,
      ) {
    final vector = List<double>.filled(
      _vocabulary.length,
      0,
    );

    final words = text
        .toLowerCase()
        .split(RegExp(r'\s+'));

    for (final word in words) {
      final index =
      _vocabulary.indexOf(word);

      if (index >= 0 &&
          index < vector.length) {
        vector[index] += 1.0;
      }
    }

    return vector;
  }
}