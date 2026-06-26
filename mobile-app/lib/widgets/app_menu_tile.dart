import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import 'accessible_focus_region.dart';

class AppMenuTile extends StatelessWidget {
  const AppMenuTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.border,
    required this.tile,
    required this.iconCircle,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color border;
  final Color tile;
  final Color iconCircle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    void onActivate() {
      if (onTap != null) {
        onTap!();
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('featureComingSoon', {'title': title})),
        ),
      );
    }

    return AccessibleFocusRegion(
      label: '$title. $subtitle',
      onActivate: onActivate,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onActivate,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: tile,
            border: Border.all(color: border, width: 1.4),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppMenuIconCircle(bg: iconCircle, icon: icon),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.subtext,
                    fontSize: 14,
                    height: 1.2,
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

class AppMenuIconCircle extends StatelessWidget {
  const AppMenuIconCircle({super.key, required this.bg, required this.icon});

  final Color bg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white70, size: 34),
    );
  }
}
