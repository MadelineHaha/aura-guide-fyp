class NavDestination {
  const NavDestination({
    required this.label,
    required this.address,
    this.latitude,
    this.longitude,
    this.isSavedHome = false,
    this.isSavedWork = false,
  });

  final String label;
  final String address;
  final double? latitude;
  final double? longitude;
  final bool isSavedHome;
  final bool isSavedWork;

  bool get hasCoordinates => latitude != null && longitude != null;

  NavDestination copyWith({
    String? label,
    String? address,
    double? latitude,
    double? longitude,
    bool? isSavedHome,
    bool? isSavedWork,
  }) {
    return NavDestination(
      label: label ?? this.label,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isSavedHome: isSavedHome ?? this.isSavedHome,
      isSavedWork: isSavedWork ?? this.isSavedWork,
    );
  }
}
