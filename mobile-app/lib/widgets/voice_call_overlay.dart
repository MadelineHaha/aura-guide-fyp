import 'dart:ui';

import 'package:flutter/material.dart';

import '../widgets/accessible_focus_region.dart';

class VoiceCallOverlay extends StatelessWidget {
  const VoiceCallOverlay({
    super.key,
    required this.remoteName,
    required this.statusText,
    required this.showTimer,
    required this.timerText,
    required this.showMute,
    required this.isMuted,
    required this.onToggleMute,
    required this.onEndCall,
    this.hintText,
    this.showAnswerActions = false,
    this.onAnswer,
    this.onDecline,
    this.answerLabel = 'Answer',
    this.answerA11yLabel = 'Answer button',
    this.declineLabel = 'Decline',
    this.declineA11yLabel = 'Decline button',
    this.muteLabel = 'Mute',
    this.unmuteLabel = 'Unmute',
    this.endLabel = 'End call',
  });

  final String remoteName;
  final String statusText;
  final String? hintText;
  final bool showTimer;
  final String timerText;
  final bool showMute;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final VoidCallback onEndCall;
  final bool showAnswerActions;
  final VoidCallback? onAnswer;
  final VoidCallback? onDecline;
  final String answerLabel;
  final String answerA11yLabel;
  final String declineLabel;
  final String declineA11yLabel;
  final String muteLabel;
  final String unmuteLabel;
  final String endLabel;

  static const Color _teal = Color(0xFF6BC4C4);
  static const Color _name = Color(0xFF212529);
  static const Color _muted = Color(0xFF6C757D);
  static const Color _hint = Color(0xFF868E96);
  static const Color _timer = Color(0xFF2F8F8F);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: ExcludeSemantics(
                child: Container(color: const Color(0xB7111827)),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: showAnswerActions
                    ? _IncomingCallCard(
                        remoteName: remoteName,
                        statusText: statusText,
                        hintText: hintText,
                        answerLabel: answerLabel,
                        answerA11yLabel: answerA11yLabel,
                        declineLabel: declineLabel,
                        declineA11yLabel: declineA11yLabel,
                        onAnswer: onAnswer,
                        onDecline: onDecline,
                      )
                    : _ActiveCallCard(
                        remoteName: remoteName,
                        statusText: statusText,
                        showTimer: showTimer,
                        timerText: timerText,
                        showMute: showMute,
                        isMuted: isMuted,
                        onToggleMute: onToggleMute,
                        onEndCall: onEndCall,
                        muteLabel: muteLabel,
                        unmuteLabel: unmuteLabel,
                        endLabel: endLabel,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IncomingCallCard extends StatelessWidget {
  const _IncomingCallCard({
    required this.remoteName,
    required this.statusText,
    required this.hintText,
    required this.answerLabel,
    required this.answerA11yLabel,
    required this.declineLabel,
    required this.declineA11yLabel,
    required this.onAnswer,
    required this.onDecline,
  });

  final String remoteName;
  final String statusText;
  final String? hintText;
  final String answerLabel;
  final String answerA11yLabel;
  final String declineLabel;
  final String declineA11yLabel;
  final VoidCallback? onAnswer;
  final VoidCallback? onDecline;

  @override
  Widget build(BuildContext context) {
    final hasHint = hintText != null && hintText!.isNotEmpty;
    final declineOrder = hasHint ? 4 : 3;
    final answerOrder = hasHint ? 5 : 4;

    return Semantics(
      explicitChildNodes: true,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF4FBFB), Colors.white],
            stops: [0.0, 0.42],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 48,
              offset: const Offset(0, 24),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 36, 28, 20),
                    child: Column(
                      children: [
                        ExcludeSemantics(
                          child: _CallAvatar(
                            name: remoteName,
                            size: 88,
                            fontSize: 26,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(1),
                          child: AccessibleFocusRegion(
                            label: remoteName,
                            child: Text(
                              remoteName,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: VoiceCallOverlay._name,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        FocusTraversalOrder(
                          order: const NumericFocusOrder(2),
                          child: AccessibleFocusRegion(
                            label: statusText,
                            child: Text(
                              statusText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: VoiceCallOverlay._muted,
                                fontSize: 15,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                        if (hasHint) ...[
                          const SizedBox(height: 8),
                          FocusTraversalOrder(
                            order: const NumericFocusOrder(3),
                            child: AccessibleFocusRegion(
                              label: hintText!,
                              child: Text(
                                hintText!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: VoiceCallOverlay._hint,
                                  fontSize: 13.5,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: FocusTraversalOrder(
                            order: NumericFocusOrder(declineOrder.toDouble()),
                            child: AccessibleFocusRegion(
                              label: declineA11yLabel,
                              onActivate: onDecline,
                              child: _PillCallButton(
                                label: declineLabel,
                                backgroundColor: const Color(0xFFE03131),
                                onPressed: onDecline,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FocusTraversalOrder(
                            order: NumericFocusOrder(answerOrder.toDouble()),
                            child: AccessibleFocusRegion(
                              label: answerA11yLabel,
                              onActivate: onAnswer,
                              child: _PillCallButton(
                                label: answerLabel,
                                backgroundColor: const Color(0xFF2F9E44),
                                icon: Icons.call_rounded,
                                onPressed: onAnswer,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveCallCard extends StatelessWidget {
  const _ActiveCallCard({
    required this.remoteName,
    required this.statusText,
    required this.showTimer,
    required this.timerText,
    required this.showMute,
    required this.isMuted,
    required this.onToggleMute,
    required this.onEndCall,
    required this.muteLabel,
    required this.unmuteLabel,
    required this.endLabel,
  });

  final String remoteName;
  final String statusText;
  final bool showTimer;
  final String timerText;
  final bool showMute;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final VoidCallback onEndCall;
  final String muteLabel;
  final String unmuteLabel;
  final String endLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF4FBFB), Colors.white],
          stops: [0.0, 0.55],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 48,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: Semantics(
        explicitChildNodes: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FocusTraversalGroup(
              policy: OrderedTraversalPolicy(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExcludeSemantics(
                    child: _CallAvatar(name: remoteName, size: 92, fontSize: 27),
                  ),
                  const SizedBox(height: 14),
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(1),
                    child: AccessibleFocusRegion(
                      label: remoteName,
                      child: Text(
                        remoteName,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: VoiceCallOverlay._name,
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FocusTraversalOrder(
                    order: const NumericFocusOrder(2),
                    child: AccessibleFocusRegion(
                      label: statusText,
                      child: Text(
                        statusText,
                        style: const TextStyle(
                          color: VoiceCallOverlay._muted,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  if (showTimer) ...[
                    const SizedBox(height: 6),
                    FocusTraversalOrder(
                      order: const NumericFocusOrder(3),
                      child: AccessibleFocusRegion(
                        label: timerText,
                        child: Text(
                          timerText,
                          style: const TextStyle(
                            color: VoiceCallOverlay._timer,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (showMute) ...[
                        FocusTraversalOrder(
                          order: NumericFocusOrder(showTimer ? 4 : 3),
                          child: AccessibleFocusRegion(
                            label: isMuted ? unmuteLabel : muteLabel,
                            onActivate: onToggleMute,
                            child: _VoiceControlButton(
                              label: isMuted ? unmuteLabel : muteLabel,
                              icon: isMuted
                                  ? Icons.mic_off_rounded
                                  : Icons.mic_rounded,
                              color: isMuted
                                  ? const Color(0xFFDC3545)
                                  : const Color(0xFF495057),
                              onPressed: onToggleMute,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                      ],
                      FocusTraversalOrder(
                        order: NumericFocusOrder(
                          showTimer
                              ? (showMute ? 5 : 4)
                              : (showMute ? 4 : 3),
                        ),
                        child: AccessibleFocusRegion(
                          label: endLabel,
                          onActivate: onEndCall,
                          child: _VoiceControlButton(
                            label: endLabel,
                            icon: Icons.call_end_rounded,
                            color: const Color(0xFFE03131),
                            onPressed: onEndCall,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallAvatar extends StatelessWidget {
  const _CallAvatar({
    required this.name,
    required this.size,
    required this.fontSize,
  });

  final String name;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: VoiceCallOverlay._teal,
          shape: BoxShape.circle,
        ),
        child: Text(
          _initials(name),
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  String _initials(String value) {
    final parts = value.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    final letters = parts.map((part) => part[0]).take(2).join();
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }
}

class _PillCallButton extends StatelessWidget {
  const _PillCallButton({
    required this.label,
    required this.backgroundColor,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final Color backgroundColor;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onPressed,
        child: SizedBox(
          height: 46,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceControlButton extends StatelessWidget {
  const _VoiceControlButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 92),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 22),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
