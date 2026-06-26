import 'package:flutter/material.dart';

import '../models/conversation_thread.dart';
import '../utils/chat_date_grouping.dart';
import 'chat_date_divider.dart';

typedef ConversationThreadItemBuilder = Widget Function(
  BuildContext context,
  ConversationThread thread,
);

/// Conversation inbox list with WhatsApp-style date section headers.
class GroupedConversationListView extends StatelessWidget {
  const GroupedConversationListView({
    super.key,
    required this.threads,
    required this.itemBuilder,
    this.padding = EdgeInsets.zero,
    this.itemSpacing = 0,
  });

  final List<ConversationThread> threads;
  final ConversationThreadItemBuilder itemBuilder;
  final EdgeInsetsGeometry padding;
  final double itemSpacing;

  @override
  Widget build(BuildContext context) {
    final entries = ChatDateGrouping.groupConversationsByDate(threads);

    return ListView.builder(
      padding: padding,
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry.isDivider) {
          return ChatDateDivider(label: entry.dividerLabel ?? '');
        }
        final thread = entry.thread!;
        return Padding(
          padding: EdgeInsets.only(bottom: itemSpacing),
          child: itemBuilder(context, thread),
        );
      },
    );
  }
}
