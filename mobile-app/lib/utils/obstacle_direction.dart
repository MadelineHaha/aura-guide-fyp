import '../models/obstacle_bounds.dart';

/// Horizontal position of a detected object in the camera frame.
enum ObstacleDirection {
  left,
  slightlyLeft,
  front,
  slightlyRight,
  right,
}

/// Maps a bounding box center to a spoken direction (left / front / right).
ObstacleDirection directionFromBounds(ObstacleBounds bounds) {
  final centerX = bounds.left + bounds.width / 2;
  if (centerX < 0.30) return ObstacleDirection.left;
  if (centerX < 0.42) return ObstacleDirection.slightlyLeft;
  if (centerX > 0.70) return ObstacleDirection.right;
  if (centerX > 0.58) return ObstacleDirection.slightlyRight;
  return ObstacleDirection.front;
}

/// Localization key for [direction].
String obstacleDirectionL10nKey(ObstacleDirection direction) {
  switch (direction) {
    case ObstacleDirection.left:
      return 'obstacleDirectionLeft';
    case ObstacleDirection.slightlyLeft:
      return 'obstacleDirectionSlightlyLeft';
    case ObstacleDirection.front:
      return 'obstacleDirectionFront';
    case ObstacleDirection.slightlyRight:
      return 'obstacleDirectionSlightlyRight';
    case ObstacleDirection.right:
      return 'obstacleDirectionRight';
  }
}
