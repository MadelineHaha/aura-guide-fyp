import 'package:intl/intl.dart';

/// Parses common spoken or dictated birth-date phrases into [DateTime].
DateTime? parseSpokenBirthDate(String raw, {DateTime? reference}) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final ref = reference ?? DateTime.now();
  final last = DateTime(ref.year, ref.month, ref.day);
  final first = DateTime(ref.year - 120, 1, 1);

  final numeric = RegExp(r'^(\d{1,2})[\/\-\.](\d{1,2})[\/\-\.](\d{4})$')
      .firstMatch(text);
  if (numeric != null) {
    final day = int.tryParse(numeric.group(1)!);
    final month = int.tryParse(numeric.group(2)!);
    final year = int.tryParse(numeric.group(3)!);
    final parsed = _safeDate(year, month, day);
    if (parsed != null && _inRange(parsed, first, last)) return parsed;
  }

  const patterns = <String>[
    'd MMMM yyyy',
    'MMMM d yyyy',
    'MMMM d, yyyy',
    'd MMM yyyy',
    'MMM d yyyy',
    'yyyy-MM-dd',
  ];

  for (final pattern in patterns) {
    try {
      final parsed = DateFormat(pattern, 'en').parseLoose(text);
      final date = DateTime(parsed.year, parsed.month, parsed.day);
      if (_inRange(date, first, last)) return date;
    } catch (_) {
      continue;
    }
  }

  return null;
}

DateTime? _safeDate(int? year, int? month, int? day) {
  if (year == null || month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  try {
    return DateTime(year, month, day);
  } catch (_) {
    return null;
  }
}

bool _inRange(DateTime date, DateTime first, DateTime last) {
  return !date.isBefore(first) && !date.isAfter(last);
}
