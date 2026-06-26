import 'package:flutter/material.dart';

import '../../doctor/widgets/doctor_patient_list_tile.dart';
import '../../models/doctor_patient_summary.dart';
import '../../services/doctor_patients_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/therapist_page_scaffold.dart';

class TherapistPatientsPage extends StatelessWidget {
  const TherapistPatientsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = DoctorPatientsService();
    return TherapistPageScaffold(
      title: 'Patients',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: StreamBuilder<List<DoctorPatientSummary>>(
          stream: service.watchPatients(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  'Error: ${snapshot.error}',
                  style: const TextStyle(color: Colors.red),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              );
            }
            final patients = snapshot.data!;
            if (patients.isEmpty) {
              return const Center(
                child: Text(
                  'No patients found in the system.',
                  style: TextStyle(color: AppColors.subtext),
                ),
              );
            }
            return ListView.builder(
              itemCount: patients.length,
              itemBuilder: (context, index) {
                final patient = patients[index];
                return DoctorPatientListTile(
                  patient: patient,
                  onTap: () {
                    showModalBottomSheet<void>(
                      context: context,
                      backgroundColor: AppColors.card,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      builder: (context) => Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              patient.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'ID: ${patient.patientId}',
                              style: const TextStyle(color: AppColors.subtext),
                            ),
                            if (patient.email.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                patient.email,
                                style: const TextStyle(color: AppColors.subtext),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
