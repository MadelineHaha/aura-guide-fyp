import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/app_experience_service.dart';
import '../services/app_settings_service.dart';
import '../services/voice_assistant_coordinator.dart';
import '../services/voice_flow_coordinator.dart';

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
  final _flowCoordinator = VoiceFlowCoordinator.instance;
  final _settings = AppSettingsService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppExperienceService.instance.addListener(_onExperienceChanged);
    if (AppExperienceService.instance.isPatientExperience) {
      _attachPatientVoiceUi();
    }
  }

  void _attachPatientVoiceUi() {
    _coordinator.ensureStarted();
    _coordinator.addListener(_onUiChanged);
    _flowCoordinator.addListener(_onUiChanged);
    _settings.addListener(_onUiChanged);
    _settings.isSpeakingNotifier.addListener(_onUiChanged);
  }

  void _detachPatientVoiceUi() {
    _coordinator.removeListener(_onUiChanged);
    _flowCoordinator.removeListener(_onUiChanged);
    _settings.removeListener(_onUiChanged);
    _settings.isSpeakingNotifier.removeListener(_onUiChanged);
  }

  void _onExperienceChanged() {
    if (!mounted) return;
    if (AppExperienceService.instance.isPatientExperience) {
      _attachPatientVoiceUi();
    } else {
      _detachPatientVoiceUi();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _detachPatientVoiceUi();
    AppExperienceService.instance.removeListener(_onExperienceChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onUiChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _coordinator.setAppResumed(state == AppLifecycleState.resumed);
  }

  bool _shouldShowConversationBox(bool voiceAssistantEnabled, bool voiceOnly) {
    return voiceAssistantEnabled && voiceOnly;
  }

  @override
  Widget build(BuildContext context) {
    if (!AppExperienceService.instance.isPatientExperience) {
      return widget.child;
    }

    final voiceAssistantEnabled = _settings.settings.voiceAssistantEnabled;
    final voiceOnly = _settings.settings.voiceOnlyModeEnabled;
    final showAssistantBox =
        _shouldShowConversationBox(voiceAssistantEnabled, voiceOnly);
    final blockTouches = voiceAssistantEnabled && voiceOnly;

    Widget content = widget.child;
    if (blockTouches) {
      content = AbsorbPointer(
        absorbing: true,
        child: ExcludeSemantics(excluding: true, child: content),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: content),
        if (showAssistantBox)
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: const _VoiceAssistantConversationBox(),
          ),
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
    final flow = VoiceFlowCoordinator.instance;
    final userCommand = coordinator.lastUserCommand;
    var assistantMessage = coordinator.assistantMessage;
    if (AppSettingsService.instance.isSpeakingNotifier.value) {
      assistantMessage = AppSettingsService.instance.lastSpokenText;
    } else if (assistantMessage.isEmpty) {
      if (flow.isWelcomeActive && flow.statusKey.isNotEmpty) {
        assistantMessage = AppSettingsService.instance.localized(
          flow.statusKey,
        );
      } else if (flow.isActive && flow.statusKey.isNotEmpty) {
        assistantMessage = AppSettingsService.instance.localized(
          flow.statusKey,
        );
      } else if (AppSettingsService.instance.isVoiceConversationEnabled) {
        assistantMessage = AppSettingsService.instance.localized(
          coordinator.isAwaitingCommand
              ? 'voiceAssistantListening'
              : 'voiceFlowMenuPrompt',
        );
      }
    }

    final titleKey = flow.isWelcomeActive
        ? 'welcomeVoiceTitle'
        : 'voiceAssistantSettingTitle';

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
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
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 168),
            child: SingleChildScrollView(
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
                          context.l10n.t(titleKey),
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
      ),
    );
  }
}
