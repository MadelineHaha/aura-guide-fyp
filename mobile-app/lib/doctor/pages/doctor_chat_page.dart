import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat_list_item.dart';
import '../../utils/chat_date_grouping.dart';
import '../../services/call_ringtone_player.dart';
import '../../services/communication_service.dart';
import '../../services/device_permissions_service.dart';
import '../../services/staff_profile_service.dart';
import '../../services/voice_call_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/chat_more_menu_sheet.dart';
import '../widgets/doctor_chat_calendar_sheet.dart';
import '../widgets/doctor_chat_message_bubble.dart';
import '../widgets/doctor_theme.dart';

class DoctorChatPage extends StatefulWidget {
  const DoctorChatPage({
    super.key,
    required this.conversationId,
    required this.patientId,
    required this.title,
    this.isAuraGuide = false,
    this.readOnly = false,
    this.isArchived = false,
  });

  final String conversationId;
  final String patientId;
  final String title;
  final bool isAuraGuide;
  final bool readOnly;
  final bool isArchived;

  @override
  State<DoctorChatPage> createState() => _DoctorChatPageState();
}

class _DoctorChatPageState extends State<DoctorChatPage> {
  final _service = CommunicationService();
  final _voiceCallService = VoiceCallService();
  final _ringtone = CallRingtonePlayer();
  final _controller = TextEditingController();
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  StreamSubscription<VoiceCallEvent>? _callStateSub;
  bool _sending = false;
  bool _searchOpen = false;
  bool _isArchived = false;
  bool _staffInitiatedCall = false;
  String? _staffId;
  VoiceCallPhase _callPhase = VoiceCallPhase.idle;

  bool get _isBroadcast =>
      widget.isAuraGuide ||
      widget.conversationId == CommunicationService.auraGuideVirtualConversationId;

  bool get _canCall =>
      !_isBroadcast && widget.patientId.isNotEmpty && !_isArchived;

  @override
  void initState() {
    super.initState();
    _isArchived = widget.isArchived;
    if (!_isBroadcast) {
      _service.markConversationReadForStaff(
        conversationId: widget.conversationId,
      );
    }
    _callStateSub = _voiceCallService.stateStream.listen(_onVoiceCallEvent);
    unawaited(_loadStaffId());
  }

  Future<void> _loadStaffId() async {
    final staffId = await StaffProfileService().currentStaffId();
    if (mounted) setState(() => _staffId = staffId);
  }

  @override
  void dispose() {
    _callStateSub?.cancel();
    unawaited(_ringtone.stop());
    _controller.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onVoiceCallEvent(VoiceCallEvent event) {
    if (!mounted) return;
    setState(() => _callPhase = event.phase);

    switch (event.phase) {
      case VoiceCallPhase.ringing:
        unawaited(_ringtone.start(mode: CallRingtoneMode.outgoing));
      case VoiceCallPhase.connecting:
      case VoiceCallPhase.connected:
      case VoiceCallPhase.incoming:
        unawaited(_ringtone.stop());
      case VoiceCallPhase.ended:
        unawaited(_ringtone.stop());
        final shouldLog = _staffInitiatedCall;
        final reason = event.reason ?? 'ended';
        final wasConnected = event.wasConnected;
        final durationSeconds = event.durationSeconds;
        setState(() => _staffInitiatedCall = false);
        if (shouldLog && reason != 'failed' && !_isBroadcast) {
          unawaited(_logStaffCall(
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

  Future<void> _logStaffCall({
    required int durationSeconds,
    required String status,
  }) async {
    try {
      await _service.sendCallMessageAsStaff(
        conversationId: widget.conversationId,
        patientId: widget.patientId,
        durationSeconds: durationSeconds,
        status: status,
      );
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending || _isBroadcast || _isArchived) return;

    setState(() => _sending = true);
    try {
      await _service.sendTextMessageAsStaff(
        conversationId: widget.conversationId,
        patientId: widget.patientId,
        content: text,
      );
      _controller.clear();
    } catch (e) {
      if (mounted) _showSnack('Could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) _searchController.clear();
    });
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

  Set<String> _dateKeysFromItems(List<ChatListItem> items) {
    return items
        .map((item) => item.dateKey)
        .whereType<String>()
        .where((key) => key.isNotEmpty)
        .toSet();
  }

  void _scrollToDate(String dateKey) {
    if (_searchOpen) {
      setState(() {
        _searchOpen = false;
        _searchController.clear();
      });
    }
    setState(() => _pendingScrollDateKey = dateKey);
  }

  Future<void> _openCalendar(List<ChatListItem> items) async {
    final dates = _dateKeysFromItems(items);
    if (dates.isEmpty) {
      _showSnack('No messages in this conversation yet.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) => DoctorChatCalendarSheet(
        datesWithMessages: dates,
        onDateSelected: _scrollToDate,
      ),
    );
  }

  Future<void> _onVoiceCall() async {
    if (!_canCall) return;
    final staffId = _staffId;
    if (staffId == null) {
      _showSnack('Staff profile not found.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DoctorTheme.surfaceElevated,
        title: const Text('Voice call', style: TextStyle(color: Colors.white)),
        content: Text(
          'Start a voice call with ${widget.title}?',
          style: const TextStyle(color: AppColors.subtext),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Call'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final micGranted =
        await DevicePermissionsService.instance.ensureMicrophone();
    if (!micGranted) {
      if (!mounted) return;
      _showSnack('Microphone permission is required for voice calls.');
      return;
    }

    try {
      _staffInitiatedCall = true;
      await _voiceCallService.startOutgoing(
        conversationId: widget.conversationId,
        staffId: staffId,
        patientId: widget.patientId,
        remoteName: widget.title,
        initiatedByStaff: true,
      );
    } catch (error) {
      _staffInitiatedCall = false;
      if (!mounted) return;
      _showSnack(_voiceCallErrorMessage(error));
    }
  }

  Future<void> _onVideoCall() async {
    if (!_canCall) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DoctorTheme.surfaceElevated,
        title: const Text('Video call', style: TextStyle(color: Colors.white)),
        content: Text(
          'Start a video call with ${widget.title}?',
          style: const TextStyle(color: AppColors.subtext),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Call'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      _showSnack('Video calls will be available in a future update.');
    }
  }

  String _voiceCallErrorMessage(Object error) {
    final text = error.toString();
    if (error is MissingPluginException ||
        text.contains('MissingPluginException') ||
        text.contains('MissingPlugin')) {
      return 'Voice calling requires a full app restart after install.';
    }
    return 'Could not start the voice call.';
  }

  Future<void> _onArchiveToggle() async {
    if (_isBroadcast) return;
    try {
      if (_isArchived) {
        await _service.unarchiveConversationForStaff(widget.conversationId);
        if (!mounted) return;
        setState(() => _isArchived = false);
        _showSnack('${widget.title} restored to active conversations.');
      } else {
        await _service.archiveConversationForStaff(widget.conversationId);
        if (!mounted) return;
        _showSnack('${widget.title} archived.');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not update conversation: $e');
    }
  }

  Future<void> _onDeleteChat() async {
    if (_isBroadcast) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: DoctorTheme.surfaceElevated,
        title: const Text('Delete chat', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete the conversation with ${widget.title}? This cannot be undone.',
          style: const TextStyle(color: AppColors.subtext),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _service.deleteConversationForStaff(widget.conversationId);
      if (!mounted) return;
      _showSnack('Conversation deleted.');
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Could not delete conversation: $e');
    }
  }

  Future<void> _showMoreMenu() async {
    final options = <ChatMoreMenuOption>[
      if (!_isBroadcast)
        ChatMoreMenuOption(
          id: 'archive',
          icon: _isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
          label: _isArchived ? 'Restore conversation' : 'Archive',
        ),
      const ChatMoreMenuOption(
        id: 'search',
        icon: Icons.search,
        label: 'Search in chat',
      ),
      if (!_isBroadcast)
        const ChatMoreMenuOption(
          id: 'delete',
          icon: Icons.delete_outline,
          label: 'Delete chat',
          color: Colors.redAccent,
          destructive: true,
        ),
    ];

    final action = await ChatMoreMenuSheet.show(context, options: options);

    switch (action) {
      case 'archive':
        await _onArchiveToggle();
      case 'search':
        if (!_searchOpen) _toggleSearch();
      case 'delete':
        await _onDeleteChat();
    }
  }

  Future<void> _endCall() async {
    await _voiceCallService.hangUp(
      reason: _callPhase == VoiceCallPhase.connected ? 'ended' : 'unanswered',
    );
  }

  String get _callStatusLabel {
    switch (_callPhase) {
      case VoiceCallPhase.connecting:
        return 'Connecting…';
      case VoiceCallPhase.ringing:
        return 'Calling…';
      case VoiceCallPhase.connected:
        return 'Connected';
      case VoiceCallPhase.incoming:
        return 'Incoming call';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final inCall = _callPhase == VoiceCallPhase.connecting ||
        _callPhase == VoiceCallPhase.ringing ||
        _callPhase == VoiceCallPhase.connected;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: Colors.white,
        leading: const AppBackButton(),
        title: Row(
          children: [
            if (_isBroadcast)
              Container(
                width: 34,
                height: 34,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: DoctorTheme.surfaceHighlight,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: DoctorTheme.portalAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: const Icon(
                  Icons.campaign_outlined,
                  color: DoctorTheme.portalAccent,
                  size: 20,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  if (_isBroadcast)
                    const Text(
                      'Broadcast messages from clinic',
                      style: TextStyle(
                        color: AppColors.subtext,
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                      ),
                    )
                  else if (_isArchived)
                    const Text(
                      'Archived',
                      style: TextStyle(
                        color: AppColors.subtext,
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_canCall) ...[
            _HeaderIconButton(
              icon: Icons.call_outlined,
              tooltip: 'Voice call',
              onPressed: inCall ? null : _onVoiceCall,
            ),
            _HeaderIconButton(
              icon: Icons.videocam_outlined,
              tooltip: 'Video call',
              onPressed: _onVideoCall,
            ),
          ],
          _HeaderIconButton(
            icon: Icons.search,
            tooltip: 'Search in conversation',
            onPressed: _toggleSearch,
            isActive: _searchOpen,
          ),
          _HeaderIconButton(
            icon: Icons.calendar_today_outlined,
            tooltip: 'Jump to date',
            onPressed: () {
              if (_latestItems.isEmpty) {
                _showSnack('No messages in this conversation yet.');
                return;
              }
              unawaited(_openCalendar(_latestItems));
            },
          ),
          _HeaderIconButton(
            icon: Icons.more_vert,
            tooltip: 'More options',
            onPressed: _showMoreMenu,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_searchOpen)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search in conversation',
                            hintStyle: const TextStyle(color: AppColors.subtext),
                            filled: true,
                            fillColor: AppColors.card,
                            prefixIcon: const Icon(
                              Icons.search,
                              color: AppColors.subtext,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: AppColors.border,
                              ),
                            ),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      IconButton(
                        onPressed: _toggleSearch,
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              Expanded(child: _buildMessageList()),
              if (_isBroadcast)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: DoctorTheme.surfaceCard(),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppColors.accent,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Broadcast messages are read-only and visible to everyone.',
                              style: TextStyle(
                                color: AppColors.subtext,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (!widget.readOnly && !_isArchived)
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Type a message…',
                              hintStyle:
                                  const TextStyle(color: AppColors.subtext),
                              filled: true,
                              fillColor: AppColors.card,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                                borderSide: const BorderSide(
                                  color: AppColors.border,
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send),
                          style: IconButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (inCall) _CallOverlay(
            name: widget.title,
            status: _callStatusLabel,
            onEnd: _endCall,
          ),
        ],
      ),
    );
  }

  List<ChatListItem> _latestItems = const [];
  String? _pendingScrollDateKey;
  final _scrollTargetKeys = <String, GlobalKey>{};

  Widget _buildMessageList() {
    return StreamBuilder<List<ChatListItem>>(
      stream: _service.watchMessagesForStaff(
        conversationId: widget.conversationId,
      ),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        final items = snapshot.data!;
        _latestItems = items;
        if (items.isEmpty) {
          return const Center(
            child: Text(
              'No messages yet.',
              style: TextStyle(color: AppColors.subtext),
            ),
          );
        }

        final visibleItems = _filterItems(items);
        if (visibleItems.isEmpty) {
          return const Center(
            child: Text(
              'No messages match your search.',
              style: TextStyle(color: AppColors.subtext),
            ),
          );
        }

        _scrollTargetKeys.clear();
        for (final item in items) {
          final dateKey = item.dateKey;
          if (dateKey != null && dateKey.isNotEmpty) {
            _scrollTargetKeys.putIfAbsent(dateKey, GlobalKey.new);
          }
        }

        if (_pendingScrollDateKey != null) {
          final targetKey = _scrollTargetKeys[_pendingScrollDateKey];
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (targetKey?.currentContext != null) {
              Scrollable.ensureVisible(
                targetKey!.currentContext!,
                alignment: 0.2,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            } else {
              _showSnack('No messages were found for the selected date.');
            }
            if (mounted) setState(() => _pendingScrollDateKey = null);
          });
        }

        if (!_searchOpen && _pendingScrollDateKey == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(
                _scrollController.position.maxScrollExtent,
              );
            }
          });
        }

        return ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: visibleItems.length,
          itemBuilder: (context, index) {
            final item = visibleItems[index];
            final key = item.dateKey != null
                ? _scrollTargetKeys[item.dateKey!]
                : null;
            final bubble = DoctorChatMessageBubble(item: item);
            if (key != null) {
              return KeyedSubtree(key: key, child: bubble);
            }
            return bubble;
          },
        );
      },
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isActive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(
        icon,
        color: isActive ? AppColors.accent : Colors.white,
      ),
    );
  }
}

class _CallOverlay extends StatelessWidget {
  const _CallOverlay({
    required this.name,
    required this.status,
    required this.onEnd,
  });

  final String name;
  final String status;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.88),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: DoctorTheme.portalGlow,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  status,
                  style: const TextStyle(color: AppColors.subtext, fontSize: 15),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: onEnd,
                  icon: const Icon(Icons.call_end),
                  label: const Text('End call'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
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
