import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/voice_assistant_coordinator.dart';

/// Keeps the wake-word voice assistant running while the app is in the foreground.
class VoiceAssistantHost extends StatefulWidget {
  const VoiceAssistantHost({super.key, required this.child});

  final Widget child;

  @override
  State<VoiceAssistantHost> createState() => _VoiceAssistantHostState();
}

class _VoiceAssistantHostState extends State<VoiceAssistantHost>
    with WidgetsBindingObserver {
  final _coordinator = VoiceAssistantCoordinator.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _coordinator.ensureStarted();
    _coordinator.addListener(_onCoordinatorChanged);
  }

  @override
  void dispose() {
    _coordinator.removeListener(_onCoordinatorChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onCoordinatorChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _coordinator.setAppResumed(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_coordinator.isActive) const _VoiceAssistantConversationBox(),
      ],
    );
  }
}

class _VoiceAssistantConversationBox extends StatelessWidget {
  const _VoiceAssistantConversationBox();

  static const Color _accent = Color(0xFF63C3C4);

  @override
  Widget build(BuildContext context) {
    final coordinator = VoiceAssistantCoordinator.instance;
    final userCommand = coordinator.lastUserCommand;
    final assistantMessage = coordinator.assistantMessage;

    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: SafeArea(
          minimum: const EdgeInsets.only(bottom: 12),
          child: Container(
            width: MediaQuery.sizeOf(context).width - 24,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _accent.withValues(alpha: 0.6)),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.15),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.mic, color: _accent, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.l10n.t('voiceAssistantSettingTitle'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                if (userCommand != null && userCommand.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.l10n.t('voiceAssistantYouSaid', {
                      'command': userCommand,
                    }),
                    style: const TextStyle(
                      color: Color(0xFFB0B0B0),
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ],
                if (assistantMessage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    assistantMessage,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
