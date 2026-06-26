import 'package:flutter/material.dart';

import '../../models/doctor_patient_summary.dart';
import '../../models/medication_item.dart';
import '../../services/doctor_patients_service.dart';
import '../../services/medications_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/doctor_page_scaffold.dart';
import '../widgets/doctor_patient_list_tile.dart';

class DoctorMedicationsPage extends StatefulWidget {
  const DoctorMedicationsPage({super.key});

  @override
  State<DoctorMedicationsPage> createState() => _DoctorMedicationsPageState();
}

class _DoctorMedicationsPageState extends State<DoctorMedicationsPage> {
  final _patientsService = DoctorPatientsService();
  final _medicationsService = MedicationsService();
  DoctorPatientSummary? _selectedPatient;

  @override
  Widget build(BuildContext context) {
    if (_selectedPatient != null) {
      return DoctorPageScaffold(
        title: _selectedPatient!.name,
        onBack: () => setState(() => _selectedPatient = null),
        body: StreamBuilder<List<MedicationItem>>(
          stream: _medicationsService.watchForPatient(_selectedPatient!.patientId),
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
            final meds = snapshot.data!;
            if (meds.isEmpty) {
              return const Center(
                child: Text(
                  'No medications scheduled for today.',
                  style: TextStyle(color: AppColors.subtext),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: meds.length,
              itemBuilder: (context, index) {
                final med = meds[index];
                final taken = med.takenToday;
                return Card(
                  color: AppColors.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: taken
                          ? Colors.green.withOpacity(0.4)
                          : Colors.orange.withOpacity(0.4),
                      width: 1.2,
                    ),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(
                      med.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${med.dosage} • ${med.scheduledTime} • ${med.status}',
                      style: const TextStyle(
                        color: AppColors.subtext,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    }

    return DoctorPageScaffold(
      title: 'Medications',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select a patient to view medications',
              style: TextStyle(color: AppColors.subtext, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<List<DoctorPatientSummary>>(
                stream: _patientsService.watchPatients(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(color: AppColors.accent),
                    );
                  }
                  final patients = snapshot.data!;
                  return ListView.builder(
                    itemCount: patients.length,
                    itemBuilder: (context, index) {
                      final patient = patients[index];
                      return DoctorPatientListTile(
                        patient: patient,
                        onTap: () =>
                            setState(() => _selectedPatient = patient),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
