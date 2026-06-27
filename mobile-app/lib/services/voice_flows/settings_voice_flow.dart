import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../app_navigator.dart';
import '../../auth_session.dart';
import '../../models/voice_profile_data.dart';
import '../../password_recovery_page.dart';
import '../../settings_page.dart';
import '../../voice_login_page.dart';
import '../../voice_profile_setup_page.dart';
import '../app_experience_service.dart';
import '../app_settings_service.dart';
import '../user_profile_service.dart';
import '../voice_assistant_coordinator.dart';
import '../../utils/voice_option_parser.dart';

/// Spoken walkthrough of the settings page: list options, then offer changes.
class SettingsVoiceFlow {
  SettingsVoiceFlow();

  final _settings = AppSettingsService.instance;
  final _assistant = VoiceAssistantCoordinator.instance;
  final _profileService = UserProfileService();

  bool _voiceLoginActive = false;
  String _pendingIntentFragments = '';

  String _l10n(String key, [Map<String, Object?> params = const {}]) {
    return _settings.localized(key, params);
  }

  Future<void> run({bool openSettingsPage = false}) async {
    if (!AppExperienceService.instance.isPatientExperience) return;

    try {
      if (openSettingsPage) {
        openVoiceGuidedSettingsPage();
      }
      await _loadVoiceLoginStatus();

      final choice = await _askReadOrModify();
      if (choice == _SettingsEntryChoice.unknown) {
        await _assistant.speakPrompt('voiceSettingsStayOnScreen');
        return;
      }

      if (choice == _SettingsEntryChoice.read) {
        await _speakOptionsList();
        final wantsModify = await _askWantsModifyAfterRead();
        if (!wantsModify) {
          await _assistant.speakPrompt('voiceSettingsStayOnScreen');
          return;
        }
      }

      await _runModifyLoop();
    } on VoiceFlowNavigationException {
      // Navigation already handled (e.g. user said "go back").
    } on VoiceFlowCancelledException {
      await _assistant.speakPrompt('voiceSettingsCancelled');
    }
  }

  Future<void> _runModifyLoop() async {
    String? pendingAnswer;
    _pendingIntentFragments = '';
    while (true) {
      final answer = pendingAnswer ??
          await _assistant.promptAndListen('voiceSettingsWhichSetting');
      pendingAnswer = null;
      if (answer == null || _isDone(answer)) break;

      final result = await _applySettingChange(answer);
      if (result == _SettingChangeResult.cancelled) break;

      if (result == _SettingChangeResult.updated) {
        _pendingIntentFragments = '';
        await _assistant.speakPrompt('voiceSettingsUpdated');
      } else if (result == _SettingChangeResult.openedScreen) {
        _pendingIntentFragments = '';
        await _assistant.speakPrompt('voiceSettingsOpenedScreen');
      } else if (result == _SettingChangeResult.notRecognized) {
        await _assistant.speakPrompt('voiceSettingsNotRecognized');
        continue;
      } else if (result == _SettingChangeResult.partial) {
        await _assistant.speakPrompt('voiceSettingsPartialHint');
        continue;
      }

      final next = await _assistant.promptAndListen('voiceSettingsChangeAnother');
      if (next == null || _isDone(next)) break;

      final nextNormalized = VoiceAssistantCoordinator.normalizeSpeech(next);
      if (_isNegative(nextNormalized)) break;
      if (_isAffirmative(nextNormalized)) continue;

      pendingAnswer = next;
    }

    await _assistant.speakPrompt('voiceSettingsDone');
  }

  Future<_SettingsEntryChoice> _askReadOrModify() async {
    var promptKey = 'voiceSettingsInitialPrompt';
    while (true) {
      final answer = await _assistant.promptAndListen(promptKey);
      final choice = _parseInitialChoice(answer);
      if (choice != _SettingsEntryChoice.unknown) return choice;
      if (answer == null) return _SettingsEntryChoice.unknown;
      promptKey = 'voiceSettingsInitialRetry';
    }
  }

  Future<bool> _askWantsModifyAfterRead() async {
    final answer = await _assistant.promptAndListen('voiceSettingsAfterReadPrompt');
    if (answer == null) return false;
    final normalized = VoiceAssistantCoordinator.normalizeSpeech(answer);
    if (_isNegative(normalized)) return false;
    return _isAffirmative(normalized) || _isModifyIntent(normalized);
  }

  Future<void> _speakOptionsList() async {
    await _loadVoiceLoginStatus();
    await _assistant.speakPrompt('voiceSettingsSummaryIntro');
    await _assistant.speakText(
      VoiceOptionParser.formatNumberedList(_buildOptionLines()),
    );
  }

  _SettingsEntryChoice _parseInitialChoice(String? answer) {
    final normalized = VoiceAssistantCoordinator.normalizeSpeech(answer ?? '');
    if (normalized.isEmpty) return _SettingsEntryChoice.unknown;

    final option = VoiceOptionParser.extractOptionNumber(answer ?? '', 2);
    if (option == 1) return _SettingsEntryChoice.read;
    if (option == 2) return _SettingsEntryChoice.modify;

    if (_matchesAny(normalized, const [
      'read',
      'read options',
      'read my options',
      'read settings',
      'list',
      'list options',
      'hear',
      'tell me',
      'what are my settings',
      'baca',
      'baca pilihan',
      'senarai',
      '朗读',
      '读',
      '选项',
    ])) {
      return _SettingsEntryChoice.read;
    }

    if (_isModifyIntent(normalized) ||
        _matchesAny(normalized, const [
          'modify settings',
          'change settings',
          'edit settings',
          'update settings',
          'ubah tetapan',
          '修改设置',
          '更改设置',
        ])) {
      return _SettingsEntryChoice.modify;
    }

    return _SettingsEntryChoice.unknown;
  }

  Future<void> _loadVoiceLoginStatus() async {
    final user = AuthSession.resolveUser() ?? FirebaseAuth.instance.currentUser;
    if (user == null) {
      _voiceLoginActive = false;
      return;
    }

    try {
      final result = await _profileService.loadProfile(user.uid);
      final voiceData =
          VoiceProfileData.fromFirestore(result.data['voiceProfile']);
      _voiceLoginActive = voiceData != null && voiceData.passphrase.isNotEmpty;
    } catch (_) {
      _voiceLoginActive = false;
    }
  }

  List<String> _buildOptionLines() {
    final settings = _settings.settings;
    return [
      _itemLine(
        _l10n('notificationsTitle'),
        _onOff(settings.notificationsEnabled),
      ),
      _itemLine(
        _l10n('fallDetectionSettingTitle'),
        _onOff(settings.fallDetectionEnabled),
      ),
      _itemLine(
        _l10n('voiceAssistantSettingTitle'),
        _onOff(settings.voiceAssistantEnabled),
      ),
      _itemLine(
        _l10n('voiceOnlyModeTitle'),
        settings.voiceAssistantEnabled
            ? _onOff(settings.voiceOnlyModeEnabled)
            : _l10n('voiceSettingsStatusDisabled'),
      ),
      _itemLine(
        _l10n('languageTitle'),
        _l10n('voiceSettingsStatusLanguage', {
          'language': _settings.languageLabel,
        }),
      ),
      _itemLine(
        _l10n('fontSizeTitle'),
        _l10n('voiceSettingsStatusFont', {
          'level': _fontLevelLabel(settings.fontScale),
        }),
      ),
      _itemLine(
        _l10n('voiceLoginTitle'),
        _voiceLoginActive
            ? _l10n('voiceSettingsVoiceLoginActive')
            : _l10n('voiceSettingsVoiceLoginInactive'),
      ),
      _itemLine(
        _l10n('resetPasswordTitle'),
        _l10n('voiceSettingsResetPasswordHint'),
      ),
    ];
  }

  String _itemLine(String name, String status) {
    return _l10n('voiceSettingsItemStatus', {'name': name, 'status': status});
  }

  String _onOff(bool enabled) {
    return enabled
        ? _l10n('voiceSettingsStatusEnabled')
        : _l10n('voiceSettingsStatusDisabled');
  }

  String _fontLevelLabel(double scale) {
    if (scale < 0.95) return _l10n('voiceSettingsFontSmall');
    if (scale > 1.15) return _l10n('voiceSettingsFontLarge');
    return _l10n('voiceSettingsFontMedium');
  }

  Future<_SettingChangeResult> _applySettingChange(String answer) async {
    const settingKeywords = [
      'notifications',
      'fall detection',
      'voice assistant',
      'voice only mode',
      'language',
      'font size',
      'voice login',
      'reset password',
    ];
    final option = VoiceOptionParser.extractOptionNumber(answer, settingKeywords.length);
    if (option != null) {
      return _applySettingChange(settingKeywords[option - 1]);
    }

    final normalized = VoiceAssistantCoordinator.normalizeSpeech(answer);
    if (normalized.isEmpty || _isDone(normalized)) {
      return _SettingChangeResult.cancelled;
    }

    final combined = _mergeIntentFragments(_pendingIntentFragments, normalized);

    final languageResult = await _tryApplyLanguage(combined);
    if (languageResult != null) return languageResult;

    final fontResult = await _tryApplyFont(combined);
    if (fontResult != null) return fontResult;

    final toggleResult = await _tryApplyToggle(combined);
    if (toggleResult != null) return toggleResult;

    final screenResult = _tryOpenScreen(combined);
    if (screenResult != null) return screenResult;

    if (_hasPartialIntent(combined)) {
      _pendingIntentFragments = combined;
      return _SettingChangeResult.partial;
    }

    _pendingIntentFragments = '';
    return _SettingChangeResult.notRecognized;
  }

  String _mergeIntentFragments(String existing, String addition) {
    if (existing.isEmpty) return addition;
    if (addition.isEmpty) return existing;
    final words = <String>{};
    for (final part in '$existing $addition'.split(RegExp(r'\s+'))) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty) words.add(trimmed);
    }
    return words.join(' ');
  }

  Future<_SettingChangeResult?> _tryApplyLanguage(String normalized) async {
    final code = _extractLanguageCode(normalized);
    final languageCue = _isLanguageSettingIntent(normalized);
    final changeCue = _hasChangeIntent(normalized);

    if (code != null) {
      await _settings.setLanguageCode(code);
      _pendingIntentFragments = '';
      return _SettingChangeResult.updated;
    }

    if (languageCue || (changeCue && _mentionsChangeTarget(normalized))) {
      final followUp =
          await _assistant.promptAndListen('voiceSettingsWhichLanguage');
      if (followUp == null || _isDone(followUp)) {
        return _SettingChangeResult.cancelled;
      }
      final merged = _mergeIntentFragments(normalized, followUp);
      final followCode = _extractLanguageCode(
        VoiceAssistantCoordinator.normalizeSpeech(merged),
      );
      if (followCode != null) {
        await _settings.setLanguageCode(followCode);
        _pendingIntentFragments = '';
        return _SettingChangeResult.updated;
      }
      if (_hasPartialIntent(merged)) {
        _pendingIntentFragments = merged;
        return _SettingChangeResult.partial;
      }
      return _SettingChangeResult.notRecognized;
    }

    return null;
  }

  Future<_SettingChangeResult?> _tryApplyFont(String normalized) async {
    final fontCue = _isFontTopic(normalized);
    final changeCue = _hasChangeIntent(normalized);
    if (!fontCue && !changeCue) return null;

    if (await _applyFontScaleChange(normalized)) {
      _pendingIntentFragments = '';
      return _SettingChangeResult.updated;
    }

    if (fontCue || (changeCue && _mentionsFontDirection(normalized))) {
      final followUp =
          await _assistant.promptAndListen('voiceSettingsFontPrompt');
      if (followUp == null || _isDone(followUp)) {
        return _SettingChangeResult.cancelled;
      }
      final merged = _mergeIntentFragments(
        normalized,
        VoiceAssistantCoordinator.normalizeSpeech(followUp),
      );
      if (await _applyFontScaleChange(merged)) {
        _pendingIntentFragments = '';
        return _SettingChangeResult.updated;
      }
      if (_hasPartialIntent(merged)) {
        _pendingIntentFragments = merged;
        return _SettingChangeResult.partial;
      }
      return _SettingChangeResult.notRecognized;
    }

    return null;
  }

  Future<_SettingChangeResult?> _tryApplyToggle(String normalized) async {
    final enable = _parseEnableIntent(normalized);
    final disable = _parseDisableIntent(normalized);

    if (_matchesSettingTopic(normalized, const [
      'notification',
      'notifications',
      'reminder',
      'reminders',
      'notifikasi',
      '通知',
    ])) {
      final value =
          _resolveToggle(enable, disable, current: _settings.settings.notificationsEnabled);
      if (value == null) return _SettingChangeResult.notRecognized;
      await _settings.setNotificationsEnabled(value);
      _pendingIntentFragments = '';
      return _SettingChangeResult.updated;
    }

    if (_matchesSettingTopic(normalized, const [
      'fall detection',
      'fall detect',
      'pengesanan jatuh',
      '跌倒',
    ]) ||
        (_containsWord(normalized, 'fall') &&
            (enable || disable || _hasChangeIntent(normalized)))) {
      final value =
          _resolveToggle(enable, disable, current: _settings.settings.fallDetectionEnabled);
      if (value == null) return _SettingChangeResult.notRecognized;
      await _settings.setFallDetectionEnabled(value);
      _pendingIntentFragments = '';
      return _SettingChangeResult.updated;
    }

    if (_matchesSettingTopic(normalized, const [
      'voice assistant',
      'voice help',
      'pembantu suara',
      '语音助手',
    ]) ||
        _containsWord(normalized, 'assistant')) {
      final value =
          _resolveToggle(enable, disable, current: _settings.settings.voiceAssistantEnabled);
      if (value == null) return _SettingChangeResult.notRecognized;
      await _settings.setVoiceAssistantEnabled(value);
      if (!value) {
        await _settings.setVoiceOnlyModeEnabled(false);
      }
      _pendingIntentFragments = '';
      return _SettingChangeResult.updated;
    }

    if (_matchesSettingTopic(normalized, const [
      'voice only',
      'voice only mode',
      'touch mode',
      'enable touch',
      'mod suara sahaja',
      '纯语音',
      '触屏',
    ])) {
      if (_parseDisableIntent(normalized) ||
          _matchesAny(normalized, const ['touch mode', 'enable touch', '触屏'])) {
        await _settings.setVoiceOnlyModeEnabled(false);
        _pendingIntentFragments = '';
        return _SettingChangeResult.updated;
      }
      if (!_settings.settings.voiceAssistantEnabled) {
        return _SettingChangeResult.notRecognized;
      }
      final value =
          _resolveToggle(enable, disable, current: _settings.settings.voiceOnlyModeEnabled);
      if (value == null) return _SettingChangeResult.notRecognized;
      await _settings.setVoiceOnlyModeEnabled(value);
      _pendingIntentFragments = '';
      return _SettingChangeResult.updated;
    }

    return null;
  }

  _SettingChangeResult? _tryOpenScreen(String normalized) {
    if (_matchesSettingTopic(normalized, const [
      'voice login',
      'voice sign in',
      'voice profile',
      'log masuk suara',
      '语音登录',
    ])) {
      _openPage(
        _voiceLoginActive ? const VoiceLoginPage() : const VoiceProfileSetupPage(),
      );
      _pendingIntentFragments = '';
      return _SettingChangeResult.openedScreen;
    }

    if (_matchesSettingTopic(normalized, const [
      'reset password',
      'change password',
      'kata laluan',
      '密码',
    ])) {
      _openPage(const PasswordRecoveryPage());
      _pendingIntentFragments = '';
      return _SettingChangeResult.openedScreen;
    }

    return null;
  }

  bool _hasPartialIntent(String normalized) {
    return _isLanguageSettingIntent(normalized) ||
        _extractLanguageCode(normalized) != null ||
        _isFontTopic(normalized) ||
        _mentionsFontDirection(normalized) ||
        _hasChangeIntent(normalized) ||
        _parseEnableIntent(normalized) ||
        _parseDisableIntent(normalized) ||
        _matchesSettingTopic(normalized, const [
          'notification',
          'notifications',
          'fall',
          'assistant',
          'voice only',
          'touch',
          'password',
          'voice login',
        ]);
  }

  bool _mentionsChangeTarget(String normalized) {
    return _containsPhrase(normalized, 'change to') ||
        _containsPhrase(normalized, 'switch to') ||
        _containsPhrase(normalized, 'set to') ||
        _containsPhrase(normalized, 'language to');
  }

  bool _mentionsFontDirection(String normalized) {
    return _matchesAny(normalized, const [
      'bigger',
      'smaller',
      'larger',
      'increase',
      'decrease',
      'reduce',
      'besar',
      'kecil',
      '大',
      '小',
    ]);
  }

  bool _hasChangeIntent(String normalized) {
    return _matchesAny(normalized, const [
      'change',
      'change to',
      'switch',
      'switch to',
      'set',
      'set to',
      'update',
      'modify',
      'tukar',
      'ubah',
      '修改',
      '更改',
      '换',
    ]);
  }

  bool _matchesSettingTopic(String normalized, List<String> topics) {
    if (_matchesAny(normalized, topics)) return true;
    for (final topic in topics) {
      if (!topic.contains(' ')) continue;
      final words = topic.split(' ');
      if (words.every((word) => _containsWord(normalized, word))) {
        return true;
      }
    }
    return false;
  }

  bool _isLanguageSettingIntent(String normalized) {
    if (_extractLanguageCode(normalized) != null) return true;
    return _containsWord(normalized, 'language') ||
        _containsWord(normalized, 'languages') ||
        _matchesAny(normalized, const [
          'bahasa',
          'tukar bahasa',
          '换语言',
          '更换语言',
          '改变语言',
          '语言',
        ]);
  }

  String? _extractLanguageCode(String normalized) {
    const checks = <String, List<String>>{
      'en': [
        'change language to english',
        'language change to english',
        'set language to english',
        'switch to english',
        'change to english',
        'language to english',
        'english',
        'inggeris',
        'ingris',
      ],
      'ms': [
        'change language to bahasa melayu',
        'language change to bahasa melayu',
        'change to bahasa melayu',
        'bahasa melayu',
        'bahasa malaysia',
        'change to malay',
        'change to melayu',
        'switch to malay',
        'malay',
        'melayu',
      ],
      'zh': [
        'change language to chinese',
        'language change to chinese',
        'change to chinese',
        'switch to chinese',
        'change to mandarin',
        'mandarin',
        'cantonese',
        'chinese',
        '中文',
        '华语',
        '汉语',
        'cina',
      ],
    };

    for (final entry in checks.entries) {
      for (final phrase in entry.value) {
        if (phrase.contains(' ')) {
          if (_containsPhrase(normalized, phrase)) return entry.key;
        } else if (_containsWord(normalized, phrase) || normalized.contains(phrase)) {
          return entry.key;
        }
      }
    }
    return null;
  }

  bool _containsWord(String text, String word) {
    if (word.isEmpty) return false;
    if (word.contains(' ')) return _containsPhrase(text, word);
    if (RegExp(r'^[a-z0-9]+$').hasMatch(word)) {
      return RegExp(r'(?:^|\s)' + RegExp.escape(word) + r'(?:\s|$)').hasMatch(text);
    }
    return text.contains(word);
  }

  bool _isFontTopic(String normalized) {
    return _matchesAny(normalized, const [
      'font',
      'text size',
      'font size',
      'saiz fon',
      '字体',
      '文字大小',
    ]);
  }

  bool _containsPhrase(String text, String phrase) {
    return text == phrase || text.contains(phrase);
  }

  Future<bool> _applyFontScaleChange(String normalized) async {
    final increased = _matchesAny(normalized, const [
      'increase',
      'bigger',
      'larger',
      'besar',
      '大',
      'increase font',
      'bigger text',
      'larger text',
    ]);
    final decreased = _matchesAny(normalized, const [
      'decrease',
      'smaller',
      'reduce',
      'kecil',
      '小',
      'decrease font',
      'smaller text',
    ]);
    final current = _settings.settings.fontScale;
    if (increased) {
      await _settings.setFontScale((current + 0.1).clamp(0.85, 1.35));
      return true;
    }
    if (decreased) {
      await _settings.setFontScale((current - 0.1).clamp(0.85, 1.35));
      return true;
    }
    return false;
  }

  bool? _resolveToggle(bool enable, bool disable, {required bool current}) {
    if (enable && !disable) return true;
    if (disable && !enable) return false;
    return !current;
  }

  bool _parseEnableIntent(String normalized) {
    return _matchesAny(normalized, const [
      'enable',
      'turn on',
      'switch on',
      'activate',
      'on',
      'hidupkan',
      'aktifkan',
      '打开',
      '启用',
      '开启',
    ]);
  }

  bool _parseDisableIntent(String normalized) {
    return _matchesAny(normalized, const [
      'disable',
      'turn off',
      'switch off',
      'deactivate',
      'off',
      'matikan',
      '关闭',
      '停用',
    ]);
  }

  bool _isAffirmative(String normalized) {
    return _matchesAny(normalized, const [
      'yes',
      'yeah',
      'yep',
      'ok',
      'okay',
      'sure',
      'ya',
      '是',
      '好',
      '可以',
    ]);
  }

  bool _isNegative(String normalized) {
    return _matchesAny(normalized, const [
      'no',
      'nope',
      'not now',
      'nothing',
      'tidak',
      '不用',
      '不要',
    ]);
  }

  bool _isModifyIntent(String normalized) {
    return _matchesAny(normalized, const [
      'modify',
      'change',
      'update',
      'adjust',
      'edit',
      'toggle',
      'ubah',
      'tukar',
      '修改',
      '更改',
    ]);
  }

  bool _isDone(String text) {
    final normalized = VoiceAssistantCoordinator.normalizeSpeech(text);
    return _matchesAny(normalized, const [
      'done',
      'finish',
      'finished',
      'cancel',
      'stop',
      'no thanks',
      'selesai',
      'batal',
      '完成',
      '取消',
    ]);
  }

  bool _matchesAny(String normalized, List<String> phrases) {
    return phrases.any(
      (phrase) => _containsPhrase(normalized, phrase),
    );
  }

  void _openPage(Widget page) {
    final navigator = rootNavigatorKey.currentState;
    if (navigator == null) return;
    navigator.push<void>(
      MaterialPageRoute<void>(
        settings: RouteSettings(name: page.runtimeType.toString()),
        builder: (context) => page,
      ),
    );
  }
}

enum _SettingsEntryChoice {
  read,
  modify,
  unknown,
}

enum _SettingChangeResult {
  updated,
  openedScreen,
  notRecognized,
  partial,
  cancelled,
}

void openVoiceGuidedSettingsPage() {
  final navigator = rootNavigatorKey.currentState;
  if (navigator == null) return;

  navigator.push<void>(
    MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'SettingsPage'),
      builder: (context) => const SettingsPage(),
    ),
  );
}
