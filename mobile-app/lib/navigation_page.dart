import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'models/navigation_destination.dart' show NavDestination;
import 'navigation_ar_page.dart';
import 'services/navigation_guidance_controller.dart';
import 'services/navigation_service.dart';

class NavigationPage extends StatefulWidget {
  const NavigationPage({super.key});

  @override
  State<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends State<NavigationPage> {
  static const Color _bg = Color(0xFF000000);
  static const Color _accent = Color(0xFF63C3C4);

  final _service = NavigationService();
  final _searchController = TextEditingController();
  final _speech = SpeechToText();
  final _guidance = NavigationGuidanceController();

  bool _loadingDestination = false;
  bool _listening = false;

  @override
  void dispose() {
    unawaited(_guidance.dispose());
    _searchController.dispose();
    _speech.stop();
    super.dispose();
  }

  Future<void> _startNavigation(NavDestination destination) async {
    if (_loadingDestination) return;
    setState(() => _loadingDestination = true);

    try {
      final resolved = await _service.resolveDestination(destination);
      _service.rememberRecent(resolved);
      await _guidance.start(resolved);
      if (!mounted) return;

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => NavigationArPage(
            destination: resolved,
            guidance: _guidance,
          ),
        ),
      );

      if (!mounted) return;
      await _guidance.stop();
      _searchController.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not start navigation: $e')),
      );
    } finally {
      if (mounted) setState(() => _loadingDestination = false);
    }
  }

  Future<void> _startVoiceSearch() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }

    final available = await _speech.initialize();
    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice search is not available.')),
      );
      return;
    }

    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        _searchController.text = result.recognizedWords;
        if (result.finalResult && mounted) {
          setState(() => _listening = false);
          _submitSearch();
        }
      },
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      localeId: 'en_US',
    );
  }

  void _submitSearch() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final results = _service.search(query);
    _startNavigation(results.first);
  }

  @override
  Widget build(BuildContext context) {
    final home = _service.home;
    final work = _service.work;
    final recents = _service.recents;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Navigation',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _SearchBar(
                controller: _searchController,
                listening: _listening,
                enabled: !_loadingDestination,
                onSubmitted: (_) => _submitSearch(),
                onMicTap: _startVoiceSearch,
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _QuickPlaceCard(
                      title: 'HOME',
                      subtitle: home?.address ?? 'Set now',
                      icon: Icons.home_outlined,
                      onTap: home == null ? null : () => _startNavigation(home),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickPlaceCard(
                      title: 'WORK',
                      subtitle: work?.address ?? 'Set now',
                      icon: Icons.work_outline,
                      onTap: work == null ? null : () => _startNavigation(work),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Text(
                'Recent',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 12),
              ...recents.map(
                (item) => _RecentTile(
                  destination: item,
                  onTap: () => _startNavigation(item),
                ),
              ),
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
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.listening,
    required this.enabled,
    required this.onSubmitted,
    required this.onMicTap,
  });

  final TextEditingController controller;
  final bool listening;
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
              decoration: const InputDecoration(
                hintText: 'Where to?',
                hintStyle: TextStyle(color: Color(0xFF8A8A8A)),
                border: InputBorder.none,
              ),
              textInputAction: TextInputAction.go,
              onSubmitted: onSubmitted,
            ),
          ),
          IconButton(
            onPressed: enabled ? onMicTap : null,
            icon: Icon(
              listening ? Icons.mic : Icons.mic_none,
              color: const Color(0xFF63C3C4),
            ),
          ),
        ],
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
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF1A1A1A),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
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
