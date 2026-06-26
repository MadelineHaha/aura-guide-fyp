/// Voice capture from speaking a 4-digit onboarding PIN.
class VoicePinCaptureResult {
  const VoicePinCaptureResult({
    required this.pin,
    required this.voiceprintVector,
    required this.voiceFeatures,
  });

  final String pin;
  final List<double> voiceprintVector;
  final Map<String, dynamic> voiceFeatures;
}
