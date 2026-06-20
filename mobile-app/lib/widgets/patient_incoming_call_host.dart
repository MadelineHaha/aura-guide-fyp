import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/communication_service.dart';
import '../services/patient_call_session.dart';
import '../services/call_ringtone_player.dart';
import '../services/voice_call_service.dart';
import 'voice_call_overlay.dart';

/// Shows incoming and active voice calls on top of any screen while signed in.
class PatientIncomingCallHost extends StatefulWidget {
  const PatientIncomingCallHost({super.key, required this.child});

  final Widget child;

  @override
  State<PatientIncomingCallHost> createState() =>
      _PatientIncomingCallHostState();
}

class _PatientIncomingCallHostState extends State<PatientIncomingCallHost> {
  final _communication = CommunicationService();
  final _session = PatientCallSession.instance;

  StreamSubscription<VoiceCallEvent>? _callStateSub;
  Timer? _callTimer;

  String? _callStatusText;
  bool _showCallTimer = false;
  bool _showCallMute = false;
  bool _callMuted = false;
  String _callTimerText = '00:00';
  String? _activeRemoteName;

  @override
  void initState() {
    super.initState();
    _session.ensureStarted();
    _callStateSub = _session.voiceCall.stateStream.listen(_onVoiceCallEvent);
    _syncFromCurrentCall();
  }

  void _syncFromCurrentCall() {
    final phase = _session.voiceCall.phase;
    if (phase == VoiceCallPhase.idle) return;
    _activeRemoteName = _session.voiceCall.remoteName;
    if (phase == VoiceCallPhase.connected) {
      _showCallTimer = true;
      _showCallMute = true;
      _startCallTimer();
    }
  }

  @override
  void dispose() {
    _callStateSub?.cancel();
    _stopCallTimer();
    super.dispose();
  }

  void _onVoiceCallEvent(VoiceCallEvent event) {
    if (!mounted) return;

    switch (event.phase) {
      case VoiceCallPhase.connecting:
        _session.ringtone.stop();
        setState(() {
          _callStatusText = context.l10n.t('voiceCallConnecting');
          _activeRemoteName = event.remoteName ?? _activeRemoteName;
          _showCallTimer = false;
          _showCallMute = false;
        });
      case VoiceCallPhase.ringing:
        unawaited(_session.ringtone.start(mode: CallRingtoneMode.outgoing));
        setState(() {
          _callStatusText = context.l10n.t('voiceCallCalling');
          _activeRemoteName = event.remoteName ?? _activeRemoteName;
          _showCallTimer = false;
          _showCallMute = false;
        });
      case VoiceCallPhase.incoming:
        setState(() {
          _callStatusText = context.l10n.t('voiceCallIncoming');
          _activeRemoteName = event.remoteName ?? _activeRemoteName;
        });
      case VoiceCallPhase.connected:
        _session.ringtone.stop();
        _startCallTimer();
        setState(() {
          _callStatusText = context.l10n.t('voiceCallConnected');
          _activeRemoteName = event.remoteName ?? _activeRemoteName;
          _showCallTimer = true;
          _showCallMute = true;
        });
      case VoiceCallPhase.ended:
        _session.ringtone.stop();
        _stopCallTimer();
        setState(() {
          _callStatusText = null;
          _activeRemoteName = null;
          _showCallTimer = false;
          _showCallMute = false;
          _callMuted = false;
        });
      case VoiceCallPhase.idle:
        break;
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    final startedAt = _session.voiceCall.connectedAt ?? DateTime.now();
    void tick() {
      if (!mounted) return;
      final elapsed =
          DateTime.now().difference(startedAt).inSeconds.clamp(0, 86400);
      final minutes = elapsed ~/ 60;
      final seconds = elapsed % 60;
      setState(() {
        _callTimerText =
            '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
      });
    }

    tick();
    _callTimer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void _stopCallTimer() {
    _callTimer?.cancel();
    _callTimer = null;
    _callTimerText = '00:00';
  }

  void _toggleCallMute() {
    final muted = _session.voiceCall.toggleMute();
    setState(() => _callMuted = muted);
  }

  bool _showCallOverlay(IncomingCallOffer? incoming) {
    final phase = _session.voiceCall.phase;
    return incoming != null || phase != VoiceCallPhase.idle;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<IncomingCallOffer?>(
      valueListenable: _session.pendingIncoming,
      builder: (context, incoming, _) {
        final showOverlay = _showCallOverlay(incoming);
        final l10n = context.l10n;
        final callPhase = _session.voiceCall.phase;

        return Stack(
          children: [
            IgnorePointer(
              ignoring: showOverlay,
              child: ExcludeSemantics(
                excluding: showOverlay,
                child: widget.child,
              ),
            ),
            if (showOverlay)
              Positioned.fill(
                child: _CallOverlayLayer(
                  incoming: incoming,
                  callPhase: callPhase,
                  activeRemoteName: _activeRemoteName,
                  callStatusText: _callStatusText,
                  showCallTimer: _showCallTimer,
                  callTimerText: _callTimerText,
                  showCallMute: _showCallMute,
                  callMuted: _callMuted,
                  communication: _communication,
                  session: _session,
                  l10n: l10n,
                  onToggleMute: _toggleCallMute,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CallOverlayLayer extends StatelessWidget {
  const _CallOverlayLayer({
    required this.incoming,
    required this.callPhase,
    required this.activeRemoteName,
    required this.callStatusText,
    required this.showCallTimer,
    required this.callTimerText,
    required this.showCallMute,
    required this.callMuted,
    required this.communication,
    required this.session,
    required this.l10n,
    required this.onToggleMute,
  });

  final IncomingCallOffer? incoming;
  final VoiceCallPhase callPhase;
  final String? activeRemoteName;
  final String? callStatusText;
  final bool showCallTimer;
  final String callTimerText;
  final bool showCallMute;
  final bool callMuted;
  final CommunicationService communication;
  final PatientCallSession session;
  final AppLocalizations l10n;
  final VoidCallback onToggleMute;

  @override
  Widget build(BuildContext context) {
    final isIncomingRinging = incoming != null && callPhase == VoiceCallPhase.idle;

    if (isIncomingRinging) {
      return FutureBuilder<String>(
        future: communication.resolveStaffDisplayName(incoming!.staffId),
        builder: (context, snapshot) {
          final remoteName = snapshot.data ?? incoming!.staffId;
          return _scopedOverlay(
            callId: incoming!.callId,
            child: VoiceCallOverlay(
              remoteName: remoteName,
              statusText: l10n.t('voiceCallIncoming'),
              hintText: l10n.t('voiceCallIncomingHint', {'name': remoteName}),
              showTimer: false,
              timerText: '00:00',
              showMute: false,
              isMuted: false,
              onToggleMute: () {},
              onEndCall: () => unawaited(session.declinePendingIncoming()),
              showAnswerActions: true,
              onAnswer: () => unawaited(session.answerPendingIncoming(context)),
              onDecline: () => unawaited(session.declinePendingIncoming()),
              answerLabel: l10n.t('voiceCallAnswer'),
              answerA11yLabel: l10n.t('voiceCallAnswerA11y'),
              declineLabel: l10n.t('voiceCallDecline'),
              declineA11yLabel: l10n.t('voiceCallDeclineA11y'),
              muteLabel: l10n.t('voiceCallMute'),
              unmuteLabel: l10n.t('voiceCallUnmute'),
              endLabel: l10n.t('voiceCallEnd'),
            ),
          );
        },
      );
    }

    final remoteName =
        activeRemoteName ?? session.voiceCall.remoteName ?? l10n.t('voiceCall');
    final statusText = callStatusText ?? l10n.t('voiceCallConnecting');

    return _scopedOverlay(
      callId: session.voiceCall.activeCallId ?? 'active',
      child: VoiceCallOverlay(
        remoteName: remoteName,
        statusText: statusText,
        showTimer: showCallTimer,
        timerText: callTimerText,
        showMute: showCallMute,
        isMuted: callMuted,
        onToggleMute: onToggleMute,
        onEndCall: () => unawaited(session.endActiveCall()),
        showAnswerActions: false,
        answerLabel: l10n.t('voiceCallAnswer'),
        answerA11yLabel: l10n.t('voiceCallAnswerA11y'),
        declineLabel: l10n.t('voiceCallDecline'),
        declineA11yLabel: l10n.t('voiceCallDeclineA11y'),
        muteLabel: l10n.t('voiceCallMute'),
        unmuteLabel: l10n.t('voiceCallUnmute'),
        endLabel: l10n.t('voiceCallEnd'),
      ),
    );
  }

  Widget _scopedOverlay({required String callId, required Widget child}) {
    return Semantics(
      key: ValueKey(callId),
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l10n.t('voiceCallA11y'),
      child: child,
    );
  }
}