import 'package:flutter/material.dart';

/// Tappable date row (calendar icon + label), same pattern as registration DOB.
class DateSelectField extends StatelessWidget {
  const DateSelectField({
    super.key,
    required this.selectedDate,
    required this.onTap,
    this.placeholder = 'Select Date',
    this.trailing,
  });

  final DateTime? selectedDate;
  final VoidCallback onTap;
  final String placeholder;
  final Widget? trailing;

  static const Color _fieldFill = Color(0xFF141414);
  static const Color _fieldBorder = Color(0xFF3A3A3A);
  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  Widget build(BuildContext context) {
    final loc = MaterialLocalizations.of(context);
    final label = selectedDate == null
        ? placeholder
        : loc.formatFullDate(selectedDate!);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: _fieldFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _fieldBorder, width: 1),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              color: Colors.white70,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selectedDate == null ? _subtext : Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
