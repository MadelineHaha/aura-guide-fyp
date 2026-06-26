import 'package:flutter/material.dart';

import '../../models/conversation_thread.dart';
import '../../models/doctor_patient_summary.dart';
import '../../services/communication_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/grouped_conversation_list_view.dart';
import '../../doctor/widgets/doctor_empty_state.dart';
import '../../doctor/widgets/doctor_page_scaffold.dart';
import '../../doctor/widgets/doctor_patient_list_tile.dart';
import '../../doctor/widgets/doctor_theme.dart';
import '../services/caregiver_patients_service.dart';
import 'caregiver_chat_page.dart';

class CaregiverCommunicationPage extends StatefulWidget {
  const CaregiverCommunicationPage({super.key});

  @override
  State<CaregiverCommunicationPage> createState() =>
      _CaregiverCommunicationPageState();
}

class _CaregiverCommunicationPageState extends State<CaregiverCommunicationPage> {
  final _service = CommunicationService();
  final _patientsService = CaregiverPatientsService();
  bool _showNewMessage = false;

  Future<void> _openThread(ConversationThread thread) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => CaregiverChatPage(
          conversationId: thread.conversationId,
          patientId: thread.staffId,
          title: thread.title,
        ),
      ),
    );
  }

  Future<void> _startChatWithPatient(DoctorPatientSummary patient) async {
    try {
      final conversationId =
          await _service.ensureConversationWithPatientAsCaregiver(
        patient.patientId,
      );
      if (!mounted) return;
      setState(() => _showNewMessage = false);
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => CaregiverChatPage(
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
            'Choose a connected patient to message',
            style: TextStyle(color: AppColors.subtext, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<DoctorPatientSummary>>(
              stream: _patientsService.watchConnectedPatients(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  );
                }
                final patients = snapshot.data!;
                if (patients.isEmpty) {
                  return const DoctorEmptyState(
                    icon: Icons.forum_outlined,
                    message: 'No connected patients',
                    detail: 'Link patients to your account to start messaging.',
                  );
                }
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
      stream: _service.watchThreadsForCaregiver(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        final threads = snapshot.data!;
        if (threads.isEmpty) {
          return const DoctorEmptyState(
            icon: Icons.forum_outlined,
            message: 'No conversations yet',
            detail: 'Tap + to message a connected patient.',
          );
        }
        return GroupedConversationListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          itemSpacing: 4,
          threads: threads,
          itemBuilder: (context, thread) {
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: DoctorTheme.surfaceHighlight,
                foregroundColor: DoctorTheme.portalAccent,
                child: Text(
                  thread.initials,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(
                thread.title,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: thread.unread ? FontWeight.bold : FontWeight.w600,
                ),
              ),
              subtitle: Text(
                thread.preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.subtext, fontSize: 13),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    thread.timeLabel,
                    style: const TextStyle(color: AppColors.subtext, fontSize: 12),
                  ),
                  if (thread.unread) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: DoctorTheme.portalAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
              onTap: () => _openThread(thread),
            );
          },
        );
      },
    );
  }
}
