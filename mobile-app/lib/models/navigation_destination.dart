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

  Map<String, dynamic> toJson() => {
        'label': label,
        'address': address,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'isSavedHome': isSavedHome,
        'isSavedWork': isSavedWork,
      };

  factory NavDestination.fromJson(Map<String, dynamic> json) {
    return NavDestination(
      label: json['label'] as String? ?? '',
      address: json['address'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      isSavedHome: json['isSavedHome'] as bool? ?? false,
      isSavedWork: json['isSavedWork'] as bool? ?? false,
    );
  }
}
