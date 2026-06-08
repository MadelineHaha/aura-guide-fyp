/// Table 4.5 — Medication entity (`medications` collection).
class MedicationEntity {
  const MedicationEntity({
    required this.medicationId,
    required this.name,
    required this.dosage,
    required this.frequency,
    required this.instructions,
    required this.startDate,
    required this.endDate,
    required this.userId,
    required this.staffId,
  });

  static final RegExp medicationIdPattern = RegExp(r'^M\d{5}$');

  final String medicationId;
  final String name;
  final String dosage;
  final String frequency;
  final String instructions;
  /// `YYYY-MM-DD`
  final String startDate;
  /// `YYYY-MM-DD`
  final String endDate;
  final String userId;
  final String staffId;

  static MedicationEntity? fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    final medicationId =
        (data['medicationId'] as String?)?.trim() ?? docId;
    if (!medicationIdPattern.hasMatch(medicationId)) return null;

    final name = (data['name'] as String?)?.trim();
    final dosage = (data['dosage'] as String?)?.trim();
    final frequency = (data['frequency'] as String?)?.trim();
    final instructions = (data['instructions'] as String?)?.trim();
    final startDate = (data['startDate'] as String?)?.trim();
    final endDate = (data['endDate'] as String?)?.trim();
    final userId = (data['userId'] as String?)?.trim() ??
        (data['userID'] as String?)?.trim() ??
        '';

    if (name == null || name.isEmpty) return null;
    if (dosage == null || dosage.isEmpty) return null;
    if (frequency == null || frequency.isEmpty) return null;
    if (instructions == null || instructions.isEmpty) return null;
    if (startDate == null || startDate.isEmpty) return null;
    if (endDate == null || endDate.isEmpty) return null;
    if (userId.isEmpty) return null;

    return MedicationEntity(
      medicationId: medicationId,
      name: name,
      dosage: dosage,
      frequency: frequency,
      instructions: instructions,
      startDate: startDate,
      endDate: endDate,
      userId: userId,
      staffId: (data['staffId'] as String?)?.trim() ??
          (data['staffID'] as String?)?.trim() ??
          '',
    );
  }

  bool isActiveOnDate(String yyyyMmDd) {
    return yyyyMmDd.compareTo(startDate) >= 0 &&
        yyyyMmDd.compareTo(endDate) <= 0;
  }
}
