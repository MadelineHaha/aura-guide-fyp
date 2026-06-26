import 'package:flutter/material.dart';

import '../../models/conversation_thread.dart';
import '../../models/doctor_patient_summary.dart';
import '../../services/communication_service.dart';
import '../../services/doctor_patients_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/grouped_conversation_list_view.dart';
import '../widgets/doctor_page_scaffold.dart';
import '../widgets/doctor_patient_list_tile.dart';
import 'doctor_chat_page.dart';

class DoctorCommunicationPage extends StatefulWidget {
  const DoctorCommunicationPage({super.key});

  @override
  State<DoctorCommunicationPage> createState() =>
      _DoctorCommunicationPageState();
}

class _DoctorCommunicationPageState extends State<DoctorCommunicationPage> {
  final _service = CommunicationService();
  final _patientsService = DoctorPatientsService();
  bool _showNewMessage = false;

  Future<void> _openThread(ConversationThread thread) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => DoctorChatPage(
          conversationId: thread.conversationId,
          patientId: thread.isAuraGuide
              ? CommunicationService.auraGuideSystemId
              : thread.staffId,
          title: thread.title,
          isAuraGuide: thread.isAuraGuide,
          readOnly: thread.isAuraGuide,
        ),
      ),
    );
  }

  Future<void> _startChatWithPatient(DoctorPatientSummary patient) async {
    try {
      final conversationId =
          await _service.ensureConversationWithPatient(patient.patientId);
      if (!mounted) return;
      setState(() => _showNewMessage = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => DoctorChatPage(
            conversationId: conversationId,
            patientId: patient.patientId,
            title: patient.name,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start chat: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DoctorPageScaffold(
      title: 'Communication',
      actions: [
        IconButton(
          icon: Icon(_showNewMessage ? Icons.close : Icons.add_comment_outlined),
          tooltip: _showNewMessage ? 'Close' : 'New message',
          onPressed: () => setState(() => _showNewMessage = !_showNewMessage),
        ),
      ],
      body: _showNewMessage ? _buildPatientPicker() : _buildThreadList(),
    );
  }

  Widget _buildPatientPicker() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Choose a patient to message',
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
                      onTap: () => _startChatWithPatient(patient),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThreadList() {
    return StreamBuilder<List<ConversationThread>>(
      stream: _service.watchThreadsForStaff(),
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
        final threads = snapshot.data!;
        if (threads.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'No conversations yet.',
                  style: TextStyle(color: AppColors.subtext),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => setState(() => _showNewMessage = true),
                  icon: const Icon(Icons.add_comment_outlined),
                  label: const Text('Message a patient'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            ),
          );
        }
        return GroupedConversationListView(
          padding: const EdgeInsets.all(16),
          itemSpacing: 10,
          threads: threads,
          itemBuilder: (context, thread) {
            return Card(
              color: thread.unread ? const Color(0xFF19393D) : AppColors.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: thread.unread
                      ? AppColors.accent.withValues(alpha: 0.5)
                      : thread.isAuraGuide
                          ? AppColors.accent.withValues(alpha: 0.35)
                          : AppColors.border,
                  width: 1.2,
                ),
              ),
              child: ListTile(
                onTap: () => _openThread(thread),
                leading: thread.isAuraGuide
                    ? CircleAvatar(
                        backgroundColor: const Color(0xFF1E3D40),
                        child: Icon(
                          Icons.campaign_outlined,
                          color: AppColors.accent,
                          size: 24,
                        ),
                      )
                    : CircleAvatar(
                        backgroundColor: const Color(0xFF2E2E2E),
                        child: Text(thread.initials),
                      ),
                title: Text(
                  thread.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight:
                        thread.unread ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  thread.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.subtext, fontSize: 13),
                ),
                trailing: Text(
                  thread.timeLabel,
                  style: const TextStyle(color: AppColors.subtext, fontSize: 12),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
