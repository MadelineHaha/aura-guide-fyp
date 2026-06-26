import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/communication_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_back_button.dart';
import '../../doctor/widgets/doctor_chat_message_bubble.dart';
import '../../doctor/widgets/doctor_theme.dart';

class CaregiverChatPage extends StatefulWidget {
  const CaregiverChatPage({
    super.key,
    required this.conversationId,
    required this.patientId,
    required this.title,
  });

  final String conversationId;
  final String patientId;
  final String title;

  @override
  State<CaregiverChatPage> createState() => _CaregiverChatPageState();
}

class _CaregiverChatPageState extends State<CaregiverChatPage> {
  final _service = CommunicationService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _service.markConversationReadForCaregiver(
      conversationId: widget.conversationId,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _service.sendTextMessageAsCaregiver(
        conversationId: widget.conversationId,
        patientId: widget.patientId,
        content: text,
      );
      _controller.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Send failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: const AppBackButton(),
        title: Text(
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  DoctorTheme.portalAccent.withValues(alpha: 0.35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder(
              stream: _service.watchMessagesForCaregiver(
                conversationId: widget.conversationId,
              ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  );
                }
                final items = snapshot.data!;
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'No messages yet. Say hello!',
                      style: TextStyle(color: AppColors.subtext),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return DoctorChatMessageBubble(item: item);
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
            decoration: const BoxDecoration(
              color: Color(0xFF0C0C0C),
              border: Border(top: BorderSide(color: DoctorTheme.borderSoft)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    style: const TextStyle(color: Colors.white),
                    maxLength: 255,
                    decoration: const InputDecoration(
                      hintText: 'Type a message…',
                      hintStyle: TextStyle(color: AppColors.subtext),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send, color: DoctorTheme.portalAccent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
