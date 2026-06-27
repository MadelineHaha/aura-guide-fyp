import '../services/voice_assistant_coordinator.dart';
import 'temporal_parser.dart';

/// Shared spoken menu option parsing for voice flows across the app.
class VoiceOptionParser {
  VoiceOptionParser._();

  static const _chineseDigits = <String, int>{
    '第一': 1,
    '第二': 2,
    '第三': 3,
    '第四': 4,
    '第五': 5,
    '第六': 6,
    '第七': 7,
    '第八': 8,
    '第九': 9,
    '第十': 10,
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '七': 7,
    '八': 8,
    '九': 9,
    '十': 10,
  };

  static const _wordNumbers = <String, int>{
    'one': 1,
    'first': 1,
    'satu': 1,
    'two': 2,
    'second': 2,
    'dua': 2,
    'three': 3,
    'third': 3,
    'tiga': 3,
    'four': 4,
    'fourth': 4,
    'empat': 4,
    'five': 5,
    'fifth': 5,
    'lima': 5,
    'six': 6,
    'sixth': 6,
    'enam': 6,
    'seven': 7,
    'seventh': 7,
    'tujuh': 7,
    'eight': 8,
    'eighth': 8,
    'lapan': 8,
    'nine': 9,
    'ninth': 9,
    'sembilan': 9,
    'ten': 10,
    'tenth': 10,
    'sepuluh': 10,
  };

  static String normalize(String raw) =>
      VoiceAssistantCoordinator.normalizeSpeech(raw);

  /// Formats a spoken numbered list: "1. Foo. 2. Bar."
  static String formatNumberedList(List<String> items) {
    return items.asMap().entries.map((entry) {
      return '${entry.key + 1}. ${entry.value}';
    }).join('. ');
  }

  /// Returns the list item at the spoken option index, or null.
  static T? selectByOptionIndex<T>(
    List<T> items,
    String? speech, {
    bool skipIfTimeLike = false,
  }) {
    final index = extractOptionNumber(
      speech ?? '',
      items.length,
      skipIfTimeLike: skipIfTimeLike,
    );
    if (index == null) return null;
    return items[index - 1];
  }

  /// Explicit option phrases such as "option 3", "number one", "nombor 2".
  static int? extractExplicitOptionNumber(String raw, int maxOptions) {
    if (maxOptions < 1) return null;
    final text = normalize(raw);

    final labeledDigit = RegExp(
      r'(?:option|number|choice|nombor|pilihan|#|no|num)\s*(\d+)\b',
    ).firstMatch(text);
    if (labeledDigit != null) {
      final value = int.tryParse(labeledDigit.group(1)!);
      if (value != null && value >= 1 && value <= maxOptions) return value;
    }

    for (final entry in _wordNumbers.entries) {
      if (entry.value > maxOptions) continue;
      final pattern = RegExp(
        '(?:option|number|choice|nombor|pilihan)\\s+${RegExp.escape(entry.key)}\\b',
      );
      if (pattern.hasMatch(text)) return entry.value;
    }

    return null;
  }

  /// Parses a spoken menu option index (1-based), including digits and ordinals.
  static int? extractOptionNumber(
    String rawAnswer,
    int maxOptions, {
    bool skipIfTimeLike = false,
  }) {
    final raw = rawAnswer.trim();
    if (raw.isEmpty || maxOptions < 1) return null;

    final explicit = extractExplicitOptionNumber(raw, maxOptions);
    if (explicit != null) return explicit;

    final sortedChinese = _chineseDigits.entries.toList()
      ..sort((a, b) => b.key.length.compareTo(a.key.length));
    for (final entry in sortedChinese) {
      if (raw.contains(entry.key) && entry.value <= maxOptions) {
        return entry.value;
      }
    }

    final text = normalize(raw);
    if (text.isEmpty) return null;

    if (RegExp(r'^\d+$').hasMatch(text)) {
      if (skipIfTimeLike && TemporalParser.looksLikeTimeExpression(raw)) {
        return null;
      }
      final value = int.tryParse(text);
      if (value != null && value >= 1 && value <= maxOptions) return value;
      return null;
    }

    final labeled = RegExp(
      r'(?:option|number|choice|nombor|pilihan|#|no|num)\s*(\d+)',
    ).firstMatch(text);
    if (labeled != null) {
      final value = int.tryParse(labeled.group(1)!);
      if (value != null && value >= 1 && value <= maxOptions) return value;
    }

    for (final entry in _wordNumbers.entries) {
      if (entry.value > maxOptions) continue;
      if (RegExp('\\b${RegExp.escape(entry.key)}\\b').hasMatch(text)) {
        return entry.value;
      }
    }

    final digit = RegExp(r'\b(\d+)\b').firstMatch(text);
    if (digit != null) {
      if (skipIfTimeLike && TemporalParser.looksLikeTimeExpression(rawAnswer)) {
        return null;
      }
      final value = int.tryParse(digit.group(1)!);
      if (value != null && value >= 1 && value <= maxOptions) return value;
    }

    return null;
  }
}
