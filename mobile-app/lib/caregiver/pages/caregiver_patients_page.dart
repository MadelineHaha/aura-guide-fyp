import 'package:flutter/material.dart';

import '../../models/doctor_patient_summary.dart';
import '../../theme/app_colors.dart';
import '../../doctor/widgets/doctor_empty_state.dart';
import '../../doctor/widgets/doctor_page_scaffold.dart';
import '../../doctor/widgets/doctor_patient_list_tile.dart';
import '../services/caregiver_patients_service.dart';
import 'caregiver_patient_detail_page.dart';

class CaregiverPatientsPage extends StatelessWidget {
  const CaregiverPatientsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = CaregiverPatientsService();
    return DoctorPageScaffold(
      title: 'Connected Patients',
      body: StreamBuilder<List<DoctorPatientSummary>>(
        stream: service.watchConnectedPatients(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          final patients = snapshot.data!;
          if (patients.isEmpty) {
            return const DoctorEmptyState(
              icon: Icons.people_outline,
              message: 'No connected patients yet. Ask your clinic administrator to link patients to your account.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: patients.length,
            itemBuilder: (context, index) {
              final patient = patients[index];
              return DoctorPatientListTile(
                patient: patient,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) => CaregiverPatientDetailPage(
                        patientUid: patient.authUid,
                        patientId: patient.patientId,
                        patientName: patient.name,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
