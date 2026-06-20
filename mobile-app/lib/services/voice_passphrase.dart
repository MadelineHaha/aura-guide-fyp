import 'voice_profile_service.dart';

/// Shared passphrase used for voice register and voice login.
class VoicePassphrase {
  VoicePassphrase._();

  static const expectedNormalized = 'sign me in';

  static final VoiceProfileService _profiles = VoiceProfileService();

  static String normalize(String raw) => _profiles.normalize(raw);

  /// True when speech-to-text output matches the required passphrase.
  static bool isSignMeIn(String raw) {
    final normalized = normalize(raw);
    if (normalized.isEmpty) return false;

    if (normalized.contains('sign me in')) return true;
    if (normalized.contains('signed me in')) return true;
    if (normalized.contains('signing me in')) return true;

    final compact = normalized.replaceAll(RegExp(r'[^a-z0-9\s]'), '');
    const variants = <String>[
      'sign me in',
      'signed me in',
      'signing me in',
      'sign in',
      'signin',
      'sign me and',
    ];
    if (variants.contains(compact)) return true;

    final words = compact.split(RegExp(r'\s+'));
    if (words.contains('sign') && words.contains('me') && words.contains('in')) {
      return true;
    }

    if (RegExp(r'sign\s+me\s+in').hasMatch(compact)) return true;
    if (RegExp(r'sign\s*(me\s*)?in').hasMatch(compact)) return true;

    return false;
  }
}
