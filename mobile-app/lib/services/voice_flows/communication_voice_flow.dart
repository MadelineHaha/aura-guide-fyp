import 'package:flutter/material.dart';

import '../../app_navigator.dart';
import '../../chat_page.dart';
import '../../models/conversation_thread.dart';
import '../../models/message_entity.dart';
import '../app_settings_service.dart';
import '../communication_service.dart';
import '../patient_call_session.dart';
import '../voice_assistant_coordinator.dart';
import '../../utils/voice_option_parser.dart';

enum _ChatVoiceAction {
  readAgain,
  sendMessage,
  searchMessage,
  searchByDate,
  archive,
  voiceCall,
  videoCall,
  photo,
}

/// Voice-only communication inbox: unread summary, conversation list, read aloud.
class CommunicationVoiceFlow {
  CommunicationVoiceFlow();

  final _service = CommunicationService();
  final _assistant = VoiceAssistantCoordinator.instance;
  final _settings = AppSettingsService.instance;

  String _l10n(String key, [Map<String, Object?> params = const {}]) {
    return _settings.localized(key, params);
  }

  Future<void> run() async {
    if (!_settings.isVoiceConversationEnabled) return;

    _assistant.acquireMicLock();
    try {
      while (_isOnCommunicationPage()) {
        final threads = await _service.fetchThreads();
        if (!_isOnCommunicationPage()) return;

        await _speakInboxSummary(threads);
        final thread = await _pickThread(threads);
        if (thread == null || !_isOnCommunicationPage()) return;

        await _openAndHandleThread(thread);
      }
    } on VoiceFlowNavigationException {
      // handled globally
    } finally {
      _service.setOpenConversation(null);
      _assistant.releaseMicLock();
      _assistant.resumeAfterVoiceFlow();
    }
  }

  Future<void> _speakInboxSummary(List<ConversationThread> threads) async {
    final unreadThreads = threads.where((t) => t.unread).toList();
    if (unreadThreads.isEmpty) {
      await _assistant.speakPrompt('commVoiceNoUnread');
    } else if (unreadThreads.length == 1) {
      await _assistant.speakPrompt(
        'commVoiceUnreadOne',
        params: {'name': unreadThreads.first.title},
      );
    } else {
      final names = unreadThreads.map((t) => t.title).join(', ');
      await _assistant.speakPrompt(
        'commVoiceUnreadMany',
        params: {'count': unreadThreads.length, 'names': names},
      );
    }

    if (threads.isEmpty) {
      await _assistant.speakPrompt('commVoiceNoConversations');
      return;
    }

    final listText = threads
        .asMap()
        .entries
        .map((entry) {
          final ord = _ordinal(entry.key + 1);
          return _l10n('commVoiceListItem', {
            'ordinal': ord,
            'name': entry.value.title,
          });
        })
        .join(' ');
    await _assistant.speakText(listText);
  }

  Future<ConversationThread?> _pickThread(
    List<ConversationThread> threads,
  ) async {
    if (threads.isEmpty) return null;

    while (_isOnCommunicationPage()) {
      await _assistant.speakPrompt('commVoiceAskPerson');
      final answer = await _assistant.listenForUtterance(
        listeningMessageKey: 'commVoiceListening',
      );
      if (!_isOnCommunicationPage()) return null;
      if (answer == null || answer.trim().isEmpty) {
        await _assistant.speakPrompt('voiceCaptureNotHeard');
        await _assistant.speakPrompt('commVoiceAskPerson');
        continue;
      }

      if (await _assistant.tryHandleGlobalNavigationCommand(answer)) {
        throw const VoiceFlowNavigationException();
      }

      if (_wantsRepeatList(answer)) {
        await _speakInboxSummary(threads);
        continue;
      }

      final picked = _parseThreadChoice(answer, threads);
      if (picked != null) return picked;

      await _assistant.speakPrompt('voiceCaptureInvalid');
    }
    return null;
  }

  Future<void> _openAndHandleThread(ConversationThread thread) async {
    _service.setOpenConversation(thread.conversationId);

    final context = rootNavigatorKey.currentContext;
    if (context != null) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: 'ChatPage:${thread.conversationId}'),
          builder: (context) => ChatPage(
            conversationId: thread.conversationId,
            title: thread.title,
            staffId: thread.staffId,
            isAuraGuide: thread.isAuraGuide,
            deferMarkReadForVoice: true,
          ),
        ),
      );
    }

    while (_isOnCommunicationPage() || _isOnChatPage(thread.conversationId)) {
      await _readUnreadMessages(thread);

      await _assistant.speakPrompt(
        'commVoiceAfterRead',
        params: {'name': thread.title},
      );

      final action = await _listenForChatAction(thread);
      if (action == null) return;

      switch (action) {
        case _ChatVoiceAction.readAgain:
          continue;
        case _ChatVoiceAction.sendMessage:
          await _sendVoiceMessage(thread);
          return;
        case _ChatVoiceAction.searchMessage:
          await _searchMessages(thread, byDate: false);
          return;
        case _ChatVoiceAction.searchByDate:
          await _searchMessages(thread, byDate: true);
          return;
        case _ChatVoiceAction.archive:
          await _service.archiveConversation(thread.conversationId);
          await _assistant.speakPrompt('commVoiceArchived');
          return;
        case _ChatVoiceAction.voiceCall:
          await _startCall(thread);
          return;
        case _ChatVoiceAction.videoCall:
          await _assistant.speakPrompt('commVoiceVideoNotAvailable');
          return;
        case _ChatVoiceAction.photo:
          await _assistant.speakPrompt('commVoicePhotoNotAvailable');
          return;
      }
    }
  }

  Future<_ChatVoiceAction?> _listenForChatAction(
    ConversationThread thread,
  ) async {
    while (_isOnCommunicationPage() || _isOnChatPage(thread.conversationId)) {
      final answer = await _assistant.listenForUtterance(
        listeningMessageKey: 'commVoiceListening',
      );
      if (answer == null || answer.trim().isEmpty) {
        await _assistant.speakPrompt('voiceCaptureNotHeard');
        await _assistant.speakPrompt(
          'commVoiceAfterRead',
          params: {'name': thread.title},
        );
        continue;
      }

      final action = await _parseChatAction(answer, thread);
      if (action != null) return action;

      await _assistant.speakPrompt('voiceCaptureInvalid');
      await _assistant.speakPrompt(
        'commVoiceAfterRead',
        params: {'name': thread.title},
      );
    }
    return null;
  }

  Future<void> _readUnreadMessages(ConversationThread thread) async {
    final unread = await _service.fetchUnreadIncomingMessages(
      conversationId: thread.conversationId,
    );
    if (unread.isEmpty) {
      await _assistant.speakPrompt(
        'commVoiceNoUnreadInThread',
        params: {'name': thread.title},
      );
      return;
    }

    for (final message in unread) {
      if (!_isOnChatPage(thread.conversationId) && !_isOnCommunicationPage()) {
        return;
      }
      await _assistant.speakText(_messageSpeechText(message));
    }

    await _service.markConversationRead(conversationId: thread.conversationId);
  }

  String _messageSpeechText(MessageEntity message) {
    return _l10n('commVoiceReadTextMessage', {
      'date': _service.messageDateLabel(message),
      'time': _service.messageTimeLabel(message),
      'text': _service.messageSpeechContent(message),
    });
  }

  Future<void> _sendVoiceMessage(ConversationThread thread) async {
    await _assistant.speakPrompt(
      'commVoiceSendMessageHint',
      params: {'name': thread.title},
    );
  }

  Future<void> _searchMessages(
    ConversationThread thread, {
    required bool byDate,
  }) async {
    if (byDate) {
      await _assistant.speakPrompt('commVoiceAskSearchDate');
    } else {
      await _assistant.speakPrompt('commVoiceAskSearchKeyword');
    }
    final query = await _assistant.listenUntilCaptured(
      listeningMessageKey: 'commVoiceListening',
    );

    final matches = await _service.searchMessagesForVoice(
      conversationId: thread.conversationId,
      query: query,
      dateOnly: byDate,
    );
    if (matches.isEmpty) {
      await _assistant.speakPrompt('commVoiceSearchNotFound');
      return;
    }

    for (final message in matches) {
      await _assistant.speakText(
        _l10n('commVoiceSearchResult', {
          'date': _service.messageDateLabel(message),
          'time': _service.messageTimeLabel(message),
          'text': _service.messageSpeechContent(message),
        }),
      );
    }
  }

  Future<void> _startCall(ConversationThread thread) async {
    if (thread.staffId.isEmpty) {
      await _assistant.speakPrompt('commVoiceCallNotAvailable');
      return;
    }
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    try {
      await PatientCallSession.instance.startOutgoingToStaff(
        context: context,
        staffId: thread.staffId,
        remoteName: thread.title,
      );
    } catch (_) {
      await _assistant.speakPrompt('commVoiceCallFailed');
    }
  }

  ConversationThread? _parseThreadChoice(
    String answer,
    List<ConversationThread> threads,
  ) {
    final picked = VoiceOptionParser.selectByOptionIndex(threads, answer);
    if (picked != null) return picked;

    final text = VoiceAssistantCoordinator.normalizeSpeech(answer);
    for (final thread in threads) {
      final name = VoiceAssistantCoordinator.normalizeSpeech(thread.title);
      if (name.isNotEmpty && text.contains(name)) return thread;
    }
    return null;
  }

  Future<_ChatVoiceAction?> _parseChatAction(
    String answer,
    ConversationThread thread,
  ) async {
    final raw = answer.trim();
    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);

    if (_containsAny(raw, const ['再读', '重复']) ||
        _containsAny(text, const ['read again', 'repeat', 'ulang'])) {
      return _ChatVoiceAction.readAgain;
    }
    if (_containsAny(text, const [
      'send',
      'message',
      'text',
      'hantar',
      'mesej',
    ])) {
      return _ChatVoiceAction.sendMessage;
    }
    if (_containsAny(text, const [
          'search message',
          'find message',
          'cari mesej',
        ]) ||
        (text.contains('search') && text.contains('message'))) {
      return _ChatVoiceAction.searchMessage;
    }
    if (text.contains('search') && text.contains('date') ||
        _containsAny(raw, const ['日期'])) {
      return _ChatVoiceAction.searchByDate;
    }
    if (_containsAny(text, const ['archive', 'arkib', '归档'])) {
      return _ChatVoiceAction.archive;
    }
    if (_containsAny(text, const [
      'voice call',
      'phone call',
      'call',
      'panggilan',
    ])) {
      return _ChatVoiceAction.voiceCall;
    }
    if (_containsAny(text, const ['video call', 'video', 'panggilan video'])) {
      return _ChatVoiceAction.videoCall;
    }
    if (_containsAny(text, const [
      'camera',
      'photo',
      'picture',
      'gambar',
      '照片',
    ])) {
      return _ChatVoiceAction.photo;
    }
    return null;
  }

  bool _wantsRepeatList(String speech) {
    final raw = speech.trim();
    if (_containsAny(raw, const ['重复', '再听'])) return true;
    final text = VoiceAssistantCoordinator.normalizeSpeech(raw);
    return _containsAny(text, const ['repeat', 'again', 'listen', 'ulang']);
  }

  String _ordinal(int n) {
    switch (_settings.settings.languageCode) {
      case 'zh':
        const zh = ['第一', '第二', '第三', '第四', '第五', '第六', '第七', '第八', '第九', '第十'];
        if (n >= 1 && n <= zh.length) return zh[n - 1];
        return '第$n';
      case 'ms':
        return 'ke-$n';
      default:
        const en = [
          'first',
          'second',
          'third',
          'fourth',
          'fifth',
          'sixth',
          'seventh',
          'eighth',
          'ninth',
          'tenth',
        ];
        if (n >= 1 && n <= en.length) return en[n - 1];
        return '$n';
    }
  }

  bool _containsAny(String text, List<String> phrases) {
    return phrases.any(text.contains);
  }

  bool _isOnCommunicationPage() {
    final label = _assistant.topRouteLabel;
    return label != null && label.contains('CommunicationPage');
  }

  bool _isOnChatPage(String conversationId) {
    final label = _assistant.topRouteLabel;
    return label != null && label.contains('ChatPage:$conversationId');
  }
}
