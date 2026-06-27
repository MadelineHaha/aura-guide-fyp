import '../models/appointment_item.dart';
import 'clinic_datetime.dart';

/// Parses spoken text to extract a requested date in English, Malay, or Chinese.
class TemporalParser {
  static DateTime? extractDate(String text) {
    final lower = text.toLowerCase().trim();

    final now = ClinicDateTime.nowClinic();
    final today = DateTime(now.year, now.month, now.day);

    if (lower.contains('today') ||
        lower.contains('hari ini') ||
        lower.contains('harini') ||
        lower.contains('今天')) {
      return today;
    }

    if (lower.contains('tomorrow') ||
        lower.contains('esok') ||
        lower.contains('besok') ||
        lower.contains('明天')) {
      return today.add(const Duration(days: 1));
    }

    if (lower.contains('day after tomorrow') ||
        lower.contains('lusa') ||
        lower.contains('后天')) {
      return today.add(const Duration(days: 2));
    }

    if (lower.contains('yesterday') ||
        lower.contains('semalam') ||
        lower.contains('kelmarin') ||
        lower.contains('昨天')) {
      return today.subtract(const Duration(days: 1));
    }

    final weekday = _extractWeekday(lower);
    if (weekday != null) {
      return _nextWeekday(today, weekday);
    }

    final zhRegex = RegExp(r'(\d{1,2})\s*月\s*(\d{1,2})\s*[号日]');
    final zhMatch = zhRegex.firstMatch(lower);
    if (zhMatch != null) {
      final month = int.tryParse(zhMatch.group(1)!);
      final day = int.tryParse(zhMatch.group(2)!);
      if (month != null && day != null) {
        return _buildDate(now, month, day);
      }
    }

    final enMonths = [
      'jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct',
      'nov', 'dec', 'january', 'february', 'march', 'april', 'june', 'july',
      'august', 'september', 'october', 'november', 'december',
    ];
    final msMonths = [
      'jan', 'feb', 'mac', 'apr', 'mei', 'jun', 'jul', 'ogo', 'sep', 'okt',
      'nov', 'dis', 'januari', 'februari', 'mac', 'april', 'julai', 'ogos',
      'september', 'oktober', 'november', 'disember',
    ];

    final allMonths = {...enMonths, ...msMonths}.toList();
    final monthsPattern = allMonths.join('|');

    final dateMonthRegex = RegExp(
      r'\b(\d{1,2})(?:st|nd|rd|th)?\s+(' + monthsPattern + r')\b',
    );
    final dateMonthMatch = dateMonthRegex.firstMatch(lower);
    if (dateMonthMatch != null) {
      final day = int.tryParse(dateMonthMatch.group(1)!);
      final monthStr = dateMonthMatch.group(2)!;
      if (day != null) {
        return _buildDate(now, _parseMonth(monthStr), day);
      }
    }

    final monthDateRegex = RegExp(
      r'\b(' + monthsPattern + r')\s+(\d{1,2})(?:st|nd|rd|th)?\b',
    );
    final monthDateMatch = monthDateRegex.firstMatch(lower);
    if (monthDateMatch != null) {
      final monthStr = monthDateMatch.group(1)!;
      final day = int.tryParse(monthDateMatch.group(2)!);
      if (day != null) {
        return _buildDate(now, _parseMonth(monthStr), day);
      }
    }

    final numericDate = RegExp(r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b').firstMatch(lower);
    if (numericDate != null) {
      final year = int.tryParse(numericDate.group(1)!);
      final month = int.tryParse(numericDate.group(2)!);
      final day = int.tryParse(numericDate.group(3)!);
      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }

    final slashDate = RegExp(r'\b(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?\b');
    final slashMatch = slashDate.firstMatch(lower);
    if (slashMatch != null) {
      final part1 = int.tryParse(slashMatch.group(1)!);
      final part2 = int.tryParse(slashMatch.group(2)!);
      final part3 = slashMatch.group(3);
      if (part1 != null && part2 != null) {
        final year = part3 == null
            ? now.year
            : int.tryParse(part3.length == 2 ? '20$part3' : part3) ?? now.year;
        return DateTime(year, part2, part1);
      }
    }

    return null;
  }

  /// Parses a spoken clock time. [minute] is null when only the hour was spoken.
  static ({int hour, int? minute})? extractTime(String text) {
    final lower = normalizeTimeSpeech(text);

    final zhMatch = RegExp(
      r'(上午|下午|晚上)?\s*(\d{1,2})\s*点\s*(\d{1,2})?\s*分?',
    ).firstMatch(lower);
    if (zhMatch != null) {
      var hour = int.tryParse(zhMatch.group(2)!);
      final minute = int.tryParse(zhMatch.group(3) ?? '');
      if (hour != null) {
        final period = zhMatch.group(1);
        if (period == '下午' || period == '晚上') {
          if (hour < 12) hour += 12;
        } else if (period == '上午' && hour == 12) {
          hour = 0;
        }
        return (hour: hour, minute: minute);
      }
    }

    final ampmMatch = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?|am|pm|pagi|petang|malam|tengah hari|pg|ptg)\b',
    ).firstMatch(lower);
    if (ampmMatch != null) {
      var hour = int.tryParse(ampmMatch.group(1)!);
      final minute = int.tryParse(ampmMatch.group(2) ?? '0');
      if (hour != null) {
        final marker = ampmMatch.group(3)!;
        if (_isPmMarker(marker) && hour < 12) hour += 12;
        if (_isAmMarker(marker) && hour == 12) hour = 0;
        return (hour: hour, minute: minute);
      }
    }

    final wordTime = _extractWordHourTime(lower);
    if (wordTime != null) return wordTime;

    final pukulMatch = RegExp(
      r'pukul\s+(\d{1,2})(?::(\d{2}))?\s*(pagi|petang|malam)?',
    ).firstMatch(lower);
    if (pukulMatch != null) {
      var hour = int.tryParse(pukulMatch.group(1)!);
      final minute = int.tryParse(pukulMatch.group(2) ?? '0');
      if (hour != null) {
        final marker = pukulMatch.group(3) ?? 'pagi';
        if (marker.contains('petang') || marker.contains('malam')) {
          if (hour < 12) hour += 12;
        }
        return (hour: hour, minute: minute);
      }
    }

    final twentyFour = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b').firstMatch(lower);
    if (twentyFour != null) {
      final hour = int.tryParse(twentyFour.group(1)!);
      final minute = int.tryParse(twentyFour.group(2)!);
      if (hour != null && minute != null) {
        return (hour: hour, minute: minute);
      }
    }

    final hourOnly = RegExp(
      r'\b(\d{1,2})\s*(o clock|oclock|pagi|petang|malam)\b',
    ).firstMatch(lower);
    if (hourOnly != null) {
      var hour = int.tryParse(hourOnly.group(1)!);
      if (hour != null) {
        final marker = hourOnly.group(2)!;
        if (marker.contains('petang') || marker.contains('malam')) {
          if (hour < 12) hour += 12;
        }
        return (hour: hour, minute: null);
      }
    }

    return null;
  }

  /// Normalizes STT output so "9 a m" / "9 A.M." become "9 am".
  static String normalizeTimeSpeech(String text) {
    var lower = text.toLowerCase().trim();
    lower = lower
        .replaceAll(RegExp(r'\ba\s*\.\s*m\s*\.?'), 'am')
        .replaceAll(RegExp(r'\bp\s*\.\s*m\s*\.?'), 'pm')
        .replaceAll(RegExp(r'\ba\s+m\b'), 'am')
        .replaceAll(RegExp(r'\bp\s+m\b'), 'pm');
    return lower;
  }

  /// True when the utterance is likely a clock time, not a menu option number.
  static bool looksLikeTimeExpression(String text) {
    final lower = normalizeTimeSpeech(text);
    if (extractTime(lower) != null) return true;
    if (RegExp(r'\b(am|pm|pagi|petang|malam|tengah hari|pukul)\b').hasMatch(lower)) {
      return true;
    }
    if (RegExp(r'\b\d{1,2}\s*:\s*\d{2}\b').hasMatch(lower)) return true;
    const wordMarkers = [
      'nine', 'ten', 'eleven', 'twelve', 'one', 'two', 'three', 'four', 'five',
      'six', 'seven', 'eight', 'sembilan', 'lapan', 'tujuh', 'enam', 'lima',
      'empat', 'tiga', 'dua', 'satu', 'twelve',
    ];
    for (final word in wordMarkers) {
      if (lower.contains(word) &&
          (lower.contains('am') ||
              lower.contains('pm') ||
              lower.contains('pagi') ||
              lower.contains('petang'))) {
        return true;
      }
    }
    return false;
  }

  static ({int hour, int? minute})? _extractWordHourTime(String lower) {
    const words = <String, int>{
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
      'eleven': 11,
      'twelve': 12,
      'satu': 1,
      'dua': 2,
      'tiga': 3,
      'empat': 4,
      'lima': 5,
      'enam': 6,
      'tujuh': 7,
      'lapan': 8,
      'sembilan': 9,
      'sepuluh': 10,
      'sebelas': 11,
      'dua belas': 12,
    };

    for (final entry in words.entries) {
      final pattern = RegExp(
        '\\b${RegExp.escape(entry.key)}\\s*(am|pm|pagi|petang|malam|tengah hari)\\b',
      );
      final match = pattern.firstMatch(lower);
      if (match == null) continue;
      var hour = entry.value;
      final marker = match.group(1)!;
      if (_isPmMarker(marker) && hour < 12) hour += 12;
      if (_isAmMarker(marker) && hour == 12) hour = 0;
      return (hour: hour, minute: 0);
    }
    return null;
  }

  static bool _isPmMarker(String marker) {
    return marker == 'pm' ||
        marker.startsWith('p.m') ||
        marker == 'petang' ||
        marker == 'ptg' ||
        marker == 'malam' ||
        marker == 'tengah hari';
  }

  static bool _isAmMarker(String marker) {
    return marker == 'am' ||
        marker.startsWith('a.m') ||
        marker == 'pagi' ||
        marker == 'pg';
  }

  static bool speechMentionsDateOrTime(String text) {
    return extractDate(text) != null || extractTime(text) != null;
  }

  static bool isAppointmentDateQuery(String text) {
    final lower = text.toLowerCase();
    const phrases = [
      'do i have',
      'any appointment',
      'appointment on',
      'appointment at',
      'have an appointment',
      'is there an appointment',
      'say a date',
      'what date',
      'check date',
      'ada temu janji',
      'temujanji pada',
      '有没有预约',
      '预约在',
      '什么日期',
    ];
    return phrases.any(lower.contains) || speechMentionsDateOrTime(text);
  }

  static int? _extractWeekday(String lower) {
    const weekdays = <String, int>{
      'monday': DateTime.monday,
      'tuesday': DateTime.tuesday,
      'wednesday': DateTime.wednesday,
      'thursday': DateTime.thursday,
      'friday': DateTime.friday,
      'saturday': DateTime.saturday,
      'sunday': DateTime.sunday,
      'isnin': DateTime.monday,
      'selasa': DateTime.tuesday,
      'rabu': DateTime.wednesday,
      'khamis': DateTime.thursday,
      'jumaat': DateTime.friday,
      'sabtu': DateTime.saturday,
      'ahad': DateTime.sunday,
      '星期一': DateTime.monday,
      '星期二': DateTime.tuesday,
      '星期三': DateTime.wednesday,
      '星期四': DateTime.thursday,
      '星期五': DateTime.friday,
      '星期六': DateTime.saturday,
      '星期日': DateTime.sunday,
      '周一': DateTime.monday,
      '周二': DateTime.tuesday,
      '周三': DateTime.wednesday,
      '周四': DateTime.thursday,
      '周五': DateTime.friday,
      '周六': DateTime.saturday,
      '周日': DateTime.sunday,
    };
    for (final entry in weekdays.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    return null;
  }

  static DateTime _nextWeekday(DateTime from, int weekday) {
    var cursor = from;
    for (var i = 0; i < 14; i++) {
      if (cursor.weekday == weekday && !cursor.isBefore(from)) {
        return cursor;
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return from.add(const Duration(days: 7));
  }

  static List<AppointmentItem> findAppointments(
    String speech,
    List<AppointmentItem> appointments,
  ) {
    final date = extractDate(speech);
    final time = extractTime(speech);
    if (date == null && time == null) return const [];

    final matches = appointments.where((appt) {
      if (appt.isCancelled) return false;

      final dateOk = date == null ||
          (appt.dateTime.year == date.year &&
              appt.dateTime.month == date.month &&
              appt.dateTime.day == date.day);

      if (!dateOk) return false;
      if (time == null) return true;

      if (time.minute != null) {
        return appt.dateTime.hour == time.hour &&
            appt.dateTime.minute == time.minute;
      }
      return appt.dateTime.hour == time.hour;
    }).toList();

    matches.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return matches;
  }

  static int _parseMonth(String month) {
    if (month.startsWith('jan')) return 1;
    if (month.startsWith('feb')) return 2;
    if (month.startsWith('mar') || month.startsWith('mac')) return 3;
    if (month.startsWith('apr')) return 4;
    if (month.startsWith('may') || month.startsWith('mei')) return 5;
    if (month.startsWith('jun')) return 6;
    if (month.startsWith('jul')) return 7;
    if (month.startsWith('aug') || month.startsWith('ogo')) return 8;
    if (month.startsWith('sep')) return 9;
    if (month.startsWith('oct') || month.startsWith('okt')) return 10;
    if (month.startsWith('nov')) return 11;
    if (month.startsWith('dec') || month.startsWith('dis')) return 12;
    return 1;
  }

  static DateTime _buildDate(DateTime now, int month, int day) {
    var year = now.year;
    final parsed = DateTime(year, month, day);
    if (now.difference(parsed).inDays > 180) {
      return DateTime(year + 1, month, day);
    }
    return parsed;
  }
}
