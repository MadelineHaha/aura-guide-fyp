import 'package:flutter/material.dart';

import '../services/app_experience_service.dart';
import 'fall_detection_host.dart';
import 'voice_assistant_host.dart';

/// Wraps the patient-only voice assistant and fall detection hosts.
/// Staff apps (doctor, therapist, caregiver) receive [child] unchanged.
class PatientExperienceHost extends StatelessWidget {
  const PatientExperienceHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppExperienceService.instance,
      builder: (context, _) {
        if (!AppExperienceService.instance.isPatientExperience) {
          return child;
        }
        return FallDetectionHost(
          child: VoiceAssistantHost(child: child),
        );
      },
    );
  }
}
