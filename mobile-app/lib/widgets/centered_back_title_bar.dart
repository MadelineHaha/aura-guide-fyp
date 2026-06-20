import 'package:flutter/material.dart';

import 'app_back_button.dart';

/// Back button on the left with a step title centered on the row.
class CenteredBackTitleBar extends StatelessWidget {
  const CenteredBackTitleBar({
    super.key,
    required this.title,
    this.onBack,
    this.titleStyle = const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
      fontSize: 20,
    ),
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final String title;
  final VoidCallback? onBack;
  final TextStyle titleStyle;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: SizedBox(
        height: 40,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: AppBackButton(
                onPressed: onBack,
                style: AppBackButtonStyle.compact,
              ),
            ),
            Positioned.fill(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 72),
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
