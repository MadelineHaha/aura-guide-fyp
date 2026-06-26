import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../widgets/app_back_button.dart';
import 'doctor_theme.dart';

class DoctorPageScaffold extends StatelessWidget {
  const DoctorPageScaffold({
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
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: AppBackButton(onPressed: onBack),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            letterSpacing: 0.2,
          ),
        ),
        actions: actions,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  DoctorTheme.portalAccent.withValues(alpha: 0.35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      body: SafeArea(child: body),
    );
  }
}
