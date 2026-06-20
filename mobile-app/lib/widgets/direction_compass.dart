import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/navigation_guidance_controller.dart';

/// Compass-style indicator pointing toward the navigation destination.
class DirectionCompass extends StatelessWidget {
  const DirectionCompass({
    super.key,
    required this.state,
    this.size = 160,
    this.compact = false,
  });

  final NavigationGuidanceState state;
  final double size;
  final bool compact;

  static const Color _accent = Color(0xFF63F7F2);

  @override
  Widget build(BuildContext context) {
    final arrowRotation = state.turnDelta * math.pi / 180;

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 18),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            Row(
              children: [
                Icon(
                  state.walkMode ? Icons.directions_walk : Icons.explore,
                  color: state.walkMode ? _accent : Colors.white38,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.walkMode
                        ? 'Walk mode'
                        : state.hasGpsFix
                            ? 'GPS active'
                            : 'Starting GPS…',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (state.hasGpsFix)
                  Text(
                    '${state.distanceMeters.toStringAsFixed(0)} m',
                    style: const TextStyle(
                      color: _accent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white12, width: 2),
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
                ..._cardinalLabels(size),
                Transform.rotate(
                  angle: arrowRotation,
                  child: Icon(
                    Icons.navigation,
                    color: _accent,
                    size: size * 0.42,
                    shadows: const [
                      Shadow(
                        color: Color(0xAA63F7F2),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            state.guidanceHint,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          if (!compact && state.hasGpsFix) ...[
            const SizedBox(height: 4),
            Text(
              'Bearing ${state.targetBearing.toStringAsFixed(0)}°',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _cardinalLabels(double compassSize) {
    const labels = ['N', 'E', 'S', 'W'];
    final radius = compassSize * 0.38;
    return List.generate(4, (index) {
      final angle = (index * 90 - 90) * math.pi / 180;
      return Transform.translate(
        offset: Offset(
          math.cos(angle) * radius,
          math.sin(angle) * radius,
        ),
        child: Text(
          labels[index],
          style: TextStyle(
            color: labels[index] == 'N' ? _accent : Colors.white38,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    });
  }
}
