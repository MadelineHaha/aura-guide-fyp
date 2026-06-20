/// Locale-aware doctor titles (e.g. Dr. Sarah / Sarah医生 / Doktor Sarah).
class LocalizedDoctorName {
  LocalizedDoctorName._();

  static String format(
    String rawName,
    String languageCode, {
    bool isDoctor = true,
  }) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) return trimmed;
    if (!isDoctor) return trimmed;

    final name = _baseName(trimmed);
    if (name.isEmpty) return trimmed;

    switch (languageCode) {
      case 'zh':
        return '$name医生';
      case 'ms':
        return 'Doktor $name';
      default:
        return 'Dr. $name';
    }
  }

  static String _baseName(String rawName) {
    var name = rawName.trim();

    if (name.endsWith('医生')) {
      name = name.substring(0, name.length - 2).trim();
    }

    const prefixes = ['Dr.', 'Dr ', 'Doktor ', 'Doktor. '];
    for (final prefix in prefixes) {
      if (name.startsWith(prefix)) {
        return name.substring(prefix.length).trim();
      }
    }

    return name;
  }
}
