import 'package:cloud_firestore/cloud_firestore.dart';

/// App user profile aligned with the User entity specification.
///
/// Age is derived from [birthDate] via [computeAge] — it is not stored, so it
/// stays correct over time without manual updates.
///
/// [password] is never stored in Firestore; authentication uses Firebase Auth.
class UserEntity {
  UserEntity({
    required this.userId,
    required this.name,
    required this.birthDate,
    required this.email,
    this.voiceProfile = '',
    this.emergencyContact = '',
    this.accessibilityPreferences = '',
    this.status = UserStatus.active,
  });

  /// Format `UNNNNN` (e.g. U00001), max length 6.
  final String userId;
  final String name;

  /// Calendar date of birth (date-only; time ignored for age math).
  final DateTime birthDate;
  final String email;
  final String voiceProfile;
  final String emergencyContact;
  final String accessibilityPreferences;
  final UserStatus status;

  static const String collection = 'users';
  static const String counterDocPath = 'system/userCounter';

  /// Normalizes to UTC midnight for stable Firestore storage.
  static DateTime dateOnlyUtc(DateTime d) =>
      DateTime.utc(d.year, d.month, d.day);

  /// Current age in full years, as of [referenceDate] (default: now).
  static int computeAge(DateTime birthDate, {DateTime? referenceDate}) {
    final ref = referenceDate ?? DateTime.now();
    var age = ref.year - birthDate.year;
    if (ref.month < birthDate.month ||
        (ref.month == birthDate.month && ref.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'name': name,
      'birthDate': Timestamp.fromDate(dateOnlyUtc(birthDate)),
      'email': email,
      'voiceProfile': voiceProfile,
      'emergencyContact': emergencyContact,
      'accessibilityPreferences': accessibilityPreferences,
      'status': status == UserStatus.active ? 'Active' : 'Inactive',
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}

enum UserStatus {
  active,
  inactive,
}
