import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_route_observer.dart';
import 'chat_page.dart';
import 'l10n/app_localizations.dart';
import 'models/conversation_thread.dart';
import 'models/staff_option.dart';
import 'services/communication_service.dart';
import 'services/patient_call_session.dart';
import 'services/voice_assistant_coordinator.dart';
import 'widgets/grouped_conversation_list_view.dart';
import 'widgets/accessible_focus_region.dart';
import 'widgets/app_back_button.dart';

class CommunicationPage extends StatefulWidget {
  const CommunicationPage({super.key});

  @override
  State<CommunicationPage> createState() => _CommunicationPageState();
}

class _CommunicationPageState extends State<CommunicationPage> with RouteAware {
  static const Color _bg = Color(0xFF000000);
  final _service = CommunicationService();

  /// 0 = Messages, 1 = Calls, 2 = Archived.
  int _view = 0;
  List<StaffOption> _staff = [];
  bool _loadingStaff = true;

  @override
  void initState() {
    super.initState();
    _loadStaff();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      VoiceAssistantCoordinator.instance.setTopRouteLabel('CommunicationPage');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    VoiceAssistantCoordinator.instance.setTopRouteLabel('CommunicationPage');
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  Future<void> _loadStaff() async {
    try {
      final staff = await _service.fetchCallableStaff();
      if (!mounted) return;
      setState(() {
        _staff = staff;
        _loadingStaff = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingStaff = false);
    }
  }

  Future<void> _openChat(
    ConversationThread thread, {
    bool isArchived = false,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (context) => ChatPage(
          conversationId: thread.conversationId,
          title: thread.title,
          staffId: thread.staffId,
          isAuraGuide: thread.isAuraGuide,
          isArchived: isArchived,
        ),
      ),
    );
  }

  Future<void> _openChatWithStaff(StaffOption staff) async {
    try {
      final conversationId = await _service.ensureConversationWithStaff(
        staff.staffId,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => ChatPage(
            conversationId: conversationId,
            title: staff.localizedDisplayName(context.l10n.languageCode),
            staffId: staff.staffId,
            isAuraGuide: false,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not start chat: $e')));
    }
  }

  Future<void> _onCallStaff(StaffOption staff) async {
    try {
      await PatientCallSession.instance.startOutgoingToStaff(
        context: context,
        staffId: staff.staffId,
        remoteName: staff.localizedDisplayName(context.l10n.languageCode),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_voiceCallErrorMessage(error))));
    }
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

  void _showAddContactSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        if (_loadingStaff) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: CircularProgressIndicator(color: Color(0xFF63C3C4)),
            ),
          );
        }
        if (_staff.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No healthcare staff available to contact.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 15),
            ),
          );
        }
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Add contact',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Choose a healthcare provider to message',
                  style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 14),
                ),
              ),
              ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: _staff.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final member = _staff[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF226A6C),
                      child: Text(
                        member.initials,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(
                      member.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chat_bubble_outline,
                      color: Color(0xFF63C3C4),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openChatWithStaff(member);
                    },
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: AppBackButton.appBarLeadingWidth,
        leading: const AppBackButton(),
        title: const Text(
          'Communication',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _SegmentedTabs(
                      selectedIndex: _view < 2 ? _view : null,
                      onChanged: (i) => setState(() => _view = i),
                    ),
                    const SizedBox(height: 10),
                    _ArchivedNavButton(
                      selected: _view == 2,
                      onTap: () => setState(() => _view = 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: switch (_view) {
                  0 => _MessagesTab(service: _service, onOpenChat: _openChat),
                  1 => _CallsTab(
                    loading: _loadingStaff,
                    staff: _staff,
                    onCall: _onCallStaff,
                  ),
                  _ => _ArchivedTab(
                    service: _service,
                    onOpenChat: (thread) => _openChat(thread, isArchived: true),
                  ),
                },
              ),
            ],
          ),
          if (_view == 0)
            Positioned(
              left: 0,
              right: 0,
              bottom: 36,
              child: Center(
                child: _AddContactChip(onPressed: _showAddContactSheet),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentedTabs extends StatelessWidget {
  const _SegmentedTabs({required this.selectedIndex, required this.onChanged});

  /// 0 = Messages, 1 = Calls, null = neither (Archived view).
  final int? selectedIndex;
  final ValueChanged<int> onChanged;

  static const Color _track = Color(0xFF2A2A2A);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _track,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabButton(
              label: 'Messages',
              icon: Icons.chat_bubble_outline,
              selected: selectedIndex == 0,
              onTap: () => onChanged(0),
            ),
          ),
          Expanded(
            child: _TabButton(
              label: 'Calls',
              icon: Icons.phone_outlined,
              selected: selectedIndex == 1,
              onTap: () => onChanged(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchivedNavButton extends StatelessWidget {
  const _ArchivedNavButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  static const Color _track = Color(0xFF2A2A2A);
  static const Color _archiveGold = Color(0xFFE8C547);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _track,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.archive_outlined,
                size: 20,
                color: selected ? _archiveGold : Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                'Archived',
                style: TextStyle(
                  color: selected ? _archiveGold : Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  static const Color _accent = Color(0xFF63C3C4);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _accent : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? Colors.black : Colors.white70,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.black : Colors.white70,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MessagesTab extends StatefulWidget {
  const _MessagesTab({required this.service, required this.onOpenChat});

  final CommunicationService service;
  final ValueChanged<ConversationThread> onOpenChat;

  @override
  State<_MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<_MessagesTab> {
  late final Stream<List<ConversationThread>> _threadsStream;

  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _accent = Color(0xFF63C3C4);

  @override
  void initState() {
    super.initState();
    _threadsStream = widget.service.watchThreads();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConversationThread>>(
      stream: _threadsStream,
      initialData: const [],
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load messages right now.\n'
                'Please try again later or contact your healthcare staff.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _subtext, height: 1.4),
              ),
            ),
          );
        }

        final threads = snapshot.data ?? const [];
        final waiting =
            snapshot.connectionState == ConnectionState.waiting &&
            threads.isEmpty;

        if (waiting) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }

        if (threads.isEmpty) {
          return const _AddContactEmptyState();
        }

        return GroupedConversationListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 88),
          itemSpacing: 12,
          threads: threads,
          itemBuilder: (context, thread) {
            return _ThreadCard(
              thread: thread,
              onTap: () => widget.onOpenChat(thread),
            );
          },
        );
      },
    );
  }
}

class _ArchivedTab extends StatefulWidget {
  const _ArchivedTab({required this.service, required this.onOpenChat});

  final CommunicationService service;
  final ValueChanged<ConversationThread> onOpenChat;

  @override
  State<_ArchivedTab> createState() => _ArchivedTabState();
}

class _ArchivedTabState extends State<_ArchivedTab> {
  late final Stream<List<ConversationThread>> _threadsStream;

  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _accent = Color(0xFF63C3C4);

  @override
  void initState() {
    super.initState();
    _threadsStream = widget.service.watchArchivedThreads();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConversationThread>>(
      stream: _threadsStream,
      initialData: const [],
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load archived conversations.\n${snapshot.error}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _subtext, height: 1.4),
              ),
            ),
          );
        }

        final threads = snapshot.data ?? const [];
        final waiting =
            snapshot.connectionState == ConnectionState.waiting &&
            threads.isEmpty;

        if (waiting) {
          return const Center(child: CircularProgressIndicator(color: _accent));
        }

        if (threads.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'No archived conversations',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _subtext,
                  fontWeight: FontWeight.normal,
                  fontSize: 15,
                ),
              ),
            ),
          );
        }

        return GroupedConversationListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          itemSpacing: 12,
          threads: threads,
          itemBuilder: (context, thread) {
            return _ThreadCard(
              thread: thread,
              onTap: () => widget.onOpenChat(thread),
            );
          },
        );
      },
    );
  }
}

class _AddContactChip extends StatelessWidget {
  const _AddContactChip({required this.onPressed});

  final VoidCallback onPressed;

  static const Color _fill = Color(0xFF63C3C4);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: _fill,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Add contact',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _AddContactEmptyState extends StatelessWidget {
  const _AddContactEmptyState();

  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(32, 32, 32, 96),
        child: Text(
          'No conversations yet',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _subtext,
            fontWeight: FontWeight.normal,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

class _ThreadCard extends StatelessWidget {
  const _ThreadCard({required this.thread, required this.onTap});

  final ConversationThread thread;
  final VoidCallback onTap;

  static const Color _card = Color(0xFF1A1A1A);
  static const Color _subtext = Color(0xFFB0B0B0);

  @override
  Widget build(BuildContext context) {
    return AccessibleFocusRegion(
      label: '${thread.title}. ${thread.preview}',
      onActivate: onTap,
      child: Material(
        color: _card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFF333333)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _ThreadAvatar(thread: thread),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              thread.title,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: thread.unread
                                    ? FontWeight.w800
                                    : FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Text(
                            thread.timeLabel,
                            style: TextStyle(
                              color: thread.unread ? Colors.white70 : _subtext,
                              fontSize: 13,
                              fontWeight: thread.unread
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        thread.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: thread.unread ? Colors.white : _subtext,
                          fontSize: 14,
                          fontWeight: thread.unread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (thread.unread) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF2196F3),
                      shape: BoxShape.circle,
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

class _ThreadAvatar extends StatelessWidget {
  const _ThreadAvatar({required this.thread});

  final ConversationThread thread;

  static const Color _accent = Color(0xFF63C3C4);

  @override
  Widget build(BuildContext context) {
    if (thread.isAuraGuide) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: const Color(0xFF1E3D40),
        child: Icon(Icons.volunteer_activism, color: _accent, size: 28),
      );
    }
    return CircleAvatar(
      radius: 28,
      backgroundColor: const Color(0xFF2C4F7F),
      child: Text(
        thread.initials,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _CallsTab extends StatelessWidget {
  const _CallsTab({
    required this.loading,
    required this.staff,
    required this.onCall,
  });

  final bool loading;
  final List<StaffOption> staff;
  final ValueChanged<StaffOption> onCall;

  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _accent = Color(0xFF63C3C4);
  static const Color _callGreen = Color(0xFF3DDC84);
  static const Color _card = Color(0xFF1A1A1A);

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator(color: _accent));
    }
    if (staff.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No active healthcare staff found.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _subtext, fontSize: 15),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      itemCount: staff.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final member = staff[index];
        return Material(
          color: _card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF333333)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFF226A6C),
                  child: Text(
                    member.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    member.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Material(
                  color: _callGreen,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onCall(member),
                    child: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Icon(Icons.phone, color: Colors.black, size: 22),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
