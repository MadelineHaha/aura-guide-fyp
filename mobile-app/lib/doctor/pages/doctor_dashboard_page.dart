import 'package:flutter/material.dart';

import '../widgets/doctor_dashboard_panel.dart';
import '../widgets/doctor_page_scaffold.dart';

class DoctorDashboardPage extends StatelessWidget {
  const DoctorDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DoctorPageScaffold(
      title: 'Dashboard',
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: DoctorDashboardPanel(),
      ),
    );
  }
}
