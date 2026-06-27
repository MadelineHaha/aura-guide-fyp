import '../services/voice_assistant_coordinator.dart';
import 'voice_option_parser.dart';

enum MainMenuVoiceCommand {
  emergency,
  medications,
  appointments,
  healthRecords,
  navigation,
  communication,
  settings,
  notifications,
}

/// Spoken main-menu options and parsing for voice-only mode.
class MainMenuVoice {
  MainMenuVoice._();

  static const optionCount = 8;

  static MainMenuVoiceCommand? parseCommand(String speech) {
    final trimmed = speech.trim();
    if (trimmed.isEmpty) return null;

    final option = VoiceOptionParser.extractOptionNumber(trimmed, optionCount);
    if (option != null) return _fromOption(option);

    final normalized = VoiceAssistantCoordinator.normalizeSpeech(trimmed);
    if (normalized.isEmpty) return null;

    if (_matchesAny(normalized, trimmed, const [
      'emergency sos',
      'emergency alert',
      'emergency',
      'sos alert',
      'sos',
      'help me',
      'need help',
      'kecemasan',
      '紧急',
      '求救',
      '救命',
    ])) {
      return MainMenuVoiceCommand.emergency;
    }
    if (_matchesAny(normalized, trimmed, const [
      'medication',
      'medications',
      'medicine',
      'pill',
      'ubat',
      '药物',
      '用药',
    ])) {
      return MainMenuVoiceCommand.medications;
    }
    if (_matchesAny(normalized, trimmed, const [
      'appointment',
      'appointments',
      'temujanji',
      '预约',
    ])) {
      return MainMenuVoiceCommand.appointments;
    }
    if (_matchesAny(normalized, trimmed, const [
      'health record',
      'health records',
      'medical record',
      'medical records',
      'rekod kesihatan',
      '健康记录',
      '病历',
    ])) {
      return MainMenuVoiceCommand.healthRecords;
    }
    if (_matchesAny(normalized, trimmed, const [
      'navigation',
      'navigate',
      'directions',
      'where to',
      'navigasi',
      '导航',
    ])) {
      return MainMenuVoiceCommand.navigation;
    }
    if (_matchesAny(normalized, trimmed, const [
      'communication',
      'message',
      'messages',
      'chat',
      'komunikasi',
      'mesej',
      '通信',
      '消息',
    ])) {
      return MainMenuVoiceCommand.communication;
    }
    if (_matchesAny(normalized, trimmed, const [
      'setting',
      'settings',
      'tetapan',
      '设置',
    ])) {
      return MainMenuVoiceCommand.settings;
    }
    if (_matchesAny(normalized, trimmed, const [
      'notification',
      'notifications',
      'pemberitahuan',
      'notifikasi',
      '通知',
    ])) {
      return MainMenuVoiceCommand.notifications;
    }

    if (_matchesAny(normalized, trimmed, const [
      'list',
      'list out',
      'what can i do',
      'what are the options',
      'options',
      'senarai',
      'apa pilihan',
      '列出',
      '有什么选项',
      '选项',
    ])) {
      return null; // Not a navigation command — handled separately
    }

    return null;
  }

  /// Returns true when the user is asking the system to list the available options.
  static bool matchesListCommand(String speech) {
    final trimmed = speech.trim();
    if (trimmed.isEmpty) return false;
    final normalized = VoiceAssistantCoordinator.normalizeSpeech(trimmed);
    return _matchesAny(normalized, trimmed, const [
      'list',
      'list out',
      'what can i do',
      'what are the options',
      'options',
      'senarai',
      'apa pilihan',
      '列出',
      '有什么选项',
      '选项',
    ]);
  }

  static MainMenuVoiceCommand? _fromOption(int option) {
    return switch (option) {
      1 => MainMenuVoiceCommand.emergency,
      2 => MainMenuVoiceCommand.medications,
      3 => MainMenuVoiceCommand.appointments,
      4 => MainMenuVoiceCommand.healthRecords,
      5 => MainMenuVoiceCommand.navigation,
      6 => MainMenuVoiceCommand.communication,
      7 => MainMenuVoiceCommand.settings,
      8 => MainMenuVoiceCommand.notifications,
      _ => null,
    };
  }

  static bool _matchesAny(
    String normalized,
    String raw,
    List<String> phrases,
  ) {
    for (final phrase in phrases) {
      if (normalized.contains(phrase)) return true;
      if (raw.contains(phrase)) return true;
    }
    return false;
  }
}
