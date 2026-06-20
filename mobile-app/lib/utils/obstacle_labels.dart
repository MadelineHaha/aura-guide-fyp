/// Friendly display names for YOLO obstacle classes.
class ObstacleLabels {
  ObstacleLabels._();

  static const _friendlyNames = <String, String>{
    'Bike': 'Bike',
    'Building': 'Building',
    'Car': 'Car',
    'Person': 'People',
    'Stairs': 'Stairs',
    'Traffic sign': 'Traffic sign',
    'Electrical Pole': 'Electrical pole',
    'Road': 'Road',
    'Motorcycle': 'Motorcycle',
    'Dustbin': 'Dustbin',
    'Dog': 'Dog',
    'Manhole': 'Manhole',
    'Tree': 'Tree',
    'Guard rail': 'Guard rail',
    'Pedestrian crosswalk': 'Crosswalk',
    'Truck': 'Truck',
    'Bus': 'Bus',
    'Bench': 'Bench',
    'Traffic Cone': 'Traffic cone',
    'Fire hydrant': 'Fire hydrant',
    'Teraffic Barrel': 'Traffic barrel',
    'Plant Pot': 'Plant pot',
    'Electrical Box': 'Electrical box',
    'Chair': 'Chair',
    'Bicycle Rack': 'Bicycle rack',
    'door': 'Door',
    'elevator': 'Elevator',
    'escalator': 'Escalator',
    'lift_icon': 'Lift',
    'surau_icon': 'Surau',
    'toilet_icon': 'Toilet',
    'Obstacle': 'Object',
  };

  static String friendlyName(String rawLabel) {
    final trimmed = rawLabel.trim();
    if (trimmed.isEmpty) return 'Object';
    return _friendlyNames[trimmed] ?? _prettify(trimmed);
  }

  static String detectedPhrase(String rawLabel) {
    return '${friendlyName(rawLabel)} detected';
  }

  static String _prettify(String value) {
    if (value.contains(' ')) {
      return value
          .split(' ')
          .map((part) => part.isEmpty ? part : '${part[0].toUpperCase()}${part.substring(1)}')
          .join(' ');
    }
    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}
