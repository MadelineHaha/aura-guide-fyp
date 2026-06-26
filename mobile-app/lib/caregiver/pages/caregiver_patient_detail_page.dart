import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/emergency_alert_entity.dart';
import '../../theme/app_colors.dart';
import '../../doctor/widgets/doctor_page_scaffold.dart';
import '../../doctor/widgets/doctor_theme.dart';
import '../services/caregiver_emergency_service.dart';

class CaregiverPatientDetailPage extends StatefulWidget {
  const CaregiverPatientDetailPage({
    super.key,
    required this.patientUid,
    required this.patientId,
    required this.patientName,
  });

  final String patientUid;
  final String patientId;
  final String patientName;

  @override
  State<CaregiverPatientDetailPage> createState() =>
      _CaregiverPatientDetailPageState();
}

class _CaregiverPatientDetailPageState extends State<CaregiverPatientDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _emergencyService = CaregiverEmergencyService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _resolveAlert(String docId) async {
    try {
      await _emergencyService.resolveAlert(docId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alert marked as resolved.')),
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
    return DoctorPageScaffold(
      title: widget.patientName,
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            indicatorColor: DoctorTheme.portalAccent,
            labelColor: DoctorTheme.portalAccent,
            unselectedLabelColor: AppColors.subtext,
            tabs: const [
              Tab(text: 'Alerts'),
              Tab(text: 'Adherence'),
              Tab(text: 'Reminders'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAlertsTab(),
                _buildAdherenceTab(),
                _buildRemindersTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertsTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('emergencyalerts')
          .where('UserID', isEqualTo: widget.patientId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No emergency alerts found.',
              style: TextStyle(color: AppColors.subtext),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final doc = docs[index];
            final entity =
                EmergencyAlertEntity.fromFirestore(doc.id, doc.data());
            if (entity == null) return const SizedBox.shrink();
            final isActive = entity.isOpen;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isActive
                      ? DoctorTheme.dangerSurface
                      : DoctorTheme.surfaceElevated,
                  borderRadius: DoctorTheme.cardRadius,
                  border: Border.all(
                    color: isActive
                        ? DoctorTheme.dangerBorder
                        : DoctorTheme.borderSoft,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${entity.alertType} (${entity.alertId})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Time: ${entity.dateTime}',
                      style: const TextStyle(color: AppColors.subtext, fontSize: 13),
                    ),
                    Text(
                      'Location: ${entity.location}',
                      style: const TextStyle(color: AppColors.subtext, fontSize: 13),
                    ),
                    if (isActive) ...[
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => _resolveAlert(doc.id),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Mark as Resolved'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                        ),
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
  }

  Widget _buildAdherenceTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('medicationreminders')
          .where('userId', isEqualTo: widget.patientId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No medication schedule found.',
              style: TextStyle(color: AppColors.subtext),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final medName =
                data['medicationName']?.toString() ?? 'Medication';
            final time = data['reminderTime']?.toString() ?? '—';
            final date = data['doseDate']?.toString() ?? '—';
            final taken = (data['taken'] as bool?) ?? false;

            return ListTile(
              tileColor: DoctorTheme.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: DoctorTheme.tileRadius,
                side: const BorderSide(color: DoctorTheme.borderSoft),
              ),
              title: Text(
                medName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'Time: $time  •  Date: $date',
                style: const TextStyle(color: AppColors.subtext, fontSize: 13),
              ),
              trailing: Icon(
                taken ? Icons.check_circle : Icons.cancel,
                color: taken ? Colors.green : Colors.red,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRemindersTab() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('appointments')
          .where('userId', isEqualTo: widget.patientId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No upcoming appointment reminders.',
              style: TextStyle(color: AppColors.subtext),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final type = data['appointmentType']?.toString() ?? 'Appointment';
            final status = data['status']?.toString() ?? 'Scheduled';
            final time = (data['dateTime'] as Timestamp?)?.toDate();
            final timeStr = time != null
                ? '${time.day}/${time.month}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}'
                : '—';

            return ListTile(
              leading: const Icon(Icons.notifications_active, color: Colors.orange),
              tileColor: DoctorTheme.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: DoctorTheme.tileRadius,
                side: const BorderSide(color: DoctorTheme.borderSoft),
              ),
              title: Text(
                type,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                'Date: $timeStr  •  Status: $status',
                style: const TextStyle(color: AppColors.subtext, fontSize: 13),
              ),
            );
          },
        );
      },
    );
  }
}
