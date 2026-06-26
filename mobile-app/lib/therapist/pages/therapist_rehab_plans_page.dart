import 'package:flutter/material.dart';

import '../../doctor/widgets/doctor_patient_list_tile.dart';
import '../../models/doctor_patient_summary.dart';
import '../../models/therapy_session_item.dart';
import '../../services/doctor_patients_service.dart';
import '../../services/staff_profile_service.dart';
import '../../services/therapy_sessions_service.dart';
import '../../theme/app_colors.dart';
import '../widgets/therapist_page_scaffold.dart';

class TherapistRehabPlansPage extends StatefulWidget {
  const TherapistRehabPlansPage({super.key});

  @override
  State<TherapistRehabPlansPage> createState() =>
      _TherapistRehabPlansPageState();
}

class _TherapistRehabPlansPageState extends State<TherapistRehabPlansPage> {
  final _patientsService = DoctorPatientsService();
  final _sessionsService = TherapySessionsService();
  DoctorPatientSummary? _selectedPatient;

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _openCreatePlanSheet() async {
    final patients = await _patientsService.fetchPatients();
    if (!mounted) return;

    DoctorPatientSummary? patient = _selectedPatient;
    var weeks = 4;
    var startDate = DateTime.now().add(const Duration(days: 1));
    final notesController = TextEditingController();
    final milestoneControllers =
        List.generate(weeks, (i) => TextEditingController());

    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void syncMilestones(int count) {
              while (milestoneControllers.length < count) {
                milestoneControllers.add(TextEditingController());
              }
              while (milestoneControllers.length > count) {
                milestoneControllers.removeLast().dispose();
              }
            }

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
                      'Create Rehab Plan',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: patient?.patientId,
                      dropdownColor: AppColors.card,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Patient',
                        labelStyle: TextStyle(color: AppColors.subtext),
                        border: OutlineInputBorder(),
                      ),
                      items: patients
                          .map(
                            (p) => DropdownMenuItem(
                              value: p.patientId,
                              child: Text('${p.name} (${p.patientId})'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setModalState(() {
                          patient = patients.firstWhere(
                            (p) => p.patientId == v,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Start date',
                        style: TextStyle(color: AppColors.subtext),
                      ),
                      subtitle: Text(
                        '${startDate.day}/${startDate.month}/${startDate.year}',
                        style: const TextStyle(color: Colors.white),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.calendar_month,
                            color: AppColors.accent),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: startDate,
                            firstDate: DateTime.now(),
                            lastDate:
                                DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setModalState(() => startDate = picked);
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Plan duration (weeks)',
                        labelStyle: TextStyle(color: AppColors.subtext),
                        border: OutlineInputBorder(),
                      ),
                      controller: TextEditingController(text: '$weeks'),
                      onChanged: (v) {
                        final parsed = int.tryParse(v) ?? 4;
                        final clamped = parsed.clamp(1, 12);
                        setModalState(() {
                          weeks = clamped;
                          syncMilestones(clamped);
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(weeks, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: TextField(
                          controller: milestoneControllers[i],
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Week ${i + 1} milestone',
                            labelStyle: const TextStyle(color: AppColors.subtext),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Plan notes (optional)',
                        labelStyle: TextStyle(color: AppColors.subtext),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Create plan'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    final notes = notesController.text.trim();
    final milestones = milestoneControllers.map((c) => c.text).toList();
    notesController.dispose();
    for (final c in milestoneControllers) {
      c.dispose();
    }

    if (created != true || patient == null || !mounted) return;

    final staffId = await StaffProfileService().currentStaffId();
    if (staffId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Staff profile not found.')),
      );
      return;
    }

    try {
      await _sessionsService.createRehabPlan(
        patientId: patient!.patientId,
        staffId: staffId,
        startDate: startDate,
        weeks: weeks,
        milestoneNames: milestones,
        notes: notes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rehab plan created.')),
        );
        setState(() => _selectedPatient = patient);
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
        body: StreamBuilder<List<TherapySessionItem>>(
          stream: _sessionsService.watchForPatient(_selectedPatient!.patientId),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.accent),
              );
            }
            final planned =
                snapshot.data!.where((s) => s.isPlanned).toList();
            if (planned.isEmpty) {
              return const Center(
                child: Text(
                  'No upcoming rehab plan sessions.',
                  style: TextStyle(color: AppColors.subtext),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: planned.length,
              itemBuilder: (context, index) {
                final session = planned[index];
                return Card(
                  color: const Color(0xFF263913),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: const Color(0xFF9DDC3D).withValues(alpha: 0.4),
                    ),
                  ),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const Icon(
                      Icons.event_note,
                      color: Color(0xFF9DDC3D),
                    ),
                    title: Text(
                      session.sessionName.isNotEmpty
                          ? session.sessionName
                          : 'Planned Session',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${_formatDateTime(session.dateTime)} • ${session.status}',
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

    return TherapistPageScaffold(
      title: 'Rehab Plans',
      actions: [
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Create plan',
          onPressed: _openCreatePlanSheet,
        ),
      ],
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Select a patient to view planned sessions',
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
