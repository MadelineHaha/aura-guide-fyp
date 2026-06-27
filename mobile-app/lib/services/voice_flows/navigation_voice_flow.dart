import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../app_navigator.dart';
import '../../models/navigation_destination.dart';
import '../../models/place_search_result.dart';
import '../../models/walking_route.dart';
import '../../navigation_ar_page.dart';
import '../../utils/place_search_matching.dart';
import '../app_settings_service.dart';
import '../navigation_guidance_controller.dart';
import '../navigation_service.dart';
import '../places_search_service.dart';
import '../walking_route_service.dart';
import '../voice_assistant_coordinator.dart';
import '../../utils/voice_option_parser.dart';

enum _NavDeclineAction { changeLocation, continueSelected, goBack }

/// Voice-only navigation: destination search, confirm, home/work, current location.
class NavigationVoiceFlow {
  NavigationVoiceFlow();

  static const _maxBranchOptions = 3;

  final _assistant = VoiceAssistantCoordinator.instance;
  final _settings = AppSettingsService.instance;
  final _nav = NavigationService.instance;
  final _places = PlacesSearchService(navigationService: NavigationService.instance);
  final _guidance = NavigationGuidanceController();

  String _l10n(String key, [Map<String, Object?> params = const {}]) {
    return _settings.localized(key, params);
  }

  Future<void> run() async {
    if (!_settings.isVoiceConversationEnabled) return;

    _assistant.acquireMicLock();
    try {
      await _nav.initialize();
      await _maybeOfferSetHomeWork();

      while (_isOnNavigationPage()) {
        final destination = await _askDestination();
        if (destination == null || !_isOnNavigationPage()) return;

        final confirmed = await _confirmDestination(destination);
        if (confirmed) {
          await _startNavigation(destination);
          return;
        }

        final action = await _askDeclineAction();
        switch (action) {
          case _NavDeclineAction.changeLocation:
            continue;
          case _NavDeclineAction.continueSelected:
            await _startNavigation(destination);
            return;
          case _NavDeclineAction.goBack:
            await _assistant.tryHandleGlobalNavigationCommand('go back');
            return;
        }
      }
    } on VoiceFlowNavigationException {
      // handled globally
    } finally {
      _assistant.releaseMicLock();
      _assistant.resumeAfterVoiceFlow();
    }
  }

  Future<void> _maybeOfferSetHomeWork() async {
    final homeMissing = _nav.home == null;
    final workMissing = _nav.work == null;
    if (!homeMissing && !workMissing) return;

    await _assistant.speakPrompt(
      'navVoiceSetHomeWorkOffer',
      params: {
        'home': homeMissing ? _l10n('navVoiceNotSet') : _l10n('navVoiceAlreadySet'),
        'work': workMissing ? _l10n('navVoiceNotSet') : _l10n('navVoiceAlreadySet'),
      },
    );

    final answer = await _assistant.listenUntilCaptured(
      listeningMessageKey: 'navVoiceListening',
    );
    if (!_isOnNavigationPage()) return;

    if (_wantsSetHome(answer) && homeMissing) {
      await _assistant.speakPrompt('navVoiceAskHomeAddress');
      final homeQuery = await _assistant.listenUntilCaptured(
        listeningMessageKey: 'navVoiceListening',
      );
      final home = await _resolveDestinationFromSpeech(homeQuery);
      if (home != null) {
        await _nav.setHome(home);
        await _assistant.speakPrompt('navVoiceHomeSaved');
      } else {
        await _assistant.speakPrompt('navVoiceLocationNotFound');
      }
    }

    if (_wantsSetWork(answer) && workMissing) {
      await _assistant.speakPrompt('navVoiceAskWorkAddress');
      final workQuery = await _assistant.listenUntilCaptured(
        listeningMessageKey: 'navVoiceListening',
      );
      final work = await _resolveDestinationFromSpeech(workQuery);
      if (work != null) {
        await _nav.setWork(work);
        await _assistant.speakPrompt('navVoiceWorkSaved');
      } else {
        await _assistant.speakPrompt('navVoiceLocationNotFound');
      }
    }
  }

  Future<NavDestination?> _askDestination() async {
    while (_isOnNavigationPage()) {
      await _assistant.speakPrompt('navVoiceAskDestination');
      final answer = await _assistant.listenUntilCaptured(
        listeningMessageKey: 'navVoiceListening',
      );
      if (!_isOnNavigationPage()) return null;

      if (PlaceSearchMatcher.isGoHomeNavigationQuery(answer)) {
        final home = _nav.home;
        if (home == null) {
          await _assistant.speakPrompt('navVoiceHomeNotSet');
          continue;
        }
        await _assistant.speakPrompt(
          'navVoiceUsingSavedHome',
          params: {'place': home.label},
        );
        return home;
      }

      if (PlaceSearchMatcher.isGoWorkNavigationQuery(answer)) {
        final work = _nav.work;
        if (work == null) {
          await _assistant.speakPrompt('navVoiceWorkNotSet');
          continue;
        }
        await _assistant.speakPrompt(
          'navVoiceUsingSavedWork',
          params: {'place': work.label},
        );
        return work;
      }

      if (await _assistant.tryHandleGlobalNavigationCommand(answer)) {
        throw const VoiceFlowNavigationException();
      }

      if (PlaceSearchMatcher.isCurrentLocationQuery(answer)) {
        try {
          final position = await _nav.currentPosition();
          return await _nav.destinationFromPosition(position);
        } catch (_) {
          await _assistant.speakPrompt('navVoiceCurrentLocationFailed');
          continue;
        }
      }

      final resolved = await _resolveDestinationFromSpeech(answer);
      if (resolved != null) return resolved;

      await _assistant.speakPrompt('navVoiceLocationNotFound');
      await _assistant.speakPrompt('navVoiceAskDestinationRetry');
    }
    return null;
  }

  Future<NavDestination?> _resolveDestinationFromSpeech(String speech) async {
    final trimmed = speech.trim();
    if (trimmed.isEmpty) return null;

    Position? position;
    try {
      position = await _nav.currentPosition();
    } catch (_) {}

    final results = await _places.search(
      query: trimmed,
      originLat: position?.latitude,
      originLng: position?.longitude,
      mergeOnlineResults: true,
    );
    if (results.isEmpty) return null;
    if (results.length == 1) return results.first.destination;

    return _askBranchChoice(results.take(_maxBranchOptions).toList());
  }

  Future<NavDestination?> _askBranchChoice(
    List<PlaceSearchResult> candidates,
  ) async {
    if (candidates.isEmpty) return null;
    if (candidates.length == 1) return candidates.first.destination;

    while (_isOnNavigationPage()) {
      final optionsText = candidates.asMap().entries.map((entry) {
        final result = entry.value;
        final distance = result.distanceLabel;
        return _l10n('navVoiceBranchOption', {
          'number': entry.key + 1,
          'name': result.destination.label,
          'distance': distance.isEmpty ? '' : ', $distance away',
        });
      }).join('. ');

      await _assistant.speakPrompt(
        'navVoiceAskBranch',
        params: {
          'count': candidates.length,
          'options': optionsText,
        },
      );

      final answer = await _assistant.listenUntilCaptured(
        listeningMessageKey: 'navVoiceListening',
      );
      if (!_isOnNavigationPage()) return null;

      if (await _assistant.tryHandleGlobalNavigationCommand(answer)) {
        throw const VoiceFlowNavigationException();
      }

      final destinations = candidates.map((c) => c.destination).toList();
      final byOption = VoiceOptionParser.selectByOptionIndex(destinations, answer);
      if (byOption != null) return byOption;

      final text = VoiceAssistantCoordinator.normalizeSpeech(answer);
      if (text.isNotEmpty) {
        NavDestination? best;
        var bestScore = 0;
        for (final candidate in candidates) {
          final label = VoiceAssistantCoordinator.normalizeSpeech(
            candidate.destination.label,
          );
          if (label.isEmpty) continue;
          if (text.contains(label) || label.contains(text)) {
            return candidate.destination;
          }
          final score = PlaceSearchMatcher.score(answer, candidate.destination);
          if (score > bestScore) {
            bestScore = score;
            best = candidate.destination;
          }
        }
        if (best != null && bestScore > 1) return best;
      }

      await _assistant.speakPrompt('navVoiceBranchRetry');
    }
    return null;
  }

  Future<bool> _confirmDestination(NavDestination destination) async {
    while (_isOnNavigationPage()) {
      await _assistant.speakPrompt(
        'navVoiceConfirmDestination',
        params: {'place': destination.label},
      );
      final answer = await _assistant.listenUntilCaptured(
        listeningMessageKey: 'navVoiceListening',
      );
      if (_isAffirmative(answer)) return true;
      if (_isNegative(answer)) return false;
      await _assistant.speakPrompt('voiceCaptureInvalid');
    }
    return false;
  }

  Future<_NavDeclineAction> _askDeclineAction() async {
    while (_isOnNavigationPage()) {
      await _assistant.speakPrompt('navVoiceDeclineOptions');
      final answer = await _assistant.listenUntilCaptured(
        listeningMessageKey: 'navVoiceListening',
      );

      const actions = [
        _NavDeclineAction.changeLocation,
        _NavDeclineAction.continueSelected,
        _NavDeclineAction.goBack,
      ];
      final byOption = VoiceOptionParser.selectByOptionIndex(actions, answer);
      if (byOption != null) return byOption;

      final text = VoiceAssistantCoordinator.normalizeSpeech(answer);
      if (_containsAny(text, const ['change', 'another', 'different', 'tukar', '换', '其他'])) {
        return _NavDeclineAction.changeLocation;
      }
      if (_containsAny(text, const ['continue', 'proceed', 'start', 'go', 'teruskan', '继续'])) {
        return _NavDeclineAction.continueSelected;
      }
      if (_containsAny(text, const ['back', 'cancel', 'kembali', '返回', '取消'])) {
        return _NavDeclineAction.goBack;
      }
      await _assistant.speakPrompt('voiceCaptureInvalid');
    }
    return _NavDeclineAction.goBack;
  }

  Future<void> _startNavigation(NavDestination destination) async {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;

    try {
      final resolved = await _nav.resolveDestination(destination);
      await _nav.rememberRecent(resolved);

      WalkingRoute? walkingRoute;
      try {
        final position = await _nav.currentPosition();
        walkingRoute = await walkingRouteService.fetchWalkingRoute(
          startLat: position.latitude,
          startLng: position.longitude,
          endLat: resolved.latitude!,
          endLng: resolved.longitude!,
        );
      } catch (_) {}

      await _guidance.start(resolved, walkingRoute: walkingRoute);
      await _assistant.speakPrompt(
        'navVoiceStartingNavigation',
        params: {'place': resolved.label},
      );

      await rootNavigatorKey.currentState?.push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'NavigationArPage'),
          builder: (context) => NavigationArPage(
            destination: resolved,
            guidance: _guidance,
          ),
        ),
      );

      await _guidance.stop();
    } catch (_) {
      await _assistant.speakPrompt('navVoiceNavigationFailed');
    }
  }

  bool _wantsSetHome(String speech) {
    final raw = speech.trim();
    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);
    return _containsAny(raw, const ['家', 'home']) ||
        _containsAny(text, const ['home', 'set home', 'home address']);
  }

  bool _wantsSetWork(String speech) {
    final raw = speech.trim();
    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);
    return _containsAny(raw, const ['工作', 'work']) ||
        _containsAny(text, const ['work', 'set work', 'office', 'work address']);
  }

  bool _isAffirmative(String speech) {
    final raw = speech.trim();
    if (_containsAny(raw, const ['是', '好', '对', '可以'])) return true;
    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);
    return _containsAny(text, const ['yes', 'yeah', 'yep', 'confirm', 'ok', 'sure', 'ya']);
  }

  bool _isNegative(String speech) {
    final raw = speech.trim();
    if (_containsAny(raw, const ['不', '否', '不要', 'tidak'])) return true;
    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);
    return _containsAny(text, const ['no', 'nope', 'cancel', 'not']);
  }

  bool _containsAny(String text, List<String> phrases) {
    return phrases.any(text.contains);
  }

  bool _isOnNavigationPage() {
    final label = _assistant.topRouteLabel;
    return label != null && label.contains('NavigationPage');
  }
}
