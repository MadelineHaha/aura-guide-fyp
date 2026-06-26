import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/staff_profile_service.dart';
import '../../theme/app_colors.dart';

class DoctorPatientDetailPage extends StatefulWidget {
  const DoctorPatientDetailPage({
    super.key,
    required this.patientUid,
    required this.patientId,
    required this.patientName,
  });

  final String patientUid;
  final String patientId;
  final String patientName;

  @override
  State<DoctorPatientDetailPage> createState() =>
      _DoctorPatientDetailPageState();
}

class _DoctorPatientDetailPageState extends State<DoctorPatientDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String? _staffId;

  final _medNameController = TextEditingController();
  final _dosageController = TextEditingController();
  String _frequency = 'Once daily';
  final _instructionsController = TextEditingController();
  final _daysController = TextEditingController();

  final _diagTitleController = TextEditingController();
  String _recordType = 'Diagnosis Report';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadStaffId();
  }

  Future<void> _loadStaffId() async {
    final id = await StaffProfileService().currentStaffId();
    if (mounted) setState(() => _staffId = id);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _medNameController.dispose();
    _dosageController.dispose();
    _instructionsController.dispose();
    _daysController.dispose();
    _diagTitleController.dispose();
    super.dispose();
  }

  Future<void> _prescribeMedication() async {
    final name = _medNameController.text.trim();
    final dosage = _dosageController.text.trim();
    final instructions = _instructionsController.text.trim();
    final daysStr = _daysController.text.trim();

    if (name.isEmpty ||
        dosage.isEmpty ||
        instructions.isEmpty ||
        daysStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all prescription fields.')),
      );
      return;
    }

    final days = int.tryParse(daysStr);
    if (days == null || days <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid number of days.')),
      );
      return;
    }

    final staffId = _staffId ??
        StaffProfileService.staffIdFromData(
          await StaffProfileService().loadCurrentProfile() ?? {},
        ) ??
        FirebaseAuth.instance.currentUser?.uid ??
        '';

    try {
      final now = DateTime.now();
      final end = now.add(Duration(days: days));
      final startDateStr =
          "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final endDateStr =
          "${end.year}-${end.month.toString().padLeft(2, '0')}-${end.day.toString().padLeft(2, '0')}";

      final counterRef =
          FirebaseFirestore.instance.doc('system/medicationCounter');
      final medicationsColl =
          FirebaseFirestore.instance.collection('medications');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final counterSnap = await transaction.get(counterRef);
        final next = counterSnap.exists
            ? (counterSnap.data()?['next'] as num?)?.toInt() ?? 1
            : 1;
        final medId = 'M${next.toString().padLeft(5, '0')}';
        final medDocRef = medicationsColl.doc(medId);

        transaction.set(counterRef, {'next': next + 1}, SetOptions(merge: true));
        transaction.set(medDocRef, {
          'medicationId': medId,
          'name': name,
          'dosage': dosage,
          'frequency': _frequency,
          'instructions': instructions,
          'startDate': startDateStr,
          'endDate': endDateStr,
          'userId': widget.patientId,
          'staffId': staffId,
          'status': 'Active',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      _medNameController.clear();
      _dosageController.clear();
      _instructionsController.clear();
      _daysController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Prescription added successfully.')),
        );
        _tabController.animateTo(0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _uploadDiagnosis() async {
    final title = _diagTitleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter report title/summary.')),
      );
      return;
    }

    final staffId = _staffId ??
        StaffProfileService.staffIdFromData(
          await StaffProfileService().loadCurrentProfile() ?? {},
        ) ??
        FirebaseAuth.instance.currentUser?.uid ??
        '';

    try {
      final now = DateTime.now();
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final dateStr = "${now.day} ${months[now.month - 1]} ${now.year}";

      final counterRef =
          FirebaseFirestore.instance.doc('system/healthRecordCounter');
      final healthRecordsColl =
          FirebaseFirestore.instance.collection('healthrecords');

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final counterSnap = await transaction.get(counterRef);
        final next = counterSnap.exists
            ? (counterSnap.data()?['next'] as num?)?.toInt() ?? 1
            : 1;
        final recordId = 'H${next.toString().padLeft(5, '0')}';
        final recordDocRef = healthRecordsColl.doc(recordId);

        transaction.set(counterRef, {'next': next + 1}, SetOptions(merge: true));
        transaction.set(recordDocRef, {
          'recordId': recordId,
          'recordType': _recordType,
          'dateCreated': dateStr,
          'title': title,
          'userId': widget.patientId,
          'staffId': staffId,
          'fileType': 'report',
          'filePath': '',
          'fileStorage': 'firestore',
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      _diagTitleController.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Diagnosis report saved.')),
        );
        _tabController.animateTo(1);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        title: Text(widget.patientName),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.accent,
          labelColor: AppColors.accent,
          unselectedLabelColor: AppColors.subtext,
          tabs: const [
            Tab(text: 'Adherence'),
            Tab(text: 'Records'),
            Tab(text: 'Prescribe'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildAdherenceTab(),
          _buildRecordsTab(),
          _buildPrescribeTab(),
          _buildHistoryTab(),
        ],
      ),
    );
  }

  Widget _buildAdherenceTab() {
    return StreamBuilder<QuerySnapshot>(
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
            final data = docs[index].data() as Map<String, dynamic>;
            final medName =
                data['medicationName']?.toString() ?? 'Medication';
            final time = data['reminderTime']?.toString() ?? '—';
            final date = data['doseDate']?.toString() ?? '—';
            final taken = (data['taken'] as bool?) ?? false;

            return Card(
              color: AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: taken
                      ? Colors.green.withOpacity(0.4)
                      : Colors.red.withOpacity(0.4),
                  width: 1.2,
                ),
              ),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(
                  medName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  'Date: $date  •  Time: $time',
                  style: const TextStyle(color: AppColors.subtext, fontSize: 13),
                ),
                trailing: Chip(
                  label: Text(
                    taken ? 'Taken' : 'Missed',
                    style: const TextStyle(color: Colors.white),
                  ),
                  backgroundColor: taken ? Colors.green : Colors.red,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRecordsTab() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('healthrecords')
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
                    'No diagnosis reports found.',
                    style: TextStyle(color: AppColors.subtext),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final title = data['title']?.toString() ?? 'No Summary';
                  final type = data['recordType']?.toString() ?? 'Report';
                  final date = data['dateCreated']?.toString() ?? '—';

                  return Card(
                    color: AppColors.card,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: AppColors.border, width: 1.2),
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      title: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        '$type  •  $date',
                        style: const TextStyle(
                          color: AppColors.subtext,
                          fontSize: 13,
                        ),
                      ),
                      leading: const Icon(Icons.description, color: AppColors.accent),
                    ),
                  );
                },
              );
            },
          ),
        ),
        _buildUploadPanel(),
      ],
    );
  }

  Widget _buildUploadPanel() {
    return Container(
      color: const Color(0xFF0C0C0C),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Upload Diagnosis Report',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _recordType,
            dropdownColor: AppColors.card,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Report Type',
              labelStyle: TextStyle(color: AppColors.subtext),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'Diagnosis Report',
                child: Text('Diagnosis'),
              ),
              DropdownMenuItem(value: 'Lab Result', child: Text('Lab Result')),
              DropdownMenuItem(
                value: 'Prescription Detail',
                child: Text('Rx Detail'),
              ),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _recordType = v);
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _diagTitleController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Diagnosis summary (e.g. Minor viral infection)',
              hintStyle: TextStyle(color: AppColors.subtext),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _uploadDiagnosis,
            icon: const Icon(Icons.upload_file),
            label: const Text('Save Report'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
          ),
        ],
      ),
    );
  }

  Widget _buildPrescribeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Prescribe New Medication',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _medNameController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Medication Name',
              labelStyle: TextStyle(color: AppColors.subtext),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _dosageController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Dosage (e.g. 500mg, 1 Capsule)',
              labelStyle: TextStyle(color: AppColors.subtext),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _frequency,
            dropdownColor: AppColors.card,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Frequency',
              labelStyle: TextStyle(color: AppColors.subtext),
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Once daily', child: Text('Once daily')),
              DropdownMenuItem(value: 'Twice daily', child: Text('Twice daily')),
              DropdownMenuItem(
                value: 'Three times daily',
                child: Text('Three times daily'),
              ),
              DropdownMenuItem(value: 'Weekly', child: Text('Weekly')),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _frequency = v);
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _instructionsController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Instructions (e.g. Take after meal)',
              labelStyle: TextStyle(color: AppColors.subtext),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _daysController,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Duration (Days)',
              labelStyle: TextStyle(color: AppColors.subtext),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _prescribeMedication,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Confirm Prescription'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    return StreamBuilder<QuerySnapshot>(
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
              'No appointments on history.',
              style: TextStyle(color: AppColors.subtext),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final type = data['appointmentType']?.toString() ?? 'Check-up';
            final status = data['status']?.toString() ?? 'Scheduled';
            final time = (data['dateTime'] as Timestamp?)?.toDate();
            final timeStr = time != null
                ? "${time.day}/${time.month}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}"
                : '—';

            return Card(
              color: AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppColors.border, width: 1.2),
              ),
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                title: Text(
                  type,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  'Time: $timeStr  •  Status: $status',
                  style: const TextStyle(color: AppColors.subtext, fontSize: 13),
                ),
                leading: const Icon(Icons.event, color: AppColors.accent),
              ),
            );
          },
        );
      },
    );
  }
}
