import 'package:flutter/material.dart';

import '../../models/doctor_patient_summary.dart';
import '../../models/health_record_item.dart';
import '../../services/doctor_patients_service.dart';
import '../../services/health_records_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/doctor_page_scaffold.dart';
import '../widgets/doctor_patient_list_tile.dart';

class DoctorMedicalRecordsPage extends StatefulWidget {
  const DoctorMedicalRecordsPage({super.key});

  @override
  State<DoctorMedicalRecordsPage> createState() =>
      _DoctorMedicalRecordsPageState();
}

class _DoctorMedicalRecordsPageState extends State<DoctorMedicalRecordsPage> {
  final _patientsService = DoctorPatientsService();
  final _recordsService = HealthRecordsService();
  DoctorPatientSummary? _selectedPatient;

  @override
  Widget build(BuildContext context) {
    if (_selectedPatient != null) {
      return DoctorPageScaffold(
        title: _selectedPatient!.name,
        onBack: () => setState(() => _selectedPatient = null),
        body: StreamBuilder<List<HealthRecordItem>>(
          stream: _recordsService.watchForPatient(_selectedPatient!.patientId),
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
            final records = snapshot.data!;
            if (records.isEmpty) {
              return const Center(
                child: Text(
                  'No health records for this patient.',
                  style: TextStyle(color: AppColors.subtext),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: records.length,
              itemBuilder: (context, index) {
                final record = records[index];
                return Card(
                  color: AppColors.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: AppColors.border, width: 1.2),
                  ),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const Icon(Icons.description, color: AppColors.accent),
                    title: Text(
                      record.summary,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${record.recordType} • ${record.dateCreated}',
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
      title: 'Medical Records',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select a patient to view records',
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
