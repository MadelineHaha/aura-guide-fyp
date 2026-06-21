import '../utils/localized_staff_name.dart';

class StaffOption {
  StaffOption({
    required this.staffId,
    required this.name,
    required this.specialty,
    required this.category,
    required this.roleLabel,
    this.rating = 4.8,
    this.location = 'Clinic — main building',
  });

  final String staffId;
  final String name;
  /// e.g. Ophthalmology, Neurology (from `specialty` / `department` in Firestore).
  final String specialty;
  /// doctor | therapist | caregiver (from `role` in Firestore).
  final String category;
  /// e.g. Doctor, Therapist, Caregiver.
  final String roleLabel;
  final double rating;
  final String location;

  String get displayName => localizedDisplayName('en');

  String localizedDisplayName(String languageCode) {
    return LocalizedStaffName.format(
      name,
      languageCode,
      role: roleLabel,
    );
  }

  String get initials {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.map((p) => p[0]).take(2).join();
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }
}
