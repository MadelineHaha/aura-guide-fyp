/// Parses spoken speech into a 4-digit PIN.
class SpokenPinParser {
  SpokenPinParser._();

  static const _wordToDigit = <String, String>{
    'zero': '0',
    'oh': '0',
    'o': '0',
    'one': '1',
    'won': '1',
    'wan': '1',
    'two': '2',
    'to': '2',
    'too': '2',
    'tu': '2',
    'three': '3',
    'tree': '3',
    'free': '3',
    'four': '4',
    'for': '4',
    'fore': '4',
    'five': '5',
    'fife': '5',
    'six': '6',
    'sicks': '6',
    'seven': '7',
    'eight': '8',
    'ate': '8',
    'nine': '9',
    'niner': '9',
    // Malay Digits
    'kosong': '0',
    'sifar': '0',
    'satu': '1',
    'dua': '2',
    'tiga': '3',
    'empat': '4',
    'lima': '5',
    'enam': '6',
    'tujuh': '7',
    'lapan': '8',
    'sembilan': '9',
    // Chinese Digits (Characters)
    '零': '0',
    '〇': '0',
    '一': '1',
    '壹': '1',
    '二': '2',
    '贰': '2',
    '两': '2',
    '俩': '2',
    '三': '3',
    '叁': '3',
    '四': '4',
    '肆': '4',
    '五': '5',
    '伍': '5',
    '六': '6',
    '陆': '6',
    '七': '7',
    '柒': '7',
    '八': '8',
    '捌': '8',
    '九': '9',
    '玖': '9',
    // Chinese Pinyin
    'ling': '0',
    'yi': '1',
    'er': '2',
    'liang': '2',
    'san': '3',
    'si': '4',
    'wu': '5',
    'liu': '6',
    'qi': '7',
    'ba': '8',
    'jiu': '9',
  };

  /// Returns digit tokens extracted from [raw] in speaking order.
  static List<String> extractDigitTokens(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];

    final tokens = <String>[];

    final digitsOnly = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length >= 4) {
      for (var i = 0; i < 4; i++) {
        tokens.add(digitsOnly[i]);
      }
      return tokens;
    }

    // Keep non-punctuation characters including letters, pinyin, and Chinese characters.
    final normalized = trimmed
        .toLowerCase()
        .replaceAll(RegExp(r'[.,\/#!$%\^&\*;:{}=\-_`~()?¿¡]'), ' ')
        .trim();
    if (normalized.isEmpty) return tokens;

    for (final word in normalized.split(RegExp(r'\s+'))) {
      if (word.isEmpty) continue;
      
      final wordDigits = word.replaceAll(RegExp(r'[^0-9]'), '');
      if (wordDigits.isNotEmpty) {
        for (var i = 0; i < wordDigits.length; i++) {
          tokens.add(wordDigits[i]);
          if (tokens.length >= 4) return tokens.take(4).toList();
        }
      } else {
        final mapped = _wordToDigit[word];
        if (mapped != null) {
          tokens.add(mapped);
        } else {
          // If the word doesn't map as a whole (like run-together characters "一二三四"),
          // check each character individually.
          for (var i = 0; i < word.length; i++) {
            final char = word[i];
            final charMapped = _wordToDigit[char];
            if (charMapped != null) {
              tokens.add(charMapped);
            }
            if (tokens.length >= 4) return tokens.take(4).toList();
          }
        }
      }
      if (tokens.length >= 4) break;
    }

    return tokens.length > 4 ? tokens.take(4).toList() : tokens;
  }

  /// Merges newly heard tokens into a running session buffer (max 4),
  /// using prefix and overlap comparison to handle cumulative speech recognition updates.
  static List<String> mergeDigitTokens(
    List<String> existing,
    String raw,
  ) {
    final newTokens = extractDigitTokens(raw);
    if (newTokens.isEmpty) return existing;

    // 1. Find the largest overlap where the end of 'existing' matches the start of 'newTokens'.
    int overlap = 0;
    for (int i = 1; i <= existing.length && i <= newTokens.length; i++) {
      bool match = true;
      for (int j = 0; j < i; j++) {
        if (existing[existing.length - i + j] != newTokens[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        overlap = i;
      }
    }

    // 2. Check for a common prefix (e.g. cumulative update with a correction/modification later).
    int commonPrefix = 0;
    for (int i = 0; i < existing.length && i < newTokens.length; i++) {
      if (existing[i] == newTokens[i]) {
        commonPrefix++;
      } else {
        break;
      }
    }

    // If there is a common prefix and the newTokens stream is longer or equal,
    // we prioritize the new cumulative stream.
    if (commonPrefix > 0 && newTokens.length >= existing.length) {
      return newTokens.length > 4 ? newTokens.take(4).toList() : newTokens;
    }

    final merged = [...existing];
    for (final token in newTokens.sublist(overlap)) {
      if (merged.length >= 4) break;
      merged.add(token);
    }
    return merged.length > 4 ? merged.take(4).toList() : merged;
  }

  static String? pinFromTokens(List<String> tokens) {
    if (tokens.length < 4) return null;
    return tokens.take(4).join();
  }

  /// Returns a 4-digit PIN when [raw] speech can be parsed, otherwise null.
  static String? parseFourDigitPin(String raw) {
    return pinFromTokens(extractDigitTokens(raw));
  }

  /// True when at least four digit tokens are available.
  static bool hasCompleteFourDigitPin(String raw) {
    return extractDigitTokens(raw).length >= 4;
  }

  static bool hasCompleteTokenList(List<String> tokens) => tokens.length >= 4;

  /// Counts digits parsed so far from partial speech (for live feedback).
  static int digitCount(String raw) => extractDigitTokens(raw).length;
}
