class VoiceProfileData {
  const VoiceProfileData({
    required this.passphrase,
    this.voiceprintVector = const [],
    this.voiceFeatures = const {},
  });

  final String passphrase;
  final List<double> voiceprintVector;
  final Map<String, dynamic> voiceFeatures;

  bool get hasVoiceprint => voiceprintVector.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'passphrase': passphrase,
        if (voiceprintVector.isNotEmpty) 'voiceprintVector': voiceprintVector,
        if (voiceFeatures.isNotEmpty) 'voiceFeatures': voiceFeatures,
        'embeddingVersion': 1,
      };

  static VoiceProfileData? fromFirestore(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) {
      final phrase = raw.trim();
      if (phrase.isEmpty) return null;
      return VoiceProfileData(passphrase: phrase);
    }
    if (raw is! Map) return null;

    final phrase = (raw['passphrase'] as String?)?.trim() ?? '';
    if (phrase.isEmpty) return null;

    final vectorRaw = raw['voiceprintVector'];
    final vector = <double>[];
    if (vectorRaw is List) {
      for (final value in vectorRaw) {
        if (value is num) vector.add(value.toDouble());
      }
    }

    final featuresRaw = raw['voiceFeatures'];
    final features = featuresRaw is Map<String, dynamic>
        ? Map<String, dynamic>.from(featuresRaw)
        : featuresRaw is Map
            ? featuresRaw.map((key, value) => MapEntry(key.toString(), value))
            : <String, dynamic>{};

    return VoiceProfileData(
      passphrase: phrase,
      voiceprintVector: vector,
      voiceFeatures: features,
    );
  }
}
