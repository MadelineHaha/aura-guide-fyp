import 'package:flutter/material.dart';

import '../widgets/therapist_dashboard_panel.dart';
import '../widgets/therapist_page_scaffold.dart';

class TherapistDashboardPage extends StatelessWidget {
  const TherapistDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TherapistPageScaffold(
      title: 'Dashboard',
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: TherapistDashboardPanel(),
      ),
    );
  }
}
