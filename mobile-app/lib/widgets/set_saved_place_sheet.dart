import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../l10n/app_localizations.dart';
import '../models/navigation_destination.dart';
import '../models/place_search_result.dart';
import '../services/navigation_service.dart';
import '../services/places_search_service.dart';

enum SavedPlaceType { home, work }

Future<NavDestination?> showSetSavedPlaceSheet({
  required BuildContext context,
  required SavedPlaceType type,
  required NavigationService navigationService,
  required PlacesSearchService placesSearch,
  Position? userPosition,
  NavDestination? currentLocation,
}) {
  return showModalBottomSheet<NavDestination>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF111111),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => _SetSavedPlaceSheet(
      type: type,
      navigationService: navigationService,
      placesSearch: placesSearch,
      userPosition: userPosition,
      currentLocation: currentLocation,
    ),
  );
}

class _SetSavedPlaceSheet extends StatefulWidget {
  const _SetSavedPlaceSheet({
    required this.type,
    required this.navigationService,
    required this.placesSearch,
    this.userPosition,
    this.currentLocation,
  });

  final SavedPlaceType type;
  final NavigationService navigationService;
  final PlacesSearchService placesSearch;
  final Position? userPosition;
  final NavDestination? currentLocation;

  @override
  State<_SetSavedPlaceSheet> createState() => _SetSavedPlaceSheetState();
}

class _SetSavedPlaceSheetState extends State<_SetSavedPlaceSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  var _searching = false;
  String? _error;
  List<PlaceSearchResult> _results = const [];
  var _saving = false;
  var _loadingLocation = false;
  NavDestination? _currentLocation;
  int _requestId = 0;

  String _title(BuildContext context) => widget.type == SavedPlaceType.home
      ? context.l10n.t('setHomeAddress')
      : context.l10n.t('setWorkAddress');

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.currentLocation;
    if (_currentLocation == null) {
      unawaited(_loadCurrentLocation());
    }
  }

  Future<void> _loadCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      final position = widget.userPosition;
      _currentLocation = position != null
          ? await widget.navigationService.destinationFromPosition(position)
          : await widget.navigationService.currentLocationDestination();
    } catch (_) {
      _currentLocation = null;
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _searching = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(_runSearch(query));
    });
  }

  Future<void> _runSearch(String query) async {
    final requestId = ++_requestId;
    setState(() {
      _searching = true;
      _error = null;
    });

    try {
      final results = await widget.placesSearch.search(
        query: query,
        originLat: widget.userPosition?.latitude,
        originLng: widget.userPosition?.longitude,
      );

      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = results;
        _searching = false;
        _error = results.isEmpty
            ? context.l10n.t('noPlacesFoundShort', {'query': query})
            : null;
      });
    } catch (_) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _results = const [];
        _searching = false;
        _error = context.l10n.t('couldNotSearchPlaces');
      });
    }
  }

  Future<void> _selectResult(PlaceSearchResult result) async {
    await _saveDestination(result.destination);
  }

  Future<void> _useCurrentLocation() async {
    final location = _currentLocation;
    if (location == null || _saving) return;
    await _saveDestination(location);
  }

  Future<void> _saveDestination(NavDestination destination) async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final saved = widget.type == SavedPlaceType.home
          ? await widget.navigationService.setHome(destination)
          : await widget.navigationService.setWork(destination);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('couldNotSaveAddress', {'error': error})),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A3A),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _title(context),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_saving,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: l10n.t('searchForPlace'),
              hintStyle: const TextStyle(color: Color(0xFF8A8A8A)),
              filled: true,
              fillColor: const Color(0xFF1A1A1A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF63C3C4)),
              ),
            ),
            textInputAction: TextInputAction.search,
            onChanged: _onChanged,
            onSubmitted: (value) {
              final query = value.trim();
              if (query.isNotEmpty) unawaited(_runSearch(query));
            },
          ),
          const SizedBox(height: 12),
          if (_loadingLocation)
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
          else if (_currentLocation != null)
            _LocationOptionTile(
              label: l10n.t('yourLocation'),
              address: _currentLocation!.address,
              trailing: l10n.t('here'),
              icon: Icons.my_location,
              enabled: !_saving,
              onTap: () => unawaited(_useCurrentLocation()),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                l10n.t('locationUnavailableGps'),
                style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 13),
              ),
            ),
          const SizedBox(height: 12),
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF63C3C4)),
              ),
            )
          else if (_searching && _results.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF63C3C4)),
              ),
            )
          else if (_error != null && _results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFB0B0B0)),
              ),
            )
          else if (_results.isNotEmpty)
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final result = _results[index];
                  return _LocationOptionTile(
                    label: result.destination.label,
                    address: result.destination.address,
                    trailing: result.distanceLabel,
                    icon: Icons.place_outlined,
                    enabled: !_saving,
                    onTap: () => unawaited(_selectResult(result)),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _LocationOptionTile extends StatelessWidget {
  const _LocationOptionTile({
    required this.label,
    required this.address,
    required this.onTap,
    this.trailing,
    this.icon = Icons.place_outlined,
    this.enabled = true,
  });

  final String label;
  final String address;
  final String? trailing;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFF63C3C4),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.black, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFB0B0B0),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null && trailing!.isNotEmpty)
                Text(
                  trailing!,
                  style: const TextStyle(
                    color: Color(0xFF63C3C4),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
