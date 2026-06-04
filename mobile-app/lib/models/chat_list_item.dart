/// One row in the chat transcript (divider, incoming, or outgoing bubble).
class ChatListItem {
  const ChatListItem.divider({required this.label})
      : type = ChatListItemType.divider,
        text = null,
        time = null;

  const ChatListItem.incoming({required this.text, required this.time})
      : type = ChatListItemType.incoming,
        label = null;

  const ChatListItem.outgoing({required this.text, required this.time})
      : type = ChatListItemType.outgoing,
        label = null;

  final ChatListItemType type;
  final String? label;
  final String? text;
  final String? time;
}

enum ChatListItemType { divider, incoming, outgoing }
