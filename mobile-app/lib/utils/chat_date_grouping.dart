import '../models/chat_list_item.dart';
import '../models/conversation_thread.dart';
import 'chat_time_format.dart';

/// Shared date-section grouping for chat transcripts and conversation lists.
abstract final class ChatDateGrouping {
  /// Inserts [ChatListItem.divider] rows before each new calendar day.
  /// Strips any existing dividers from [items] first.
  static List<ChatListItem> withDateDividers(List<ChatListItem> items) {
    final result = <ChatListItem>[];
    String? lastDivider;

    for (final item in items) {
      if (item.type == ChatListItemType.divider) continue;

      final dateKey = item.dateKey ?? '';
      final divider = dateKey.isNotEmpty
          ? ChatTimeFormat.dividerLabelFromDateKey(dateKey)
          : ChatTimeFormat.dividerLabel(null);

      if (divider != lastDivider) {
        result.add(
          ChatListItem.divider(
            label: divider,
            dateKey: dateKey.isEmpty ? null : dateKey,
          ),
        );
        lastDivider = divider;
      }
      result.add(item);
    }

    return result;
  }

  /// Groups inbox threads under WhatsApp-style date section headers.
  static List<ConversationDateEntry> groupConversationsByDate(
    List<ConversationThread> threads,
  ) {
    final entries = <ConversationDateEntry>[];
    String? lastLabel;

    for (final thread in threads) {
      final label = ChatTimeFormat.dividerLabelFromMillis(thread.lastMessageAtMs);
      if (label != lastLabel) {
        entries.add(ConversationDateEntry.divider(label));
        lastLabel = label;
      }
      entries.add(ConversationDateEntry.thread(thread));
    }

    return entries;
  }
}

class ConversationDateEntry {
  const ConversationDateEntry._({
    required this.isDivider,
    this.dividerLabel,
    this.thread,
  });

  const ConversationDateEntry.divider(String label)
      : this._(isDivider: true, dividerLabel: label);

  const ConversationDateEntry.thread(ConversationThread thread)
      : this._(isDivider: false, thread: thread);

  final bool isDivider;
  final String? dividerLabel;
  final ConversationThread? thread;
}
