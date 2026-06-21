import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'models/navigation_destination.dart' show NavDestination;
import 'models/place_search_result.dart';
import 'models/walking_route.dart';
import 'navigation_ar_page.dart';
import 'l10n/app_localizations.dart';
import 'services/field_speech_input.dart';
import 'services/navigation_guidance_controller.dart';
import 'services/navigation_service.dart';
import 'services/places_search_service.dart';
import 'services/walking_route_service.dart';
import 'widgets/accessible_focus_region.dart';
import 'widgets/app_back_button.dart';
import 'widgets/listening_mic_button.dart';
import 'widgets/set_saved_place_sheet.dart';

class NavigationPage extends StatefulWidget {
  const NavigationPage({super.key});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  static const Color _bg = Color(0xFF000000);
  static const Color _accent = Color(0xFF63C3C4);

  final _service = NavigationService.instance;
  late final PlacesSearchService _placesSearch =
      PlacesSearchService(navigationService: _service);
  final _searchController = TextEditingController();
  final _fieldSpeech = FieldSpeechInput.instance;
  final _guidance = NavigationGuidanceController();

  bool _loadingDestination = false;
  bool _searching = false;
  String? _searchError;
  List<PlaceSearchResult> _searchResults = const [];
  Position? _userPosition;
  NavDestination? _currentLocation;
  var _locationLoading = false;
  Timer? _searchDebounce;
  int _searchRequestId = 0;
  var _storageReady = false;

  bool get _listening => _fieldSpeech.isListeningFor(_searchController);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchTextChanged);
    _fieldSpeech.addListener(_onFieldSpeechChanged);
    unawaited(_bootstrap());
  }

  void _onFieldSpeechChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bootstrap() async {
    await _service.initialize();
    await _loadUserPosition();
    if (!mounted) return;
    setState(() => _storageReady = true);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchTextChanged);
    _fieldSpeech.removeListener(_onFieldSpeechChanged);
    unawaited(_fieldSpeech.stop());
    unawaited(_guidance.dispose());
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserPosition() async {
    setState(() => _locationLoading = true);
    try {
      _userPosition = await _service.currentPosition();
      _currentLocation = await _service.destinationFromPosition(_userPosition!);
    } catch (_) {
      _userPosition = null;
      _currentLocation = null;
    } finally {
      if (mounted) setState(() => _locationLoading = false);
    }
  }

  PlaceSearchResult? get _currentLocationResult {
    final location = _currentLocation;
    if (location == null) return null;
    return PlaceSearchResult(
      destination: location,
      distanceMeters: 0,
    );
  }

  void _onSearchTextChanged() {
    _searchDebounce?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = const [];
        _searchError = null;
        _searching = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_runSearch(query));
    });
  }

  Future<void> _runSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    final requestId = ++_searchRequestId;
    setState(() {
      _searching = true;
      _searchError = null;
    });

    try {
      if (_userPosition == null) {
        await _loadUserPosition();
      }

      final results = await _placesSearch.search(
        query: trimmed,
        originLat: _userPosition?.latitude,
        originLng: _userPosition?.longitude,
      );

      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _searchResults = results;
        _searching = false;
        _searchError = results.isEmpty
            ? context.l10n.t('noPlacesFoundForQuery', {'query': trimmed})
            : null;
      });
    } catch (error) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _searchResults = const [];
        _searching = false;
        _searchError = context.l10n.t('couldNotSearchPlaces');
      });
    }
  }

  Future<void> _startNavigation(NavDestination destination) async {
    if (_loadingDestination) return;
    setState(() => _loadingDestination = true);

    try {
      final resolved = await _service.resolveDestination(destination);
      await _service.rememberRecent(resolved);

      var walkingRoute = await _fetchWalkingRoute(resolved);
      await _guidance.start(resolved, walkingRoute: walkingRoute);
      if (!mounted) return;

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: const RouteSettings(name: 'NavigationArPage'),
          builder: (context) => NavigationArPage(
            destination: resolved,
            guidance: _guidance,
          ),
        ),
      );

      if (!mounted) return;
      await _guidance.stop();
      _searchController.clear();
      setState(() {
        _searchResults = const [];
        _searchError = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('couldNotStartNavigation', {'error': e}))),
      );
    } finally {
      if (mounted) setState(() => _loadingDestination = false);
    }
  }

  Future<void> _openSetSavedPlace(SavedPlaceType type) async {
    final saved = await showSetSavedPlaceSheet(
      context: context,
      type: type,
      navigationService: _service,
      placesSearch: _placesSearch,
      userPosition: _userPosition,
      currentLocation: _currentLocation,
    );
    if (!mounted || saved == null) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          type == SavedPlaceType.home
              ? context.l10n.t('homeAddressSaved')
              : context.l10n.t('workAddressSaved'),
        ),
      ),
    );
  }

  void _onHomeTap(NavDestination? home) {
    if (home == null) {
      unawaited(_openSetSavedPlace(SavedPlaceType.home));
      return;
    }
    unawaited(_startNavigation(home));
  }

  void _onWorkTap(NavDestination? work) {
    if (work == null) {
      unawaited(_openSetSavedPlace(SavedPlaceType.work));
      return;
    }
    unawaited(_startNavigation(work));
  }

  Future<WalkingRoute?> _fetchWalkingRoute(NavDestination destination) async {
    if (!destination.hasCoordinates) return null;

    try {
      final position = await _service.currentPosition();
      return await walkingRouteService.fetchWalkingRoute(
        startLat: position.latitude,
        startLng: position.longitude,
        endLat: destination.latitude!,
        endLng: destination.longitude!,
      );
    } catch (_) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t('couldNotLoadWalkingRoute'))),
      );
      return null;
    }
  }

  Future<void> _startVoiceSearch() async {
    final error = await _fieldSpeech.toggleForController(_searchController);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  void _submitSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    unawaited(_runSearch(query));
  }

  void _selectSearchResult(PlaceSearchResult result) {
    FocusScope.of(context).unfocus();
    _startNavigation(result.destination);
  }

  bool get _showSearchResults =>
      _searchController.text.trim().isNotEmpty ||
      _searching ||
      _searchResults.isNotEmpty ||
      _searchError != null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final home = _service.home;
    final work = _service.work;
    final recents = _service.recentsForDisplay;
    final showSearchResults = _showSearchResults;
    final hereLabel = l10n.t('here');
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: AppBackButton.appBarLeadingWidth,
        leading: const AppBackButton(),
        title: Text(
          l10n.t('navigation'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              AccessibleFocusRegion(
                label: _listening
                    ? l10n.t('navigationListeningA11y')
                    : l10n.t('whereToSearchA11y'),
                child: _SearchBar(
                  controller: _searchController,
                  listening: _listening,
                  searching: _searching,
                  enabled: !_loadingDestination,
                  onSubmitted: (_) => _submitSearch(),
                  onMicTap: () => unawaited(_startVoiceSearch()),
                ),
              ),
              if (!showSearchResults) ...[
                const SizedBox(height: 12),
                if (_locationLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF63C3C4),
                        ),
                      ),
                    ),
                  )
                else if (_currentLocationResult != null)
                  AccessibleFocusRegion(
                    label: l10n.t('yourLocationSelectA11y', {
                      'address': _currentLocation!.address,
                    }),
                    onActivate: () =>
                        _selectSearchResult(_currentLocationResult!),
                    child: _SearchResultTile(
                      result: _currentLocationResult!,
                      icon: Icons.my_location,
                      distanceLabel: hereLabel,
                      onTap: () => _selectSearchResult(_currentLocationResult!),
                    ),
                  )
                else
                  AccessibleFocusRegion(
                    label: l10n.t('locationUnavailable'),
                    child: _SearchMessageCard(
                      message: l10n.t('locationUnavailable'),
                    ),
                  ),
              ],
              if (showSearchResults) ...[
                const SizedBox(height: 16),
                AccessibleFocusRegion(
                  label: l10n.t('searchResults'),
                  child: Text(
                    l10n.t('searchResults'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_searching && _searchResults.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF63C3C4),
                      ),
                    ),
                  )
                else if (_searchError != null)
                  AccessibleFocusRegion(
                    label: _searchError!,
                    child: _SearchMessageCard(message: _searchError!),
                  )
                else
                  ..._searchResults.map(
                    (result) => AccessibleFocusRegion(
                      label: _searchResultAccessibilityLabel(context, result),
                      onActivate: () => _selectSearchResult(result),
                      child: _SearchResultTile(
                        result: result,
                        icon: result.destination.label.toLowerCase() ==
                                'your location'
                            ? Icons.my_location
                            : Icons.place_outlined,
                        distanceLabel: result.destination.label
                                        .toLowerCase() ==
                                    'your location'
                            ? hereLabel
                            : null,
                        onTap: () => _selectSearchResult(result),
                      ),
                    ),
                  ),
              ],
              if (!showSearchResults) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: AccessibleFocusRegion(
                      label: home == null
                          ? l10n.t('homeSetNowA11y')
                          : l10n.t('homeNavigateA11y', {'address': home.address}),
                      onActivate: () => _onHomeTap(home),
                      child: _QuickPlaceCard(
                        title: l10n.t('home'),
                        subtitle: home?.address ?? l10n.t('setNow'),
                        icon: Icons.home_outlined,
                        onTap: () => _onHomeTap(home),
                        onLongPress: () =>
                            unawaited(_openSetSavedPlace(SavedPlaceType.home)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AccessibleFocusRegion(
                      label: work == null
                          ? l10n.t('workSetNowA11y')
                          : l10n.t('workNavigateA11y', {'address': work.address}),
                      onActivate: () => _onWorkTap(work),
                      child: _QuickPlaceCard(
                        title: l10n.t('work'),
                        subtitle: work?.address ?? l10n.t('setNow'),
                        icon: Icons.work_outline,
                        onTap: () => _onWorkTap(work),
                        onLongPress: () =>
                            unawaited(_openSetSavedPlace(SavedPlaceType.work)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              AccessibleFocusRegion(
                label: l10n.t('recentDestinations'),
                child: Text(
                  l10n.t('recent'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (!_storageReady)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: CircularProgressIndicator(color: Color(0xFF63C3C4)),
                  ),
                )
              else if (recents.isEmpty)
                AccessibleFocusRegion(
                  label: l10n.t('noRecentDestinations'),
                  child: _SearchMessageCard(
                    message: l10n.t('noRecentDestinations'),
                  ),
                )
              else
                ...recents.map(
                (item) => AccessibleFocusRegion(
                  label: l10n.t('placeNavigateA11y', {
                    'label': item.label,
                    'address': item.address,
                  }),
                  onActivate: () => _startNavigation(item),
                  child: _RecentTile(
                    destination: item,
                    onTap: () => _startNavigation(item),
                  ),
                ),
              ),
              ],
            ],
          ),
          if (_loadingDestination)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(color: _accent),
            ),
        ],
      ),
    );
  }

  String _searchResultAccessibilityLabel(BuildContext context, PlaceSearchResult result) {
    final distance = result.distanceLabel;
    final distancePart = distance.isEmpty
        ? ''
        : ' $distance from your location.';
    return context.l10n.t('placeSearchResultA11y', {
      'label': result.destination.label,
      'address': result.destination.address,
      'distancePart': distancePart,
    });
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.listening,
    required this.searching,
    required this.enabled,
    required this.onSubmitted,
    required this.onMicTap,
  });

  final TextEditingController controller;
  final bool listening;
  final bool searching;
  final bool enabled;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onMicTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Row(
        children: [
          const Icon(Icons.near_me, color: Color(0xFF63C3C4), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                hintText: listening && controller.text.trim().isEmpty
                    ? context.l10n.t('listeningEllipsis')
                    : context.l10n.t('whereTo'),
                hintStyle: TextStyle(
                  color: listening ? const Color(0xFF63C3C4) : const Color(0xFF8A8A8A),
                ),
                border: InputBorder.none,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
            ),
          ),
          if (searching)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF63C3C4),
                ),
              ),
            )
          else
            ListeningMicButton(
              listening: listening,
              enabled: enabled,
              onPressed: onMicTap,
              tooltip: listening
                  ? context.l10n.t('stopListening')
                  : context.l10n.t('voiceSearch'),
              variant: ListeningMicButtonVariant.icon,
              inactiveColor: const Color(0xFF63C3C4),
            ),
        ],
      ),
    );
  }
}

class _SearchMessageCard extends StatelessWidget {
  const _SearchMessageCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2E2E2E)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFB0B0B0),
          fontSize: 14,
          height: 1.4,
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({
    required this.result,
    required this.onTap,
    this.icon = Icons.place_outlined,
    this.distanceLabel,
  });

  final PlaceSearchResult result;
  final VoidCallback onTap;
  final IconData icon;
  final String? distanceLabel;

  @override
  Widget build(BuildContext context) {
    final destination = result.destination;
    final distance = distanceLabel ?? result.distanceLabel;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2E2E2E)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF63C3C4),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: Colors.black,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        destination.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB0B0B0),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (distance.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    distance,
                    style: const TextStyle(
                      color: Color(0xFF63C3C4),
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickPlaceCard extends StatelessWidget {
  const _QuickPlaceCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.onLongPress,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2E2E2E)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: Color(0xFF63C3C4),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.black, size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFFB0B0B0),
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.destination,
    required this.onTap,
  });

  final NavDestination destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2E2E2E)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: Color(0xFF63C3C4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.history,
                    color: Colors.black,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        destination.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        destination.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFB0B0B0),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
