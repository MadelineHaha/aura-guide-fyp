import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'accessible_focus_region.dart';

enum AppBackButtonStyle {
  appBar,
  compact,
  filled,
}

/// Shared back control — text-only back label (no arrow icon).
class AppBackButton extends StatelessWidget {
  const AppBackButton({
    super.key,
    this.onPressed,
    this.color = Colors.white,
    this.style = AppBackButtonStyle.appBar,
  });

  static const double appBarLeadingWidth = 72;

  final VoidCallback? onPressed;
  final Color color;
  final AppBackButtonStyle style;

  static TextStyle _labelStyle(Color color) => TextStyle(
        color: color,
        fontWeight: FontWeight.w600,
        fontSize: 16,
      );

  void _handlePress(BuildContext context) {
    if (onPressed != null) {
      onPressed!();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = context.l10n.t('back');
    void onTap() => _handlePress(context);

    Widget button;
    switch (style) {
      case AppBackButtonStyle.filled:
        button = FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: Colors.black54,
            foregroundColor: color,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            visualDensity: VisualDensity.compact,
          ),
          child: Text(label),
        );
      case AppBackButtonStyle.compact:
        button = TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(label, style: _labelStyle(color)),
        );
      case AppBackButtonStyle.appBar:
        button = Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(label, style: _labelStyle(color)),
          ),
        );
    }

    return AccessibleFocusRegion(
      label: label,
      onActivate: onTap,
      child: button,
    );
  }
}
