import 'dart:async';

import 'package:flutter/foundation.dart';

import 'voice_assistant_coordinator.dart';
import 'voice_flow_coordinator.dart';

/// Whether the signed-in account should use the patient voice experience
/// (wake-word assistant, voice-only mode, fall detection voice prompts).
/// Doctor, therapist, and caregiver apps are touch-only.
class AppExperienceService extends ChangeNotifier {
  AppExperienceService._();

  static final AppExperienceService instance = AppExperienceService._();

  bool _isPatientExperience = false;

  bool get isPatientExperience => _isPatientExperience;

  void setPatientExperience(bool enabled) {
    if (_isPatientExperience == enabled) return;
    _isPatientExperience = enabled;
    if (!enabled) {
      VoiceFlowCoordinator.instance.cancelWelcomeFlow();
      VoiceFlowCoordinator.instance.cancelBookFlow();
      unawaited(VoiceAssistantCoordinator.instance.stopForNonPatientApp());
    }
    notifyListeners();
  }

  void clear() {
    setPatientExperience(false);
  }
}
