import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// Dark calendar dialog used for birth date, appointment date, etc.
/// Matches the registration flow picker (bounded height + scrollable).
Future<DateTime?> showCalendarDatePickerDialog({
  required BuildContext context,
  required String title,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  Color accent = const Color(0xFF63C3C4),
}) {
  return showDialog<DateTime>(
    context: context,
    barrierDismissible: true,
    builder: (context) => CalendarDatePickerDialog(
      title: title,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      accent: accent,
    ),
  );
}

class CalendarDatePickerDialog extends StatefulWidget {
  const CalendarDatePickerDialog({
    super.key,
    required this.title,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    required this.accent,
  });

  final String title;
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Color accent;

  @override
  State<CalendarDatePickerDialog> createState() =>
      _CalendarDatePickerDialogState();
}

class _CalendarDatePickerDialogState extends State<CalendarDatePickerDialog> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.92;

    final theme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: widget.accent,
        onPrimary: Colors.black,
        surface: const Color(0xFF1E1E1E),
        onSurface: Colors.white,
        surfaceContainerHighest: const Color(0xFF2A2A2A),
      ),
    );

    return Theme(
      data: theme,
      child: Dialog(
        backgroundColor: const Color(0xFF1E1E1E),
        clipBehavior: Clip.none,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 420,
            maxHeight: maxH,
          ),
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: true,
              physics: const ClampingScrollPhysics(),
            ),
            child: SingleChildScrollView(
              primary: true,
              physics: const ClampingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 360,
                      width: double.infinity,
                      child: CalendarDatePicker(
                        initialDate: _selected,
                        firstDate: widget.firstDate,
                        lastDate: widget.lastDate,
                        onDateChanged: (d) => setState(() => _selected = d),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(context.l10n.t('cancel')),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(_selected),
                          style: FilledButton.styleFrom(
                            backgroundColor: widget.accent,
                            foregroundColor: Colors.black,
                          ),
                          child: Text(context.l10n.t('ok')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

DateTime clampCalendarDate(DateTime date, DateTime min, DateTime max) {
  if (date.isBefore(min)) return min;
  if (date.isAfter(max)) return max;
  return date;
}
