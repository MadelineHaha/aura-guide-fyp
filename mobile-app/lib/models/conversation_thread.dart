/// Inbox row for the Communication → Messages tab.
class ConversationThread {
  const ConversationThread({
    required this.conversationId,
    required this.title,
    required this.preview,
    required this.timeLabel,
    required this.lastMessageAtMs,
    required this.unread,
    required this.staffId,
    required this.isAuraGuide,
    required this.specialty,
    required this.initials,
  });

  final String conversationId;
  final String title;
  final String preview;
  final String timeLabel;
  final int lastMessageAtMs;
  final bool unread;
  /// Other participant when staff (`S00001`); empty for Aura Guide system thread.
  final String staffId;
  final bool isAuraGuide;
  final String specialty;
  final String initials;
}
