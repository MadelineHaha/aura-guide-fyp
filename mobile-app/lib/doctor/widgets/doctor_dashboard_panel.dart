import 'package:flutter/material.dart';

import '../../models/doctor_patient_summary.dart';
import '../../services/appointments_service.dart';
import '../../services/communication_service.dart';
import '../../services/doctor_adherence_service.dart';
import '../../services/doctor_patients_service.dart';
import '../../services/staff_profile_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/clinic_datetime.dart';
import '../pages/doctor_chat_page.dart';
import 'doctor_section_header.dart';
import 'doctor_theme.dart';

class DoctorDashboardPanel extends StatefulWidget {
  const DoctorDashboardPanel({super.key});

  @override
  State<DoctorDashboardPanel> createState() => _DoctorDashboardPanelState();
}

class _DoctorDashboardPanelState extends State<DoctorDashboardPanel> {
  final _patientsService = DoctorPatientsService();
  final _appointmentsService = AppointmentsService();
  final _adherenceService = DoctorAdherenceService();
  final _staffProfileService = StaffProfileService();
  final _communicationService = CommunicationService();

  String _adherenceRange = 'today';
  bool _loadingAlerts = false;
  List<PatientAdherenceRow> _lowAdherence = [];
  String? _contactingParticipantId;

  static const _rangeLabels = {
    'today': 'Today',
    'month': 'This Month',
    'all': 'All Time',
  };

  @override
  void initState() {
    super.initState();
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    setState(() => _loadingAlerts = true);
    try {
      final patients = await _patientsService.fetchPatients();
      final rows = await _adherenceService.loadLowAdherenceRows(
        patients,
        rangeKey: _adherenceRange,
      );
      if (mounted) {
        setState(() {
          _lowAdherence = rows;
          _loadingAlerts = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingAlerts = false);
    }
  }

  Future<void> _openContactChat(PatientAdherenceRow row) async {
    if (_contactingParticipantId != null) return;
    setState(() => _contactingParticipantId = row.contactParticipantId);
    try {
      final conversationId = await _communicationService
          .ensureConversationWithPatient(row.contactParticipantId);
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => DoctorChatPage(
            conversationId: conversationId,
            patientId: row.contactParticipantId,
            title: row.contactDisplayName,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open chat: $e')),
      );
    } finally {
      if (mounted) setState(() => _contactingParticipantId = null);
    }
  }

  int _todayAppointmentCount(List<dynamic> items) {
    final today = ClinicDateTime.clinicDayStart(ClinicDateTime.nowClinic());
    return items.where((item) {
      final dt = item.dateTime as DateTime;
      return ClinicDateTime.clinicDayStart(dt) == today;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _staffProfileService.loadCurrentProfile(),
      builder: (context, profileSnap) {
        final staffId = profileSnap.data != null
            ? StaffProfileService.staffIdFromData(profileSnap.data!)
            : null;

        return Container(
          decoration: DoctorTheme.accentCard(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const DoctorSectionHeader(
                title: 'Today at a glance',
                subtitle: 'Your patients and schedule',
              ),
              const SizedBox(height: 14),
              StreamBuilder<List<DoctorPatientSummary>>(
                stream: _patientsService.watchPatients(),
                builder: (context, patientsSnap) {
                  final count = patientsSnap.data?.length ?? 0;
                  return Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          icon: Icons.people_outline,
                          label: 'Patients',
                          value: count.toString(),
                          accent: DoctorTheme.modulePatients,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: staffId == null
                            ? _StatTile(
                                icon: Icons.calendar_today_outlined,
                                label: 'Today',
                                value: '—',
                                accent: DoctorTheme.moduleAppointments,
                              )
                            : FutureBuilder(
                                future: _appointmentsService.fetchForStaff(staffId),
                                builder: (context, apptSnap) {
                                  final items = apptSnap.data ?? [];
                                  final todayCount =
                                      _todayAppointmentCount(items);
                                  return _StatTile(
                                    icon: Icons.calendar_today_outlined,
                                    label: 'Today',
                                    value: todayCount.toString(),
                                    accent: DoctorTheme.moduleAppointments,
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Adherence alerts',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (_lowAdherence.isNotEmpty && !_loadingAlerts)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: DoctorTheme.dangerSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: DoctorTheme.dangerBorder.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        '${_lowAdherence.length}',
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _rangeLabels.entries.map((entry) {
                  final selected = _adherenceRange == entry.key;
                  return ChoiceChip(
                    label: Text(entry.value),
                    selected: selected,
                    onSelected: (_) {
                      setState(() => _adherenceRange = entry.key);
                      _loadAlerts();
                    },
                    labelStyle: TextStyle(
                      color: selected ? Colors.black : AppColors.subtext,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    selectedColor: DoctorTheme.portalAccent,
                    backgroundColor: DoctorTheme.surface,
                    side: BorderSide(
                      color: selected
                          ? DoctorTheme.portalAccent
                          : DoctorTheme.borderSoft,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              if (_loadingAlerts)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  ),
                )
              else if (_lowAdherence.isEmpty)
                _EmptyAlertsCard()
              else
                ..._lowAdherence.map(
                  (row) => _AdherenceAlertCard(
                    row: row,
                    contacting: _contactingParticipantId == row.contactParticipantId,
                    onContact: () => _openContactChat(row),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DoctorTheme.surface.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 26,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: AppColors.subtext, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EmptyAlertsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: DoctorTheme.surfaceCard(),
      child: const Row(
        children: [
          Icon(Icons.check_circle_outline, color: AppColors.accent, size: 28),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'All patients are on track — no adherence alerts.',
              style: TextStyle(color: AppColors.subtext, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _AdherenceAlertCard extends StatelessWidget {
  const _AdherenceAlertCard({
    required this.row,
    required this.contacting,
    required this.onContact,
  });

  final PatientAdherenceRow row;
  final bool contacting;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final contactLabel = row.contactIsCaregiver
        ? 'Contact Caregiver'
        : 'Contact Patient';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: DoctorTheme.dangerSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: DoctorTheme.dangerBorder.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Colors.redAccent,
              ),
            ),
            title: Text(
              row.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            subtitle: Text(
              '${row.patientId} • Low adherence',
              style: const TextStyle(color: AppColors.subtext, fontSize: 12),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${row.adherencePercent}%',
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: OutlinedButton.icon(
              onPressed: contacting ? null : onContact,
              icon: contacting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DoctorTheme.portalAccent,
                      ),
                    )
                  : const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text(contactLabel),
              style: OutlinedButton.styleFrom(
                foregroundColor: DoctorTheme.portalAccent,
                side: BorderSide(
                  color: DoctorTheme.portalAccent.withValues(alpha: 0.55),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
