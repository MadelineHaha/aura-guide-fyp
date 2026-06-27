import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/book_appointment_session.dart';
import 'app_experience_service.dart';
import 'app_settings_service.dart';
import 'voice_assistant_coordinator.dart';
import 'voice_flows/book_appointment_voice_flow.dart';
import 'voice_flows/settings_voice_flow.dart';
import 'voice_flows/welcome_voice_flow.dart';

/// Runs multi-step voice dialogues on top of the wake-word assistant.
class VoiceFlowCoordinator extends ChangeNotifier {
  VoiceFlowCoordinator._();

  static final VoiceFlowCoordinator instance = VoiceFlowCoordinator._();

  bool _active = false;
  bool _welcomeActive = false;
  int _welcomeGeneration = 0;
  String _statusKey = '';

  bool get isActive => _active;
  bool get isWelcomeActive => _welcomeActive;
  String get statusKey => _statusKey;

  Future<void> startWelcomeFlow() async {
    final loggedIn = FirebaseAuth.instance.currentUser != null;
    if (loggedIn && !AppExperienceService.instance.isPatientExperience) return;
    if (_welcomeActive || _active) return;
    if (!AppSettingsService.instance.isVoiceConversationEnabled) return;

    final generation = ++_welcomeGeneration;
    _welcomeActive = true;
    _statusKey = 'welcomeVoiceInProgress';
    notifyListeners();

    final assistant = VoiceAssistantCoordinator.instance;
    assistant.beginWelcomeSession();
    assistant.acquireMicLock();

    try {
      await WelcomeVoiceFlow(
        isCancelled: () => generation != _welcomeGeneration,
      ).run();
    } catch (error, stack) {
      if (error is! VoiceFlowCancelledException) {
        debugPrint('VoiceFlowCoordinator welcome flow failed: $error\n$stack');
      }
    } finally {
      assistant.releaseMicLock();
      assistant.endWelcomeSession();
      if (generation == _welcomeGeneration) {
        _welcomeActive = false;
        _statusKey = '';
        notifyListeners();
      }
    }
  }

  void cancelWelcomeFlow() {
    if (!_welcomeActive) return;
    _welcomeGeneration++;
    _welcomeActive = false;
    _statusKey = '';
    final assistant = VoiceAssistantCoordinator.instance;
    unawaited(assistant.cancelActiveDialog());
    assistant.endWelcomeSession();
    notifyListeners();
  }

  void cancelBookFlow() {
    if (!_active) return;
    _active = false;
    _statusKey = '';
    final assistant = VoiceAssistantCoordinator.instance;
    unawaited(assistant.cancelActiveDialog());
    assistant.releaseMicLock();
    notifyListeners();
  }

  void cancelActiveFlow() {
    if (_welcomeActive) {
      cancelWelcomeFlow();
      return;
    }
    cancelBookFlow();
  }

  Future<void> startBookAppointmentFlow() async {
    if (!AppExperienceService.instance.isPatientExperience) return;
    if (_active) return;
    if (!AppSettingsService.instance.isVoiceConversationEnabled) return;

    _active = true;
    _statusKey = 'voiceFlowBookingInProgress';
    notifyListeners();

    final session = BookAppointmentSession();
    final assistant = VoiceAssistantCoordinator.instance;
    assistant.acquireMicLock();

    try {
      openVoiceGuidedBookAppointmentPage(session);
      await BookAppointmentVoiceFlow(session).run();
    } catch (error, stack) {
      if (error is VoiceFlowCancelledException) {
        await assistant.speakPrompt('voiceFlowBookingCancelled');
      } else {
        debugPrint('VoiceFlowCoordinator book flow failed: $error\n$stack');
        await assistant.speakPrompt('voiceFlowBookingFailed');
      }
    } finally {
      assistant.releaseMicLock();
      _active = false;
      _statusKey = '';
      notifyListeners();
      assistant.resumeAfterVoiceFlow();
    }
  }

  Future<void> startSettingsFlow({bool openPage = false}) async {
    if (!AppExperienceService.instance.isPatientExperience) return;
    if (_active || _welcomeActive) return;
    if (!AppSettingsService.instance.isVoiceConversationEnabled) return;

    _active = true;
    _statusKey = 'voiceFlowSettingsInProgress';
    notifyListeners();

    final assistant = VoiceAssistantCoordinator.instance;
    assistant.acquireMicLock();

    try {
      await SettingsVoiceFlow().run(openSettingsPage: openPage);
    } catch (error, stack) {
      if (error is! VoiceFlowCancelledException) {
        debugPrint('VoiceFlowCoordinator settings flow failed: $error\n$stack');
        await assistant.speakPrompt('voiceSettingsFailed');
      }
    } finally {
      assistant.releaseMicLock();
      _active = false;
      _statusKey = '';
      notifyListeners();
      assistant.resumeAfterVoiceFlow();
    }
  }

  Future<void> handleGlobalCommand(String? command) async {
    final normalized = VoiceAssistantCoordinator.normalizeSpeech(command ?? '');
    if (normalized.isEmpty) return;

    if (_matchesBookAppointment(normalized)) {
      await startBookAppointmentFlow();
      return;
    }

    if (_matchesDisableVoiceOnly(normalized)) {
      // Handled in VoiceAssistantCoordinator settings toggle.
      return;
    }
  }

  bool _matchesBookAppointment(String normalized) {
    const phrases = [
      'book appointment',
      'book an appointment',
      'make appointment',
      'schedule appointment',
    ];
    return phrases.any(normalized.contains);
  }

  bool _matchesDisableVoiceOnly(String normalized) {
    const phrases = [
      'enable touch',
      'touch mode',
      'disable voice only',
      'turn off voice only',
    ];
    return phrases.any(normalized.contains);
  }
}
