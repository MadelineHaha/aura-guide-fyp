import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'auth_session.dart';
import 'password_recovery_page.dart';
import 'services/app_settings_service.dart';
import 'services/user_profile_service.dart';
import 'widgets/accessible_focus_region.dart';
import 'widgets/app_back_button.dart';
import 'widgets/audio_feedback_title.dart';
import 'voice_login_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const Color _bg = Color(0xFF000000);
  static const Color _accent = Color(0xFF63C3C4);

  final _settings = AppSettingsService.instance;
  final _profileService = UserProfileService();

  bool _voiceLoginActive = false;
  bool _loadingVoiceStatus = true;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _loadVoiceLoginStatus();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadVoiceLoginStatus() async {
    final user = AuthSession.resolveUser() ?? FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _voiceLoginActive = false;
          _loadingVoiceStatus = false;
        });
      }
      return;
    }

    try {
      final result = await _profileService.loadProfile(user.uid);
      final voiceProfile =
          (result.data['voiceProfile'] as String?)?.trim() ?? '';
      if (!mounted) return;
      setState(() {
        _voiceLoginActive = voiceProfile.isNotEmpty;
        _loadingVoiceStatus = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _voiceLoginActive = false;
        _loadingVoiceStatus = false;
      });
    }
  }

  Future<void> _pickLanguage() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Choose language',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                ...AppSettings.languages.entries.map((entry) {
                  final isSelected = _settings.settings.languageCode == entry.key;
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tileColor: isSelected ? const Color(0xFF203536) : null,
                    title: Text(
                      entry.value,
                      style: TextStyle(
                        color: isSelected ? _accent : Colors.white,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: _accent)
                        : null,
                    onTap: () => Navigator.of(context).pop(entry.key),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );

    if (selected != null) {
      await _settings.setLanguageCode(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings.settings;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leadingWidth: AppBackButton.appBarLeadingWidth,
        leading: const AppBackButton(),
        title: AudioFeedbackTitle(
          label: 'Settings',
          child: const Text(
            'Settings',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _SettingsCard(
            icon: Icons.volume_up_outlined,
            title: 'AUDIO FEEDBACK',
            subtitle: 'Read screen on tap',
            trailing: Switch(
              value: settings.audioFeedbackEnabled,
              activeColor: Colors.white,
              activeTrackColor: _accent,
              onChanged: _settings.setAudioFeedbackEnabled,
            ),
          ),
          _SettingsCard(
            icon: Icons.text_fields,
            iconLabel: 'Aa',
            title: 'FONT SIZE',
            subtitle: 'Ensure readability',
            trailing: SizedBox(
              width: 132,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: SliderComponentShape.noOverlay,
                  activeTrackColor: _accent,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: _accent,
                ),
                child: Slider(
                  value: settings.fontScale,
                  min: 0.85,
                  max: 1.35,
                  onChanged: (value) => _settings.setFontScale(value),
                ),
              ),
            ),
          ),
          _SettingsCard(
            icon: Icons.language,
            title: 'LANGUAGE',
            subtitle: _settings.languageLabel,
            onTap: () {
              _settings.speakIfEnabled('Language. ${_settings.languageLabel}');
              _pickLanguage();
            },
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          ),
          _SettingsCard(
            icon: Icons.notifications_none_outlined,
            title: 'NOTIFICATIONS',
            subtitle: 'Get notify immediately',
            trailing: Switch(
              value: settings.notificationsEnabled,
              activeColor: Colors.white,
              activeTrackColor: _accent,
              onChanged: _settings.setNotificationsEnabled,
            ),
          ),
          _VoiceLoginCard(
            loading: _loadingVoiceStatus,
            active: _voiceLoginActive,
            onTap: () async {
              _settings.speakIfEnabled('Voice login');
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => const VoiceLoginPage(),
                ),
              );
              await _loadVoiceLoginStatus();
            },
          ),
          _SettingsCard(
            icon: Icons.vpn_key_outlined,
            title: 'RESET PASSWORD',
            subtitle: 'Create stronger password',
            onTap: () {
              _settings.speakIfEnabled('Reset password');
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (context) => const PasswordRecoveryPage(),
                ),
              );
            },
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconLabel,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String? iconLabel;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  static const Color _accent = Color(0xFF63C3C4);
  static const Color _card = Color(0xFF1A1A1A);
  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AccessibleFocusRegion(
        label: '$title. $subtitle',
        onActivate: onTap,
        child: Material(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: iconLabel != null
                        ? Text(
                            iconLabel!,
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          )
                        : Icon(icon, color: Colors.black, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(color: _subtext, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceLoginCard extends StatelessWidget {
  const _VoiceLoginCard({
    required this.loading,
    required this.active,
    required this.onTap,
  });

  final bool loading;
  final bool active;
  final VoidCallback onTap;

  static const Color _accent = Color(0xFF63C3C4);
  static const Color _card = Color(0xFF1A1A1A);
  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: _accent,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.fingerprint, color: Colors.black, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'VOICE LOGIN',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            loading
                                ? 'Checking…'
                                : active
                                    ? 'Active'
                                    : 'Not set up',
                            style: TextStyle(
                              color: active ? Colors.white : _subtext,
                              fontWeight:
                                  active ? FontWeight.bold : FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          if (active) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _accent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'VERIFIED',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white54),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
