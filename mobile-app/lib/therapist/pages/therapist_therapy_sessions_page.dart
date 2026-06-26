import 'package:flutter/material.dart';

import '../../doctor/widgets/doctor_patient_list_tile.dart';
import '../../models/doctor_patient_summary.dart';
import '../../models/therapy_session_item.dart';
import '../../services/doctor_patients_service.dart';
import '../../services/therapy_sessions_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/therapist_page_scaffold.dart';

class TherapistTherapySessionsPage extends StatefulWidget {
  const TherapistTherapySessionsPage({super.key});

  @override
  State<TherapistTherapySessionsPage> createState() =>
      _TherapistTherapySessionsPageState();
}

class _TherapistTherapySessionsPageState
    extends State<TherapistTherapySessionsPage> {
  final _patientsService = DoctorPatientsService();
  final _sessionsService = TherapySessionsService();
  DoctorPatientSummary? _selectedPatient;

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openRecordSheet(TherapySessionItem session) async {
    final nameController = TextEditingController(text: session.sessionName);
    final durationController =
        TextEditingController(text: session.sessionDuration);
    final remarksController =
        TextEditingController(text: session.sessionRemarks);
    var sessionStatus = session.sessionStatus.isNotEmpty
        ? session.sessionStatus
        : 'Improved';
    var sessionOutcome = session.sessionOutcome.isNotEmpty
        ? session.sessionOutcome
        : 'Good';

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Record Therapy Session',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Session name',
                        labelStyle: TextStyle(color: AppColors.subtext),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: durationController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Duration',
                        labelStyle: TextStyle(color: AppColors.subtext),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: remarksController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Remarks',
                        labelStyle: TextStyle(color: AppColors.subtext),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: sessionStatus,
                      dropdownColor: AppColors.card,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Progress status',
                        labelStyle: TextStyle(color: AppColors.subtext),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Improved',
                          child: Text('Improved'),
                        ),
                        DropdownMenuItem(value: 'Stable', child: Text('Stable')),
                        DropdownMenuItem(
                          value: 'Requiring Additional Training',
                          child: Text('Requiring Additional Training'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setModalState(() => sessionStatus = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: sessionOutcome,
                      dropdownColor: AppColors.card,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Outcome',
                        labelStyle: TextStyle(color: AppColors.subtext),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Excellent',
                          child: Text('Excellent'),
                        ),
                        DropdownMenuItem(value: 'Good', child: Text('Good')),
                        DropdownMenuItem(
                          value: 'Needs Improvement',
                          child: Text('Needs Improvement'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setModalState(() => sessionOutcome = v);
                      },
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Save session details'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (saved != true) {
      nameController.dispose();
      durationController.dispose();
      remarksController.dispose();
      return;
    }
    if (!mounted) {
      nameController.dispose();
      durationController.dispose();
      remarksController.dispose();
      return;
    }

    final name = nameController.text.trim();
    final duration = durationController.text.trim();
    final remarks = remarksController.text.trim();
    nameController.dispose();
    durationController.dispose();
    remarksController.dispose();

    try {
      await _sessionsService.updateSessionDetails(
        appointmentId: session.id,
        sessionName: name,
        sessionDuration: duration,
        sessionRemarks: remarks,
        sessionStatus: sessionStatus,
        sessionOutcome: sessionOutcome,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session details saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedPatient != null) {
      return TherapistPageScaffold(
        title: _selectedPatient!.name,
        onBack: () => setState(() => _selectedPatient = null),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Record session',
            onPressed: () async {
              final sessions = await _sessionsService
                  .fetchForPatient(_selectedPatient!.patientId);
              if (!mounted) return;
              if (sessions.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('No therapy appointments for this patient.'),
                  ),
                );
                return;
              }
              await _openRecordSheet(sessions.first);
            },
          ),
        ],
        body: StreamBuilder<List<TherapySessionItem>>(
          stream: _sessionsService.watchForPatient(_selectedPatient!.patientId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              );
            }
            final sessions = snapshot.data!;
            if (sessions.isEmpty) {
              return const Center(
                child: Text(
                  'No therapy sessions for this patient.',
                  style: TextStyle(color: AppColors.subtext),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final session = sessions[index];
                return Card(
                  color: AppColors.card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: const BorderSide(color: AppColors.border, width: 1.2),
                  ),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    onTap: () => _openRecordSheet(session),
                    leading: const Icon(
                      Icons.fitness_center,
                      color: AppColors.accent,
                    ),
                    title: Text(
                      session.sessionName.isNotEmpty
                          ? session.sessionName
                          : 'Therapy Session',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${_formatDateTime(session.dateTime)}\n'
                      'Status: ${session.sessionStatus.isNotEmpty ? session.sessionStatus : session.status}',
                      style: const TextStyle(
                        color: AppColors.subtext,
                        fontSize: 13,
                      ),
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            );
          },
        ),
      );
    }

    return TherapistPageScaffold(
      title: 'Therapy Sessions',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select a patient to view sessions',
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
                  return ListView.builder(
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) {
                      final patient = snapshot.data![index];
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
