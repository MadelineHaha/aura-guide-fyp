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
  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final coordinator = FallDetectionCoordinator.instance;

    return Material(
      color: Colors.black.withValues(alpha: 0.92),
      child: SafeArea(
        child: ListenableBuilder(
          listenable: coordinator,
          builder: (context, _) {
            final isDemo = coordinator.isDemoSession;
            final titleKey = isDemo
                ? 'fallDetectionDemoOverlayTitle'
                : 'fallDetectionOverlayTitle';
            final instructionsKey = isDemo
                ? 'fallDetectionDemoOverlayInstructions'
                : 'fallDetectionOverlayInstructions';
            final heard = coordinator.heardVoicePreview.trim();

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.t(titleKey),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.t(instructionsKey),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _subtext,
                      fontSize: 16,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (coordinator.isListeningForVoice) ...[
                    const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          color: _accent,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.t('fallDetectionListening'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (heard.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.t('fallDetectionHeardPreview', {'words': heard}),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                  if (coordinator.lastVoiceAnalysis != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      coordinator.lastVoiceAnalysis!.isEmergency
                          ? l10n.t(
                              isDemo
                                  ? 'fallDetectionDemoAnalysisEmergency'
                                  : 'fallDetectionAnalysisEmergency',
                            )
                          : l10n.t('fallDetectionAnalysisSafe'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: coordinator.lastVoiceAnalysis!.isEmergency
                            ? _helpRed
                            : _accent,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
                        coordinator.dismissResponse(),
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
                        coordinator.requestHelp(),
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
            );
          },
        ),
      ),
    );
  }
}
