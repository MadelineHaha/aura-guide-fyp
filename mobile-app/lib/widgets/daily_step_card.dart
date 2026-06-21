import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../services/step_tracking_service.dart';
import 'accessible_focus_region.dart';

/// Main-menu card showing today's device step count and last sync time.
class DailyStepCard extends StatefulWidget {
  const DailyStepCard({super.key});

  @override
  State<DailyStepCard> createState() => _DailyStepCardState();
}

class _DailyStepCardState extends State<DailyStepCard> {
  final _service = StepTrackingService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceChanged);
    unawaited(_service.start());
  }

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  String _formatUpdatedAt(BuildContext context, DateTime? value) {
    if (value == null) return context.l10n.t('stepsNotUpdatedYet');
    final locale = AppLocalizations.of(context).languageCode;
    return DateFormat('HH:mm', locale).format(value);
  }

  String _formatSteps(int steps) {
    return NumberFormat.decimalPattern().format(steps);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final snapshot = _service.snapshot;
    final stepsLabel = snapshot.isLoading && snapshot.stepsToday == 0
        ? '…'
        : _formatSteps(snapshot.stepsToday);
    final updatedLabel = _formatUpdatedAt(context, snapshot.lastUpdated);

    final a11yLabel = l10n.t('stepsTodayA11y', {
      'steps': snapshot.stepsToday.toString(),
      'updated': updatedLabel,
    });

    return AccessibleFocusRegion(
      label: a11yLabel,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFF1E2A2B),
          border: Border.all(color: const Color(0xFF3D5C5E), width: 1.1),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF2A666A),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_walk_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.t('stepsToday'),
                    style: const TextStyle(
                      color: Color(0xFFB0B0B0),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stepsLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      height: 1.05,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.t('stepsLastUpdated', {'time': updatedLabel}),
                    style: const TextStyle(
                      color: Color(0xFF8A8A8A),
                      fontSize: 12,
                    ),
                  ),
                  if (!snapshot.permissionGranted &&
                      snapshot.errorMessage != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      l10n.t('stepsPermissionNeeded'),
                      style: const TextStyle(
                        color: Color(0xFFE8A838),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (snapshot.isLoading)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF63C3C4),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
