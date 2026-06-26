import 'package:flutter/material.dart';

import '../../services/appointments_service.dart';
import '../../services/doctor_adherence_service.dart';
import '../../services/doctor_patients_service.dart';
import '../../services/staff_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/clinic_datetime.dart';
import '../widgets/doctor_page_scaffold.dart';

class DoctorReportsPage extends StatefulWidget {
  const DoctorReportsPage({super.key});

  @override
  State<DoctorReportsPage> createState() => _DoctorReportsPageState();
}

class _DoctorReportsPageState extends State<DoctorReportsPage> {
  final _patientsService = DoctorPatientsService();
  final _appointmentsService = AppointmentsService();
  final _adherenceService = DoctorAdherenceService();
  final _staffProfileService = StaffProfileService();

  String _range = 'month';
  bool _loading = true;
  int _totalAppointments = 0;
  int _completedAppointments = 0;
  List<PatientAdherenceRow> _lowAdherence = [];

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    setState(() => _loading = true);
    try {
      final patients = await _patientsService.fetchPatients();
      final profile = await _staffProfileService.loadCurrentProfile();
      final staffId = profile != null
          ? StaffProfileService.staffIdFromData(profile)
          : null;

      var appointments = <dynamic>[];
      if (staffId != null) {
        appointments = await _appointmentsService.fetchForStaff(staffId);
      }

      final now = ClinicDateTime.nowClinic();
      final filtered = appointments.where((a) {
        final dt = a.dateTime as DateTime;
        switch (_range) {
          case 'today':
            return ClinicDateTime.clinicDayStart(dt) ==
                ClinicDateTime.clinicDayStart(now);
          case 'month':
            return dt.year == now.year && dt.month == now.month;
          default:
            return true;
        }
      }).toList();

      final lowRows = await _adherenceService.loadLowAdherenceRows(
        patients,
        rangeKey: _range,
      );

      if (mounted) {
        setState(() {
          _totalAppointments = filtered.length;
          _completedAppointments = filtered
              .where(
                (a) =>
                    (a.status as String).trim().toLowerCase() == 'completed',
              )
              .length;
          _lowAdherence = lowRows;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DoctorPageScaffold(
      title: 'Reports',
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Report Period',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      DropdownButton<String>(
                        value: _range,
                        dropdownColor: AppColors.card,
                        style: const TextStyle(color: Colors.white),
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 'today', child: Text('Today')),
                          DropdownMenuItem(
                            value: 'month',
                            child: Text('This Month'),
                          ),
                          DropdownMenuItem(value: 'all', child: Text('All Time')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _range = value);
                          _loadReport();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _ReportStatCard(
                    title: 'Total Appointments',
                    value: _totalAppointments.toString(),
                  ),
                  const SizedBox(height: 10),
                  _ReportStatCard(
                    title: 'Completed Appointments',
                    value: _completedAppointments.toString(),
                  ),
                  const SizedBox(height: 10),
                  _ReportStatCard(
                    title: 'Low Adherence Patients',
                    value: _lowAdherence.length.toString(),
                    accent: Colors.redAccent,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Patients with Low Medication Adherence (< 100%)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_lowAdherence.isEmpty)
                    const Text(
                      'No low-adherence patients for this period.',
                      style: TextStyle(color: AppColors.subtext),
                    )
                  else
                    ..._lowAdherence.map(
                      (row) => Card(
                        color: const Color(0xFF2A1515),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: Colors.red.withOpacity(0.35),
                          ),
                        ),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(
                            row.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            row.patientId,
                            style: const TextStyle(color: AppColors.subtext),
                          ),
                          trailing: Text(
                            '${row.adherencePercent}%',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _ReportStatCard extends StatelessWidget {
  const _ReportStatCard({
    required this.title,
    required this.value,
    this.accent,
  });

  final String title;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: AppColors.subtext, fontSize: 14),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: accent ?? AppColors.accent,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }
}
