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
/// Uses preview-oriented coordinates so speech matches what the user sees.
ObstacleDirection directionFromBounds(
  ObstacleBounds bounds, {
  bool? rotateForPortrait,
}) {
  final centerX = bounds.displayCenterX(rotateForPortrait: rotateForPortrait);
  if (centerX < 0.28) return ObstacleDirection.left;
  if (centerX < 0.40) return ObstacleDirection.slightlyLeft;
  if (centerX > 0.72) return ObstacleDirection.right;
  if (centerX > 0.60) return ObstacleDirection.slightlyRight;
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
