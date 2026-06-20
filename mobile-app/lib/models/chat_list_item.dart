/// One row in the chat transcript (divider, incoming, or outgoing bubble).
class ChatListItem {
  const ChatListItem.divider({required this.label})
      : type = ChatListItemType.divider,
        text = null,
        time = null,
        voiceUrl = null,
        durationSeconds = null;

  const ChatListItem.incoming({required this.text, required this.time})
      : type = ChatListItemType.incoming,
        label = null,
        voiceUrl = null,
        durationSeconds = null;

  const ChatListItem.outgoing({required this.text, required this.time})
      : type = ChatListItemType.outgoing,
        label = null,
        voiceUrl = null,
        durationSeconds = null;

  const ChatListItem.incomingVoice({
    required this.label,
    required this.voiceUrl,
    required this.durationSeconds,
    required this.time,
  })  : type = ChatListItemType.incoming,
        text = label;

  const ChatListItem.outgoingVoice({
    required this.label,
    required this.voiceUrl,
    required this.durationSeconds,
    required this.time,
  })  : type = ChatListItemType.outgoing,
        text = label;

  final ChatListItemType type;
  final String? label;
  final String? text;
  final String? time;
  final String? voiceUrl;
  final int? durationSeconds;

  bool get isVoice => voiceUrl != null && voiceUrl!.isNotEmpty;
}

enum ChatListItemType { divider, incoming, outgoing }
