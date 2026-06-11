class VoiceCaptureResult {
  const VoiceCaptureResult({
    required this.phrase,
    required this.voiceprintVector,
    required this.voiceFeatures,
  });

  final String phrase;
  final List<double> voiceprintVector;
  final Map<String, dynamic> voiceFeatures;
}
