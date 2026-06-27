import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'l10n/app_localizations.dart';
import 'models/chat_list_item.dart';
import 'services/call_ringtone_player.dart';
import 'services/chat_voice_recorder_service.dart';
import 'services/communication_service.dart';
import 'services/device_permissions_service.dart';
import 'services/field_speech_input.dart';
import 'services/patient_call_session.dart';
import 'services/voice_call_service.dart';
import 'utils/chat_date_grouping.dart';
import 'utils/chat_search_highlight.dart';
import 'widgets/accessible_focus_region.dart';
import 'widgets/chat_date_divider.dart';
import 'widgets/app_back_button.dart';
import 'widgets/chat_voice_composer.dart';
import 'widgets/listening_mic_button.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.conversationId,
    required this.title,
    required this.staffId,
    required this.isAuraGuide,
    this.isArchived = false,
    this.deferMarkReadForVoice = false,
  });

  final String conversationId;
  final String title;
  final String staffId;
  final bool isAuraGuide;
  final bool isArchived;
  final bool deferMarkReadForVoice;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const Color _bg = Color(0xFF000000);
  static const Color _accent = Color(0xFF63C3C4);
  static const Color _subtext = Color(0xFFB0B0B0);

  final _service = CommunicationService();
  PatientCallSession get _callSession => PatientCallSession.instance;
  VoiceCallService get _voiceCallService => _callSession.voiceCall;
  CallRingtonePlayer get _ringtone => _callSession.ringtone;
  final _controller = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _firstSearchMatchKey = GlobalKey();
  final _voiceRecorder = ChatVoiceRecorderService();
  final _fieldSpeech = FieldSpeechInput.instance;

  StreamSubscription<VoiceCallEvent>? _callStateSub;
  Timer? _recordTimer;

  bool _sending = false;
  bool _searchOpen = false;
  bool _voiceRecordingMode = false;
  bool _sendingVoice = false;
  int _recordElapsedSeconds = 0;
  String? _patientId;
  bool _patientInitiatedCall = false;
  late bool _isArchived;
  bool _archiving = false;

  @override
  void initState() {
    super.initState();
    _isArchived = widget.isArchived;
    _fieldSpeech.addListener(_onFieldSpeechChanged);
    CommunicationService.activeOpenConversationId = widget.conversationId;
    if (!widget.deferMarkReadForVoice) {
      _service.markConversationRead(conversationId: widget.conversationId);
    }
    unawaited(_bootstrapCallHandling());
  }

  @override
  void dispose() {
    _callStateSub?.cancel();
    _recordTimer?.cancel();
    unawaited(_voiceRecorder.dispose());
    _fieldSpeech.removeListener(_onFieldSpeechChanged);
    unawaited(_fieldSpeech.stop());
    _controller.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    if (CommunicationService.activeOpenConversationId == widget.conversationId) {
      CommunicationService.activeOpenConversationId = null;
    }
    super.dispose();
  }

  void _onFieldSpeechChanged() {
    if (!mounted) return;
    setState(() {});
    if (_fieldSpeech.isListeningFor(_searchController)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToFirstSearchMatch();
      });
    }
  }

  Future<void> _dictateToSearch() async {
    final error = await _fieldSpeech.toggleForController(
      _searchController,
      listenMode: ListenMode.search,
    );
    if (error != null && mounted) {
      _showSnack(error);
    }
  }

  Future<void> _bootstrapCallHandling() async {
    final patientId = await _service.currentPatientUserId();
    if (!mounted) return;
    setState(() => _patientId = patientId);
    if (patientId == null || widget.isAuraGuide || widget.staffId.isEmpty) {
      return;
    }

    _callStateSub = _voiceCallService.stateStream.listen(_onVoiceCallEvent);
  }

  void _onVoiceCallEvent(VoiceCallEvent event) {
    if (!mounted) return;

    switch (event.phase) {
      case VoiceCallPhase.ringing:
        _ringtone.start(mode: CallRingtoneMode.outgoing);
      case VoiceCallPhase.connecting:
      case VoiceCallPhase.connected:
      case VoiceCallPhase.incoming:
        _ringtone.stop();
      case VoiceCallPhase.ended:
        _ringtone.stop();
        final shouldLog = _patientInitiatedCall;
        final reason = event.reason ?? 'ended';
        final wasConnected = event.wasConnected;
        final durationSeconds = event.durationSeconds;
        setState(() => _patientInitiatedCall = false);
        if (shouldLog && reason != 'failed') {
          unawaited(_logPatientCall(
            durationSeconds: durationSeconds,
            status: _resolveCallLogStatus(reason, wasConnected),
          ));
        }
      case VoiceCallPhase.idle:
        break;
    }
  }

  String _resolveCallLogStatus(String reason, bool wasConnected) {
    if (reason == 'declined') return 'declined';
    if (reason == 'missed' || reason == 'unanswered') return 'unanswered';
    if (!wasConnected) return 'unanswered';
    return 'completed';
  }

  Future<void> _logPatientCall({
    required int durationSeconds,
    required String status,
  }) async {
    try {
      await _service.sendCallMessage(
        conversationId: widget.conversationId,
        staffId: widget.staffId,
        durationSeconds: durationSeconds,
        status: status,
      );
    } catch (_) {
      /* call log failure should not block UI */
    }
  }

  void _toggleSearch() {
    if (_searchOpen) {
      unawaited(_fieldSpeech.stop());
    }
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _searchController.clear();
      }
    });
    if (_searchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToFirstSearchMatch();
      });
    }
  }

  Future<void> _onArchiveToggle() async {
    if (_archiving || widget.isAuraGuide) return;
    setState(() => _archiving = true);
    try {
      if (_isArchived) {
        await _service.unarchiveConversation(widget.conversationId);
        if (!mounted) return;
        setState(() {
          _isArchived = false;
          _archiving = false;
        });
        _showSnack(
          context.l10n.t('threadRestored', {'title': widget.title}),
        );
      } else {
        await _service.archiveConversation(widget.conversationId);
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.t('threadArchived', {'title': widget.title}),
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _archiving = false);
      _showSnack(
        _isArchived
            ? context.l10n.t('couldNotCancelArchive', {'error': '$error'})
            : context.l10n.t('couldNotArchive', {'error': '$error'}),
      );
    }
  }

  Future<void> _onVoiceCall() async {
    if (widget.isAuraGuide || widget.staffId.isEmpty) {
      _showSnack(context.l10n.t('voiceCallNotAvailable'));
      return;
    }
    if (_voiceCallService.phase != VoiceCallPhase.idle) {
      _showSnack(context.l10n.t('voiceCallNotAvailable'));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          context.l10n.t('voiceCallConfirmTitle'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          context.l10n.t('voiceCallConfirmBody', {'name': widget.title}),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.t('voiceCall')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
    if (!micGranted) {
      if (!mounted) return;
      _showSnack(context.l10n.t('microphonePermissionRequired'));
      return;
    }

    final patientId = _patientId ?? await _service.currentPatientUserId();
    if (!mounted || patientId == null) return;

    try {
      _patientInitiatedCall = true;
      await _voiceCallService.startOutgoing(
        conversationId: widget.conversationId,
        staffId: widget.staffId,
        patientId: patientId,
        remoteName: widget.title,
      );
    } catch (error) {
      _patientInitiatedCall = false;
      if (!mounted) return;
      _showSnack(_voiceCallErrorMessage(error));
    }
  }

  Future<void> _onVideoCall() async {
    if (widget.isAuraGuide || widget.staffId.isEmpty) {
      _showSnack(context.l10n.t('videoCallNotAvailable'));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: Text(
          context.l10n.t('videoCallConfirmTitle'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          context.l10n.t('videoCallConfirmBody', {'name': widget.title}),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.t('videoCall')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _showSnack(context.l10n.t('videoCallNotAvailable'));
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _voiceCallErrorMessage(Object error) {
    final text = error.toString();
    if (error is MissingPluginException ||
        text.contains('MissingPluginException') ||
        text.contains('MissingPlugin')) {
      return context.l10n.t('voiceCallPluginRestartHint');
    }
    return context.l10n.t('voiceCallFailed');
  }

  void _scrollToFirstSearchMatch() {
    final context = _firstSearchMatchKey.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      alignment: 0.3,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty || _sending) return;
    if (widget.isAuraGuide || widget.staffId.isEmpty) {
      _showSnack('Aura Guide replies are automated only.');
      return;
    }

    setState(() => _sending = true);
    try {
      await _service.sendTextMessage(
        conversationId: widget.conversationId,
        staffId: widget.staffId,
        content: text,
      );
      _controller.clear();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _startVoiceRecording() async {
    if (widget.isAuraGuide || widget.staffId.isEmpty) {
      _showSnack('Aura Guide replies are automated only.');
      return;
    }
    if (_voiceRecordingMode || _sendingVoice) return;

    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
    if (!micGranted) {
      if (!mounted) return;
      _showSnack(context.l10n.t('microphonePermissionRequired'));
      return;
    }

    final started = await _voiceRecorder.start();
    if (!started) {
      if (!mounted) return;
      _showSnack(
        context.l10n.t('voiceCaptureFailed', {'error': 'Microphone unavailable'}),
      );
      return;
    }

    setState(() {
      _voiceRecordingMode = true;
      _recordElapsedSeconds = 0;
    });
    _recordTimer?.cancel();
    _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordElapsedSeconds += 1);
      if (_recordElapsedSeconds >= 120) {
        unawaited(_sendVoiceRecording());
      }
    });
  }

  Future<void> _cancelVoiceRecording() async {
    _recordTimer?.cancel();
    await _voiceRecorder.cancel();
    if (!mounted) return;
    setState(() {
      _voiceRecordingMode = false;
      _recordElapsedSeconds = 0;
    });
  }

  Future<void> _sendVoiceRecording() async {
    if (_sendingVoice) return;
    setState(() => _sendingVoice = true);
    _recordTimer?.cancel();

    final recording = await _voiceRecorder.stop();
    if (!mounted) return;

    if (recording == null || recording.durationSeconds < 1) {
      setState(() {
        _sendingVoice = false;
        _voiceRecordingMode = false;
        _recordElapsedSeconds = 0;
      });
      _showSnack(context.l10n.t('voiceMessageTooShort'));
      return;
    }

    try {
      await _service.sendVoiceMessage(
        conversationId: widget.conversationId,
        staffId: widget.staffId,
        audioBytes: recording.bytes,
        mimeType: recording.mimeType,
        fileName: recording.fileName,
        durationSeconds: recording.durationSeconds,
      );
      if (!mounted) return;
      setState(() {
        _sendingVoice = false;
        _voiceRecordingMode = false;
        _recordElapsedSeconds = 0;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sendingVoice = false;
        _voiceRecordingMode = false;
        _recordElapsedSeconds = 0;
      });
      _showSnack(context.l10n.t('voiceMessageFailed'));
    }
  }

  List<ChatListItem> _filterItems(List<ChatListItem> items) {
    final query = _searchController.text.trim().toLowerCase();
    if (!_searchOpen || query.isEmpty) return items;
    final matched = items.where((item) {
      if (item.type == ChatListItemType.divider) return false;
      final haystack = '${item.text ?? ''} ${item.label ?? ''}'.toLowerCase();
      return haystack.contains(query);
    }).toList();
    return ChatDateGrouping.withDateDividers(matched);
  }

  @override
  Widget build(BuildContext context) {
    final searchQuery = _searchController.text.trim();

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
          widget.title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          _ChatHeaderAction(
            label: context.l10n.t('voiceCallA11y'),
            icon: Icons.call_outlined,
            onPressed: _onVoiceCall,
          ),
          _ChatHeaderAction(
            label: context.l10n.t('videoCallA11y'),
            icon: Icons.videocam_outlined,
            onPressed: _onVideoCall,
          ),
          if (!widget.isAuraGuide)
            _ChatHeaderAction(
              label: _isArchived
                  ? context.l10n.t('cancelArchiveConversationA11y')
                  : context.l10n.t('archiveConversationA11y'),
              icon: _isArchived
                  ? Icons.unarchive_outlined
                  : Icons.archive_outlined,
              onPressed: () => unawaited(_onArchiveToggle()),
            ),
          _ChatHeaderAction(
            label: context.l10n.t('searchConversationA11y'),
            icon: Icons.search,
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_searchOpen)
            _ConversationSearchBar(
              controller: _searchController,
              hintText: context.l10n.t('searchMessagesHint'),
              closeLabel: context.l10n.t('closeSearchA11y'),
              micLabel: context.l10n.t('voiceSearch'),
              micListening: _fieldSpeech.isListeningFor(_searchController),
              onMic: () => unawaited(_dictateToSearch()),
              onChanged: (_) {
                setState(() {});
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToFirstSearchMatch();
                });
              },
              onClose: _toggleSearch,
            ),
          Expanded(
            child: StreamBuilder<List<ChatListItem>>(
              stream: _service.watchMessages(
                conversationId: widget.conversationId,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Could not load chat.\n${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _subtext),
                    ),
                  );
                }

                final items = snapshot.data;
                if (items == null) {
                  return const Center(
                    child: CircularProgressIndicator(color: _accent),
                  );
                }

                if (items.isEmpty) {
                  final emptyMessage = context.l10n.t(
                    'noMessagesYetWithName',
                    {'name': widget.title},
                  );
                  return Center(
                    child: AccessibleFocusRegion(
                      label: emptyMessage,
                      child: Text(
                        emptyMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _subtext, height: 1.4),
                      ),
                    ),
                  );
                }

                final visibleItems = _filterItems(items);
                if (visibleItems.isEmpty) {
                  return Center(
                    child: AccessibleFocusRegion(
                      label: context.l10n.t('noSearchResults'),
                      child: Text(
                        context.l10n.t('noSearchResults'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _subtext, height: 1.4),
                      ),
                    ),
                  );
                }

                if (!_searchOpen) {
                  _scrollToBottom();
                }

                var firstMatchAssigned = false;
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  itemCount: visibleItems.length,
                  itemBuilder: (context, index) {
                    final item = visibleItems[index];
                    final isFirstMatch = !firstMatchAssigned &&
                        searchQuery.isNotEmpty &&
                        item.type != ChatListItemType.divider;
                    if (isFirstMatch) {
                      firstMatchAssigned = true;
                    }

                    switch (item.type) {
                      case ChatListItemType.divider:
                        return AccessibleFocusRegion(
                          label: item.label ?? '',
                          child: ChatDateDivider(label: item.label ?? ''),
                        );
                      case ChatListItemType.incoming:
                        if (item.isPhoto) {
                          return AccessibleFocusRegion(
                            label: context.l10n.t('photoMessageBubbleA11y', {
                              'label': item.text ?? 'Photo',
                            }),
                            child: _PhotoBubble(
                              key: isFirstMatch ? _firstSearchMatchKey : null,
                              imageUrl: item.imageUrl,
                              label: item.text ?? 'Photo',
                              time: item.time ?? '',
                              outgoing: false,
                            ),
                          );
                        }
                        if (item.isVoice) {
                          return AccessibleFocusRegion(
                            label: context.l10n.t('voiceMessageBubbleA11y', {
                              'duration': item.text ?? 'Voice message',
                            }),
                            child: _VoiceBubble(
                              key: isFirstMatch ? _firstSearchMatchKey : null,
                              label: item.text ?? 'Voice message',
                              voiceUrl: item.voiceUrl,
                              durationSeconds: item.durationSeconds ?? 0,
                              time: item.time ?? '',
                              outgoing: false,
                            ),
                          );
                        }
                        return AccessibleFocusRegion(
                          label:
                              'Message from ${widget.title}. ${item.text ?? ''}',
                          child: _Bubble(
                            key: isFirstMatch ? _firstSearchMatchKey : null,
                            text: item.text ?? '',
                            time: item.time ?? '',
                            outgoing: false,
                            searchQuery: searchQuery,
                          ),
                        );
                      case ChatListItemType.outgoing:
                        if (item.isPhoto) {
                          return AccessibleFocusRegion(
                            label: context.l10n.t('photoMessageBubbleA11y', {
                              'label': item.text ?? 'Photo',
                            }),
                            child: _PhotoBubble(
                              key: isFirstMatch ? _firstSearchMatchKey : null,
                              imageUrl: item.imageUrl,
                              label: item.text ?? 'Photo',
                              time: item.time ?? '',
                              outgoing: true,
                            ),
                          );
                        }
                        if (item.isVoice) {
                          return AccessibleFocusRegion(
                            label: context.l10n.t('voiceMessageBubbleA11y', {
                              'duration': item.text ?? 'Voice message',
                            }),
                            child: _VoiceBubble(
                              key: isFirstMatch ? _firstSearchMatchKey : null,
                              label: item.text ?? 'Voice message',
                              voiceUrl: item.voiceUrl,
                              durationSeconds: item.durationSeconds ?? 0,
                              time: item.time ?? '',
                              outgoing: true,
                            ),
                          );
                        }
                        return AccessibleFocusRegion(
                          label: 'You said. ${item.text ?? ''}',
                          child: _Bubble(
                            key: isFirstMatch ? _firstSearchMatchKey : null,
                            text: item.text ?? '',
                            time: item.time ?? '',
                            outgoing: true,
                            searchQuery: searchQuery,
                          ),
                        );
                    }
                  },
                );
              },
            ),
          ),
          _voiceRecordingMode
              ? ChatVoiceComposer(
                  recording: true,
                  elapsedSeconds: _recordElapsedSeconds,
                  sending: _sendingVoice,
                  onCancel: () => unawaited(_cancelVoiceRecording()),
                  onSend: () => unawaited(_sendVoiceRecording()),
                )
              : AccessibleFocusRegion(
                  label: context.l10n.t('chatComposerA11y'),
                  child: _Composer(
                    controller: _controller,
                    sending: _sending,
                    onSend: _send,
                    onMic: () => unawaited(_startVoiceRecording()),
                  ),
                ),
        ],
      ),
    );
  }
}

class _ChatHeaderAction extends StatelessWidget {
  const _ChatHeaderAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return AccessibleFocusRegion(
      label: label,
      onActivate: onPressed,
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
        tooltip: label,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      ),
    );
  }
}

class _ConversationSearchBar extends StatelessWidget {
  const _ConversationSearchBar({
    required this.controller,
    required this.hintText,
    required this.closeLabel,
    required this.micLabel,
    required this.micListening,
    required this.onMic,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final String hintText;
  final String closeLabel;
  final String micLabel;
  final bool micListening;
  final VoidCallback onMic;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  static const Color _inputBg = Color(0xFF2A2A2A);
  static const Color _accent = Color(0xFF63C3C4);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _inputBg,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.only(left: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: hintText,
                      textField: true,
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: hintText,
                          hintStyle: const TextStyle(color: Color(0xFF888888)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 12,
                          ),
                        ),
                        onChanged: onChanged,
                      ),
                    ),
                  ),
                  ListeningMicButton(
                    listening: micListening,
                    onPressed: onMic,
                    tooltip: micLabel,
                    variant: ListeningMicButtonVariant.icon,
                    inactiveColor: Colors.white70,
                    activeColor: _accent,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          AccessibleFocusRegion(
            label: closeLabel,
            onActivate: onClose,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white70),
              onPressed: onClose,
              tooltip: closeLabel,
            ),
          ),
        ],
      ),
    );
  }
}


class _VoiceBubble extends StatefulWidget {
  const _VoiceBubble({
    super.key,
    required this.label,
    required this.voiceUrl,
    required this.durationSeconds,
    required this.time,
    required this.outgoing,
  });

  final String label;
  final String? voiceUrl;
  final int durationSeconds;
  final String time;
  final bool outgoing;

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final url = widget.voiceUrl;
    if (url == null || url.isEmpty) return;

    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }

    await _player.play(UrlSource(url));
    if (!mounted) return;
    setState(() => _playing = true);
    _player.onPlayerComplete.first.then((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.outgoing ? Colors.white : const Color(0xFF63C3C4);
    final fg = Colors.black;

    return Align(
      alignment: widget.outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(widget.outgoing ? 16 : 4),
            bottomRight: Radius.circular(widget.outgoing ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AccessibleFocusRegion(
                  label: context.l10n.t('voiceMessagePlayA11y'),
                  onActivate: widget.voiceUrl == null ? null : _togglePlayback,
                  child: IconButton(
                    onPressed: widget.voiceUrl == null ? null : () {
                      unawaited(_togglePlayback());
                    },
                    icon: Icon(
                      _playing ? Icons.stop_circle_outlined : Icons.play_arrow_rounded,
                      color: fg,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.time,
              style: TextStyle(
                color: fg.withValues(alpha: 0.65),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoBubble extends StatelessWidget {
  const _PhotoBubble({
    super.key,
    required this.imageUrl,
    required this.label,
    required this.time,
    required this.outgoing,
  });

  final String? imageUrl;
  final String label;
  final String time;
  final bool outgoing;

  static const Color _incoming = Color(0xFF63C3C4);

  Uint8List? _decodeDataUrl(String dataUrl) {
    final match = RegExp(r'^data:[^;]+;base64,(.+)$').firstMatch(dataUrl);
    if (match == null) return null;
    try {
      return base64Decode(match.group(1)!);
    } catch (_) {
      return null;
    }
  }

  void _openPreview(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _PhotoPreviewPage(imageUrl: url, label: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = outgoing ? Colors.white : _incoming;
    final fg = Colors.black;
    final url = imageUrl;

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(outgoing ? 16 : 4),
            bottomRight: Radius.circular(outgoing ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (url == null || url.isEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(label, style: TextStyle(color: fg, fontSize: 15)),
              )
            else
              AccessibleFocusRegion(
                label: context.l10n.t('photoMessageOpenA11y', {'label': label}),
                onActivate: () => _openPreview(context),
                child: GestureDetector(
                  onTap: () => _openPreview(context),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 240,
                        maxHeight: 280,
                      ),
                      child: _ChatPhotoImage(url: url, decodeDataUrl: _decodeDataUrl),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                time,
                style: TextStyle(
                  color: fg.withValues(alpha: 0.65),
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatPhotoImage extends StatelessWidget {
  const _ChatPhotoImage({
    required this.url,
    required this.decodeDataUrl,
  });

  final String url;
  final Uint8List? Function(String dataUrl) decodeDataUrl;

  @override
  Widget build(BuildContext context) {
    if (url.startsWith('data:')) {
      final bytes = decodeDataUrl(url);
      if (bytes == null) {
        return const _PhotoLoadError();
      }
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => const _PhotoLoadError(),
      );
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return const SizedBox(
          width: 200,
          height: 160,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (_, __, ___) => const _PhotoLoadError(),
    );
  }
}

class _PhotoLoadError extends StatelessWidget {
  const _PhotoLoadError();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 160,
      color: const Color(0xFF2A2A2A),
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, color: Colors.white54),
    );
  }
}

class _PhotoPreviewPage extends StatelessWidget {
  const _PhotoPreviewPage({
    required this.imageUrl,
    required this.label,
  });

  final String imageUrl;
  final String label;

  Uint8List? _decodeDataUrl(String dataUrl) {
    final match = RegExp(r'^data:[^;]+;base64,(.+)$').firstMatch(dataUrl);
    if (match == null) return null;
    try {
      return base64Decode(match.group(1)!);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(label),
      ),
      body: Center(
        child: InteractiveViewer(
          child: imageUrl.startsWith('data:')
              ? () {
                  final bytes = _decodeDataUrl(imageUrl);
                  if (bytes == null) {
                    return const _PhotoLoadError();
                  }
                  return Image.memory(bytes, fit: BoxFit.contain);
                }()
              : Image.network(imageUrl, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.text,
    required this.time,
    required this.outgoing,
    this.searchQuery = '',
  });

  final String text;
  final String time;
  final bool outgoing;
  final String searchQuery;

  static const Color _incoming = Color(0xFF63C3C4);

  @override
  Widget build(BuildContext context) {
    final bg = outgoing ? Colors.white : _incoming;
    final fg = Colors.black;
    final bodyStyle = TextStyle(color: fg, fontSize: 15, height: 1.35);
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(outgoing ? 16 : 4),
            bottomRight: Radius.circular(outgoing ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: searchQuery.isEmpty
                  ? Text(text, style: bodyStyle)
                  : highlightedMessageText(
                      text: text,
                      query: searchQuery,
                      style: bodyStyle,
                      highlightColor: const Color(0xFFFFF176),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: TextStyle(
                color: fg.withValues(alpha: 0.65),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onMic,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onMic;

  static const Color _inputBg = Color(0xFF2A2A2A);
  static const Color _accent = Color(0xFF63C3C4);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: _inputBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: context.l10n.t('typeOrUseVoice'),
                          hintStyle: const TextStyle(color: Color(0xFF888888)),
                          border: InputBorder.none,
                        ),
                        maxLength: 255,
                        buildCounter: (
                          context, {
                          required currentLength,
                          required isFocused,
                          maxLength,
                        }) =>
                            null,
                        onSubmitted: (_) => onSend(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.mic, color: Colors.white70),
                      onPressed: onMic,
                      tooltip: context.l10n.t('voiceMessageMicA11y'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: _accent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: sending ? null : onSend,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.send, color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
