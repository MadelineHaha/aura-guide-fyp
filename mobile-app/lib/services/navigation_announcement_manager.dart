import 'package:geolocator/geolocator.dart';

import '../models/navigation_destination.dart';
import '../models/walking_route.dart';
import '../navigation/turn_instruction_generator.dart';
import 'app_settings_service.dart';
import 'navigation_voice_service.dart';

/// Speaks prompts for the exact [WalkingRoute] shown in AR navigation.
class NavigationAnnouncementManager {
  NavigationAnnouncementManager({
    NavigationVoiceService? voiceService,
    TurnInstructionGenerator? turnGenerator,
  })  : _voice = voiceService ?? NavigationVoiceService.instance,
        _turnGenerator = turnGenerator ?? const TurnInstructionGenerator();

  final NavigationVoiceService _voice;
  final TurnInstructionGenerator _turnGenerator;
  final _settings = AppSettingsService.instance;

  WalkingRoute? _activeRoute;
  List<RoutePoint> _routePoints = const [];
  List<WalkStep> _walkSteps = const [];
  List<RouteVoiceManeuver> _voiceManeuvers = const [];
  final _announcedMilestones = <String>{};
  var _hasAnnouncedArrival = false;
  var _obstacleActive = false;
  String? _lastObstacleKey;

  static const _arrivalDistanceMeters = 5.0;
  static const _announce50Meters = 50.0;
  static const _announce20Meters = 20.0;
  static const _announceNowMeters = 5.0;

  Future<void> initialize() async {
    await _voice.initialize();
  }

  /// Binds voice prompts to the same pedestrian route used for AR arrows.
  void prepareRoute(WalkingRoute? route) {
    _activeRoute = route;
    _routePoints = route?.points ?? const [];
    _walkSteps = route?.steps ?? const [];
    _voiceManeuvers =
        route == null ? const [] : _turnGenerator.generateFromWalkRoute(route);
    resetSession();
  }

  void resetSession() {
    _announcedMilestones.clear();
    _hasAnnouncedArrival = false;
    _obstacleActive = false;
    _lastObstacleKey = null;
    _voice.clearDuplicateGuard();
  }

  Future<void> updateNavigation({
    required Position position,
    required NavDestination destination,
    required double distanceRemaining,
    required int closestRouteIndex,
    required int currentStepIndex,
    required bool walkMode,
  }) async {
    await _voice.initialize();

    if (distanceRemaining <= _arrivalDistanceMeters) {
      if (!_hasAnnouncedArrival) {
        _hasAnnouncedArrival = true;
        await _voice.speak(_l10n('arrivedAtDestination'), force: true);
      }
      return;
    }

    if (!walkMode || _activeRoute == null || _walkSteps.isEmpty) {
      return;
    }

    final upcomingTurn = _nextTurnManeuver(currentStepIndex);
    if (upcomingTurn != null) {
      final distanceToTurn = _distanceAlongRoute(
        position: position,
        fromIndex: closestRouteIndex,
        toIndex: upcomingTurn.routeIndex,
        toLat: upcomingTurn.latitude,
        toLng: upcomingTurn.longitude,
      );

      await _announceTurnMilestones(
        turnKey: 'step:${upcomingTurn.stepIndex}',
        turnPhrase: _phraseForInstruction(upcomingTurn.instruction),
        distanceToTurn: distanceToTurn,
      );
      return;
    }

    await _announceStraightLeg(currentStepIndex);
  }

  Future<void> announceObstacle({
    required String spokenMessage,
    String? dedupeKey,
  }) async {
    await _voice.initialize();

    final text = spokenMessage.trim();
    if (text.isEmpty) return;

    final key = dedupeKey ?? text;
    if (_lastObstacleKey == key) return;

    _lastObstacleKey = key;
    _obstacleActive = true;
    await _voice.speak(text);
  }

  Future<void> announceObstacleCleared() async {
    if (!_obstacleActive) return;
    _obstacleActive = false;
    _lastObstacleKey = null;
    await _voice.speak(_l10n('navVoiceObstacleCleared'));
  }

  Future<void> stop() async {
    await _voice.stop();
    resetSession();
  }

  Future<void> dispose() async {
    await _voice.dispose();
    resetSession();
  }

  RouteVoiceManeuver? _nextTurnManeuver(int currentStepIndex) {
    for (final maneuver in _voiceManeuvers) {
      if (maneuver.stepIndex > currentStepIndex && maneuver.isTurn) {
        return maneuver;
      }
    }
    return null;
  }

  Future<void> _announceStraightLeg(int currentStepIndex) async {
    if (currentStepIndex < 0 || currentStepIndex >= _walkSteps.length) return;

    final step = _walkSteps[currentStepIndex];
    if (!_turnGenerator.isStraightLeg(step)) return;

    final key = 'straight-leg:$currentStepIndex';
    if (_announcedMilestones.contains(key)) return;

    final meters = step.distanceMeters.round();
    if (meters < 50) {
      if (_markMilestone(key)) {
        await _voice.speak(_l10n('navVoiceContinueStraight'));
      }
      return;
    }

    if (_markMilestone(key)) {
      await _voice.speak(_l10n('navVoiceWalkStraightMeters', {
        'distance': meters.toString(),
      }));
    }
  }

  double _distanceAlongRoute({
    required Position position,
    required int fromIndex,
    required int toIndex,
    required double toLat,
    required double toLng,
  }) {
    if (_routePoints.isEmpty) {
      return Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        toLat,
        toLng,
      );
    }

    fromIndex = fromIndex.clamp(0, _routePoints.length - 1);
    toIndex = toIndex.clamp(0, _routePoints.length - 1);

    if (toIndex <= fromIndex) {
      return Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        toLat,
        toLng,
      );
    }

    var total = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      _routePoints[fromIndex].latitude,
      _routePoints[fromIndex].longitude,
    );

    for (var i = fromIndex; i < toIndex; i++) {
      final a = _routePoints[i];
      final b = _routePoints[i + 1];
      total += Geolocator.distanceBetween(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
    }

    return total;
  }

  Future<void> _announceTurnMilestones({
    required String turnKey,
    required String turnPhrase,
    required double distanceToTurn,
  }) async {
    if (distanceToTurn <= _announceNowMeters) {
      final key = '$turnKey:now';
      if (_markMilestone(key)) {
        await _voice.speak(_l10n('navVoiceTurnNow', {'turn': turnPhrase}));
      }
      return;
    }

    if (distanceToTurn <= _announce20Meters + 3) {
      final key = '$turnKey:20';
      if (_markMilestone(key)) {
        await _voice.speak(_l10n('navVoiceTurnInMeters', {
          'turn': turnPhrase,
          'distance': '20',
        }));
      }
      return;
    }

    if (distanceToTurn <= _announce50Meters + 5) {
      final key = '$turnKey:50';
      if (_markMilestone(key)) {
        await _voice.speak(_l10n('navVoiceTurnInMeters', {
          'turn': turnPhrase,
          'distance': '50',
        }));
      }
    }
  }

  bool _markMilestone(String key) {
    if (_announcedMilestones.contains(key)) return false;
    _announcedMilestones.add(key);
    return true;
  }

  String _phraseForInstruction(TurnInstruction instruction) {
    return switch (instruction) {
      TurnInstruction.continueStraight => _l10n('navVoiceContinueStraight'),
      TurnInstruction.slightLeft => _l10n('navVoiceSlightLeft'),
      TurnInstruction.turnLeft => _l10n('navVoiceTurnLeft'),
      TurnInstruction.sharpLeft => _l10n('navVoiceSharpLeft'),
      TurnInstruction.slightRight => _l10n('navVoiceSlightRight'),
      TurnInstruction.turnRight => _l10n('navVoiceTurnRight'),
      TurnInstruction.sharpRight => _l10n('navVoiceSharpRight'),
    };
  }

  String _l10n(String key, [Map<String, Object?> params = const {}]) {
    return _settings.localized(key, params);
  }
}
