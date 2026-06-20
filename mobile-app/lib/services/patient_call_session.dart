import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'call_ringtone_player.dart';
import 'communication_service.dart';
import 'device_permissions_service.dart';
import 'voice_call_service.dart';

/// App-wide patient voice-call session (incoming watcher + shared WebRTC).
class PatientCallSession {
  PatientCallSession._();

  static final PatientCallSession instance = PatientCallSession._();

  final VoiceCallService voiceCall = VoiceCallService();
  final CallRingtonePlayer ringtone = CallRingtonePlayer();
  final CommunicationService communication = CommunicationService();

  final ValueNotifier<IncomingCallOffer?> pendingIncoming =
      ValueNotifier<IncomingCallOffer?>(null);

  StreamSubscription<User?>? _authSub;
  StreamSubscription<IncomingCallOffer?>? _incomingSub;
  StreamSubscription<VoiceCallEvent>? _callStateSub;

  String? _logConversationId;
  String? _logStaffId;
  bool _patientInitiatedCall = false;

  void ensureStarted() {
    if (_authSub != null) return;
    _callStateSub ??= voiceCall.stateStream.listen(_onVoiceCallState);
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        unawaited(_restartIncomingWatcher());
      } else {
        unawaited(_stopIncomingWatcher());
      }
    });
    if (FirebaseAuth.instance.currentUser != null) {
      unawaited(_restartIncomingWatcher());
    }
  }

  Future<void> _restartIncomingWatcher() async {
    final patientId = await communication.currentPatientUserId();
    if (patientId == null) return;

    await _incomingSub?.cancel();
    _incomingSub = voiceCall
        .watchIncomingRingingCall(patientId: patientId)
        .listen((incoming) async {
      if (incoming == null) {
        if (pendingIncoming.value != null) {
          pendingIncoming.value = null;
          await ringtone.stop();
        }
        return;
      }

      if (voiceCall.phase != VoiceCallPhase.idle) return;
      pendingIncoming.value = incoming;
      await ringtone.start(mode: CallRingtoneMode.incoming);
    });
  }

  Future<void> _stopIncomingWatcher() async {
    await _incomingSub?.cancel();
    _incomingSub = null;
    pendingIncoming.value = null;
    await ringtone.stop();
    if (voiceCall.phase != VoiceCallPhase.idle) {
      await voiceCall.hangUp(reason: 'ended', skipRemoteUpdate: true);
    }
  }

  Future<void> declinePendingIncoming() async {
    final incoming = pendingIncoming.value;
    if (incoming == null) return;
    await ringtone.stop();
    pendingIncoming.value = null;
    await voiceCall.declineIncoming(incoming.callId);
  }

  Future<void> answerPendingIncoming(BuildContext context) async {
    final incoming = pendingIncoming.value;
    if (incoming == null) return;

    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
    if (!micGranted) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('microphonePermissionRequired'))),
        );
      }
      return;
    }

    final patientId = await communication.currentPatientUserId();
    if (patientId == null) return;

    final remoteName =
        await communication.resolveStaffDisplayName(incoming.staffId);
    await ringtone.stop();

    try {
      await voiceCall.answerIncoming(
        incoming: incoming,
        patientId: patientId,
        remoteName: remoteName,
      );
    } catch (error) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('voiceCallFailed'))),
        );
      }
      rethrow;
    } finally {
      pendingIncoming.value = null;
    }
  }

  Future<void> endActiveCall() async {
    await ringtone.stop();
    final wasConnected = voiceCall.connectedAt != null;
    await voiceCall.hangUp(
      reason: wasConnected ? 'ended' : 'unanswered',
    );
  }

  Future<void> startOutgoingToStaff({
    required BuildContext context,
    required String staffId,
    required String remoteName,
  }) async {
    if (voiceCall.phase != VoiceCallPhase.idle) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('voiceCallNotAvailable'))),
        );
      }
      return;
    }

    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
    if (!micGranted) {
      if (context.mounted) {
        final l10n = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.t('microphonePermissionRequired'))),
        );
      }
      return;
    }

    final patientId = await communication.currentPatientUserId();
    if (patientId == null) return;

    final conversationId =
        await communication.ensureConversationWithStaff(staffId);

    _patientInitiatedCall = true;
    _logConversationId = conversationId;
    _logStaffId = staffId;

    try {
      await voiceCall.startOutgoing(
        conversationId: conversationId,
        staffId: staffId,
        patientId: patientId,
        remoteName: remoteName,
      );
    } catch (error) {
      _clearPatientInitiatedLogging();
      rethrow;
    }
  }

  void _onVoiceCallState(VoiceCallEvent event) {
    if (event.phase != VoiceCallPhase.ended) return;

    final shouldLog = _patientInitiatedCall;
    final conversationId = _logConversationId;
    final staffId = _logStaffId;
    _clearPatientInitiatedLogging();

    if (!shouldLog ||
        event.reason == 'failed' ||
        conversationId == null ||
        staffId == null) {
      return;
    }

    unawaited(
      communication.sendCallMessage(
        conversationId: conversationId,
        staffId: staffId,
        durationSeconds: event.durationSeconds,
        status: _resolveCallLogStatus(event.reason ?? 'ended', event.wasConnected),
      ),
    );
  }

  void _clearPatientInitiatedLogging() {
    _patientInitiatedCall = false;
    _logConversationId = null;
    _logStaffId = null;
  }

  String _resolveCallLogStatus(String reason, bool wasConnected) {
    if (reason == 'declined') return 'declined';
    if (reason == 'missed' || reason == 'unanswered') return 'unanswered';
    if (!wasConnected) return 'unanswered';
    return 'completed';
  }

  Future<void> disposeOnSignOut() async {
    await _callStateSub?.cancel();
    _callStateSub = null;
    await _authSub?.cancel();
    _authSub = null;
    await _stopIncomingWatcher();
    await ringtone.dispose();
    await voiceCall.dispose();
  }
}
