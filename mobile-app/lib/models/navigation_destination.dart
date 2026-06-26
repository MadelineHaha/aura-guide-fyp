class NavDestination {
  const NavDestination({
    required this.label,
    required this.address,
    this.latitude,
    this.longitude,
    this.category,
    this.isSavedHome = false,
    this.isSavedWork = false,
  });

  final String label;
  final String address;
  final double? latitude;
  final double? longitude;

  /// Optional place type, e.g. "Restaurant", "Cafe", "Hospital".
  final String? category;
  final bool isSavedHome;
  final bool isSavedWork;

  bool get hasCoordinates => latitude != null && longitude != null;

  NavDestination copyWith({
    String? label,
    String? address,
    double? latitude,
    double? longitude,
    String? category,
    bool? isSavedHome,
    bool? isSavedWork,
  }) {
    return NavDestination(
      label: label ?? this.label,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      category: category ?? this.category,
      isSavedHome: isSavedHome ?? this.isSavedHome,
      isSavedWork: isSavedWork ?? this.isSavedWork,
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'address': address,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (category != null && category!.isNotEmpty) 'category': category,
        'isSavedHome': isSavedHome,
        'isSavedWork': isSavedWork,
      };

  factory NavDestination.fromJson(Map<String, dynamic> json) {
    return NavDestination(
      label: json['label'] as String? ?? '',
      address: json['address'] as String? ?? '',
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      category: json['category'] as String?,
      isSavedHome: json['isSavedHome'] as bool? ?? false,
      isSavedWork: json['isSavedWork'] as bool? ?? false,
    );
  }
}
