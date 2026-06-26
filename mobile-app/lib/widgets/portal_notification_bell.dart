import 'package:flutter/material.dart';

import '../doctor/widgets/doctor_theme.dart';
import 'accessible_focus_region.dart';

class PortalNotificationBell extends StatelessWidget {
  const PortalNotificationBell({
    super.key,
    required this.unreadCount,
    required this.onTap,
    this.tooltip = 'Notifications',
  });

  final int unreadCount;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final label = unreadCount <= 0
        ? tooltip
        : unreadCount == 1
            ? '1 unread notification'
            : '$unreadCount unread notifications';

    return AccessibleFocusRegion(
      label: label,
      onActivate: onTap,
      child: Material(
        color: DoctorTheme.surfaceElevated,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: DoctorTheme.borderSoft),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.notifications_outlined,
                  color: Colors.white,
                  size: 24,
                ),
                if (unreadCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: _Badge(count: unreadCount),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final display = count > 99 ? '99+' : count.toString();
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.black, width: 1.2),
      ),
      alignment: Alignment.center,
      child: Text(
        display,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
