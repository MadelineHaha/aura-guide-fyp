import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/fall_detection_coordinator.dart';

/// Starts fall monitoring while the app is in the foreground and shows the
/// check-in overlay when a possible fall is detected.
class FallDetectionHost extends StatefulWidget {
  const FallDetectionHost({super.key, required this.child});

  final Widget child;

  @override
  State<FallDetectionHost> createState() => _FallDetectionHostState();
}

class _FallDetectionHostState extends State<FallDetectionHost>
    with WidgetsBindingObserver {
  final _coordinator = FallDetectionCoordinator.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _coordinator.ensureStarted();
    _coordinator.addListener(_onCoordinatorChanged);
  }

  @override
  void dispose() {
    _coordinator.removeListener(_onCoordinatorChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onCoordinatorChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _coordinator.setAppResumed(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    final responding = _coordinator.isResponding;

    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: responding,
          child: widget.child,
        ),
        if (responding) const _FallResponseOverlay(),
      ],
    );
  }
}

class _FallResponseOverlay extends StatelessWidget {
  const _FallResponseOverlay();

  static const Color _accent = Color(0xFF63C3C4);
  static const Color _helpRed = Color(0xFFE13636);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ExcludeSemantics(
      child: Material(
        color: Colors.black.withValues(alpha: 0.92),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Text(
                  l10n.t('fallDetectionOverlayTitle'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.t('fallDetectionOverlayInstructions'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB0B0B0),
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => unawaited(
                      FallDetectionCoordinator.instance.dismissResponse(),
                    ),
                    child: Text(
                      l10n.t('fallDetectionImFineButton'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _helpRed,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => unawaited(
                      FallDetectionCoordinator.instance.requestHelp(),
                    ),
                    child: Text(
                      l10n.t('fallDetectionNeedHelpButton'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
