import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_back_button.dart';

class TherapistPageScaffold extends StatelessWidget {
  const TherapistPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.onBack,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        leading: AppBackButton(onPressed: onBack),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: actions,
      ),
      body: SafeArea(child: body),
    );
  }
}
