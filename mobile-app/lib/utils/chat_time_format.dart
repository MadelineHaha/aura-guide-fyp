import 'clinic_datetime.dart';

/// Formats message timestamps for chat UI (clinic local time, UTC+8).
class ChatTimeFormat {
  ChatTimeFormat._();

  static DateTime? _date(dynamic value) => ClinicDateTime.fromFirestore(value);

  static String listTime(dynamic value) {
    final date = _date(value);
    if (date == null) return '—';

    final now = ClinicDateTime.nowClinic();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfDate = DateTime(date.year, date.month, date.day);
    final diffDays = startOfToday.difference(startOfDate).inDays;

    if (diffDays == 0) return _clock(date);
    if (diffDays == 1) return 'Yesterday';
    if (diffDays < 7) {
      const weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      return weekdays[date.weekday - 1];
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  static String dividerLabel(dynamic value) {
    final date = _date(value);
    if (date == null) return 'Earlier';

    final now = ClinicDateTime.nowClinic();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final startOfDate = DateTime(date.year, date.month, date.day);
    final diffDays = startOfToday.difference(startOfDate).inDays;

    if (diffDays == 0) return 'Today';
    if (diffDays == 1) return 'Yesterday';
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (diffDays < 7) {
      const weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ];
      return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]} ${date.year}';
    }
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  static String messageClock(dynamic value) {
    final date = _date(value);
    if (date == null) return '—';
    return _clock(date);
  }

  /// `yyyy-MM-dd` in clinic local time for calendar jump.
  static String dateKey(dynamic value) {
    final date = _date(value);
    if (date == null) return '';
    final y = date.year;
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Section header label from a [dateKey] (`yyyy-MM-dd`).
  static String dividerLabelFromDateKey(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) return 'Earlier';
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return 'Earlier';
    return dividerLabel(DateTime(year, month, day));
  }

  /// Section header label from epoch milliseconds (conversation list).
  static String dividerLabelFromMillis(int ms) {
    if (ms <= 0) return 'Earlier';
    return dividerLabel(DateTime.fromMillisecondsSinceEpoch(ms));
  }

  static String monthYearLabel(int year, int month) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[month - 1]} $year';
  }

  static String _clock(DateTime date) {
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:$minute $period';
  }
}
