/// Locale-aware staff titles (Doctor / Therapist / Caregiver).
class LocalizedStaffName {
  LocalizedStaffName._();

  static String format(
    String rawName,
    String languageCode, {
    String? role,
  }) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return trimmed;

    final baseName = baseNameFrom(trimmed);
    if (baseName.isEmpty) return trimmed;

    final category = _normalizeRole(role);
    if (category == null) return baseName;

    switch (languageCode) {
      case 'zh':
        return _zhFormat(baseName, category);
      case 'ms':
        return _msFormat(baseName, category);
      default:
        return _enFormat(baseName, category);
    }
  }

  static String baseNameFrom(String rawName) {
    var name = rawName.trim();

    const zhSuffixes = ['医生', '治疗师', '护理员'];
    for (final suffix in zhSuffixes) {
      if (name.endsWith(suffix) && name.length > suffix.length) {
        name = name.substring(0, name.length - suffix.length).trim();
        break;
      }
    }

    const enPrefixes = [
      'Doctor ',
      'Therapist ',
      'Caregiver ',
      'Dr. ',
      'Dr ',
      'Doktor ',
      'Doktor. ',
      'Ahli Terapi ',
      'Penjaga ',
    ];
    for (final prefix in enPrefixes) {
      if (name.startsWith(prefix)) {
        return name.substring(prefix.length).trim();
      }
    }

    return name;
  }

  static String? _normalizeRole(String? role) {
    if (role == null) return null;
    final value = role.trim().toLowerCase();
    if (value.isEmpty) return null;
    if (value == 'doctor' || value == 'dr' || value == 'physician') {
      return 'doctor';
    }
    if (value == 'therapist' || value == 'therapy') {
      return 'therapist';
    }
    if (value == 'caregiver' || value == 'nurse') {
      return 'caregiver';
    }
    return null;
  }

  static String _enFormat(String baseName, String category) {
    switch (category) {
      case 'doctor':
        return 'Doctor $baseName';
      case 'therapist':
        return 'Therapist $baseName';
      case 'caregiver':
        return 'Caregiver $baseName';
      default:
        return baseName;
    }
  }

  static String _zhFormat(String baseName, String category) {
    switch (category) {
      case 'doctor':
        return '$baseName医生';
      case 'therapist':
        return '$baseName治疗师';
      case 'caregiver':
        return '$baseName护理员';
      default:
        return baseName;
    }
  }

  static String _msFormat(String baseName, String category) {
    switch (category) {
      case 'doctor':
        return 'Doktor $baseName';
      case 'therapist':
        return 'Ahli Terapi $baseName';
      case 'caregiver':
        return 'Penjaga $baseName';
      default:
        return baseName;
    }
  }
}

/// Backward-compatible alias for older call sites.
typedef LocalizedDoctorName = LocalizedStaffName;
