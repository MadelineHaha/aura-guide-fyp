import 'package:flutter/material.dart';

enum ListeningMicButtonVariant { filled, icon }

/// Mic control for speech-to-text fields. Pulses while listening.
class ListeningMicButton extends StatefulWidget {
  const ListeningMicButton({
    super.key,
    required this.listening,
    required this.onPressed,
    this.enabled = true,
    this.tooltip,
    this.size = 44,
    this.iconSize = 20,
    this.activeColor = Colors.redAccent,
    this.inactiveColor = const Color(0xFF1D7278),
    this.variant = ListeningMicButtonVariant.filled,
  });

  final bool listening;
  final VoidCallback onPressed;
  final bool enabled;
  final String? tooltip;
  final double size;
  final double iconSize;
  final Color activeColor;
  final Color inactiveColor;
  final ListeningMicButtonVariant variant;

  @override
  State<ListeningMicButton> createState() => _ListeningMicButtonState();
}

class _ListeningMicButtonState extends State<ListeningMicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnimation = Tween<double>(begin: 0.25, end: 1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _syncPulseAnimation();
  }

  @override
  void didUpdateWidget(covariant ListeningMicButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listening != widget.listening) {
      _syncPulseAnimation();
    }
  }

  void _syncPulseAnimation() {
    if (widget.listening) {
      _pulseController.repeat(reverse: true);
    } else {
      _pulseController.stop();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final micColor = widget.listening
        ? widget.activeColor
        : (widget.variant == ListeningMicButtonVariant.icon
            ? widget.inactiveColor
            : widget.inactiveColor);

    Widget micBody;
    if (widget.variant == ListeningMicButtonVariant.icon) {
      micBody = IconButton(
        onPressed: widget.enabled ? widget.onPressed : null,
        tooltip: widget.tooltip,
        icon: Icon(
          widget.listening ? Icons.mic : Icons.mic_none,
          color: micColor,
        ),
      );
    } else {
      micBody = Material(
        color: micColor,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: widget.enabled ? widget.onPressed : null,
          child: SizedBox(
            width: widget.size,
            height: widget.size,
            child: Icon(
              Icons.mic,
              color: Colors.white,
              size: widget.iconSize,
            ),
          ),
        ),
      );
    }

    if (!widget.listening) {
      return micBody;
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.activeColor.withValues(
                alpha: _pulseAnimation.value,
              ),
              width: 2.4,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.activeColor.withValues(
                  alpha: _pulseAnimation.value * 0.45,
                ),
                blurRadius: 10,
                spreadRadius: 1,
              ),
            ],
          ),
          child: child,
        );
      },
      child: micBody,
    );
  }
}
