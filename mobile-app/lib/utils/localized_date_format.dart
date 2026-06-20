import 'package:intl/intl.dart';

/// Locale-aware calendar labels for UI and TalkBack.
class LocalizedDateFormat {
  LocalizedDateFormat._();

  static const _cnDigits = [
    '零',
    '一',
    '二',
    '三',
    '四',
    '五',
    '六',
    '七',
    '八',
    '九',
  ];

  /// Visible date on screen (e.g. Chinese: 星期六，2026年6月20号).
  static String displayDate(DateTime date, String languageCode) {
    switch (languageCode) {
      case 'zh':
        final weekday = DateFormat('EEEE', 'zh_CN').format(date);
        return '$weekday，${date.year}年${date.month}月${date.day}号';
      case 'ms':
        return DateFormat('EEEE, d MMMM y', 'ms').format(date);
      default:
        return DateFormat('EEEE, d MMMM y', 'en').format(date);
    }
  }

  /// Spoken form for accessibility (e.g. Chinese: 星期六，二零二六年六月二十号).
  static String spokenDate(DateTime date, String languageCode) {
    if (languageCode == 'zh') {
      return _chineseSpokenDate(date);
    }
    return displayDate(date, languageCode);
  }

  static String _chineseSpokenDate(DateTime date) {
    final weekday = DateFormat('EEEE', 'zh_CN').format(date);
    final yearSpoken =
        date.year.toString().split('').map(_cnDigitChar).join();
    return '$weekday，$yearSpoken年${_chineseNumber(date.month)}月${_chineseNumber(date.day)}号';
  }

  static String _cnDigitChar(String digit) => _cnDigits[int.parse(digit)];

  static String _chineseNumber(int value) {
    if (value <= 0) return value.toString();
    if (value < 10) return _cnDigits[value];
    if (value == 10) return '十';
    if (value < 20) return '十${_cnDigits[value - 10]}';
    if (value < 100) {
      final tens = value ~/ 10;
      final ones = value % 10;
      if (ones == 0) return '${_cnDigits[tens]}十';
      return '${_cnDigits[tens]}十${_cnDigits[ones]}';
    }
    return value.toString();
  }
}
