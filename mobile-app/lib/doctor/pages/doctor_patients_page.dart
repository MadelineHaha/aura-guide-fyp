import 'package:flutter/material.dart';

import '../../models/doctor_patient_summary.dart';
import '../../services/doctor_patients_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/doctor_empty_state.dart';
import '../widgets/doctor_page_scaffold.dart';
import '../widgets/doctor_patient_list_tile.dart';
import '../widgets/doctor_theme.dart';
import 'doctor_patient_detail_page.dart';

class DoctorPatientsPage extends StatelessWidget {
  const DoctorPatientsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = DoctorPatientsService();
    return DoctorPageScaffold(
      title: 'Patients',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: StreamBuilder<List<DoctorPatientSummary>>(
          stream: service.watchPatients(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return DoctorEmptyState(
                icon: Icons.error_outline,
                message: 'Could not load patients',
                detail: snapshot.error.toString(),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              );
            }
            final patients = snapshot.data!;
            if (patients.isEmpty) {
              return const DoctorEmptyState(
                icon: Icons.people_outline,
                message: 'No patients yet',
                detail: 'Patients assigned to you will appear here.',
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: DoctorTheme.accentCard(),
                  child: Row(
                    children: [
                      const Icon(Icons.people, color: DoctorTheme.portalAccent),
                      const SizedBox(width: 10),
                      Text(
                        patients.length == 1
                            ? '1 active patient'
                            : '${patients.length} active patients',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView.builder(
                    itemCount: patients.length,
                    itemBuilder: (context, index) {
                      final patient = patients[index];
                      return DoctorPatientListTile(
                        patient: patient,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (context) => DoctorPatientDetailPage(
                                patientUid: patient.authUid,
                                patientId: patient.patientId,
                                patientName: patient.name,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
