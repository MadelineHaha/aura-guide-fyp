import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/chat_time_format.dart';
import '../../utils/clinic_datetime.dart';
import 'doctor_theme.dart';

class DoctorChatCalendarSheet extends StatefulWidget {
  const DoctorChatCalendarSheet({
    super.key,
    required this.datesWithMessages,
    required this.onDateSelected,
  });

  final Set<String> datesWithMessages;
  final ValueChanged<String> onDateSelected;

  @override
  State<DoctorChatCalendarSheet> createState() =>
      _DoctorChatCalendarSheetState();
}

class _DoctorChatCalendarSheetState extends State<DoctorChatCalendarSheet> {
  late int _year;
  late int _month;

  @override
  void initState() {
    super.initState();
    final now = ClinicDateTime.nowClinic();
    _year = now.year;
    _month = now.month;
  }

  void _changeMonth(int delta) {
    setState(() {
      _month += delta;
      if (_month < 1) {
        _month = 12;
        _year--;
      } else if (_month > 12) {
        _month = 1;
        _year++;
      }
    });
  }

  List<_DayCell> _buildCells() {
    final first = DateTime(_year, _month, 1);
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final leading = first.weekday % 7;
    final cells = <_DayCell>[];

    for (var i = 0; i < leading; i++) {
      cells.add(const _DayCell.outside());
    }
    final todayKey = ChatTimeFormat.dateKey(ClinicDateTime.nowClinic());
    for (var day = 1; day <= daysInMonth; day++) {
      final dateKey =
          '$_year-${_month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
      cells.add(
        _DayCell(
          day: day,
          dateKey: dateKey,
          hasMessages: widget.datesWithMessages.contains(dateKey),
          isToday: dateKey == todayKey,
        ),
      );
    }
    while (cells.length % 7 != 0) {
      cells.add(const _DayCell.outside());
    }
    return cells;
  }

  @override
  Widget build(BuildContext context) {
    final cells = _buildCells();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  'Jump to date',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left, color: Colors.white),
                ),
                Expanded(
                  child: Text(
                    ChatTimeFormat.monthYearLabel(_year, _month),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: const [
                _WeekdayLabel('S'),
                _WeekdayLabel('M'),
                _WeekdayLabel('T'),
                _WeekdayLabel('W'),
                _WeekdayLabel('T'),
                _WeekdayLabel('F'),
                _WeekdayLabel('S'),
              ],
            ),
            const SizedBox(height: 6),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: cells.length,
              itemBuilder: (context, index) {
                final cell = cells[index];
                if (cell.isOutside) {
                  return const SizedBox.shrink();
                }
                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: cell.hasMessages
                        ? () {
                            Navigator.of(context).pop();
                            widget.onDateSelected(cell.dateKey!);
                          }
                        : null,
                    borderRadius: BorderRadius.circular(10),
                    child: Ink(
                      decoration: BoxDecoration(
                        color: cell.hasMessages
                            ? DoctorTheme.portalGlow.withValues(alpha: 0.35)
                            : DoctorTheme.surfaceElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: cell.isToday
                              ? DoctorTheme.portalAccent
                              : cell.hasMessages
                                  ? DoctorTheme.portalAccent
                                      .withValues(alpha: 0.4)
                                  : DoctorTheme.borderSoft,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${cell.day}',
                          style: TextStyle(
                            color: cell.hasMessages
                                ? Colors.white
                                : AppColors.subtext.withValues(alpha: 0.5),
                            fontWeight: cell.isToday
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            const Text(
              'Days with messages are highlighted. Tap a highlighted day to jump.',
              style: TextStyle(color: AppColors.subtext, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: AppColors.subtext,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DayCell {
  const _DayCell({
    required this.day,
    required this.dateKey,
    required this.hasMessages,
    required this.isToday,
  }) : isOutside = false;

  const _DayCell.outside()
      : day = 0,
        dateKey = null,
        hasMessages = false,
        isToday = false,
        isOutside = true;

  final int day;
  final String? dateKey;
  final bool hasMessages;
  final bool isToday;
  final bool isOutside;
}
