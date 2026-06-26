/// One row in the chat transcript (divider, incoming, or outgoing bubble).
class ChatListItem {
  const ChatListItem.divider({required this.label, this.dateKey})
      : type = ChatListItemType.divider,
        text = null,
        time = null,
        voiceUrl = null,
        durationSeconds = null,
        imageUrl = null,
        videoUrl = null,
        isCall = false;

  const ChatListItem.incoming({
    required this.text,
    required this.time,
    this.isCall = false,
    this.dateKey,
  })  : type = ChatListItemType.incoming,
        label = null,
        voiceUrl = null,
        durationSeconds = null,
        imageUrl = null,
        videoUrl = null;

  const ChatListItem.outgoing({
    required this.text,
    required this.time,
    this.isCall = false,
    this.dateKey,
  })  : type = ChatListItemType.outgoing,
        label = null,
        voiceUrl = null,
        durationSeconds = null,
        imageUrl = null,
        videoUrl = null;

  const ChatListItem.incomingVoice({
    required this.label,
    required this.voiceUrl,
    required this.durationSeconds,
    required this.time,
    this.dateKey,
  })  : type = ChatListItemType.incoming,
        text = label,
        imageUrl = null,
        videoUrl = null,
        isCall = false;

  const ChatListItem.outgoingVoice({
    required this.label,
    required this.voiceUrl,
    required this.durationSeconds,
    required this.time,
    this.dateKey,
  })  : type = ChatListItemType.outgoing,
        text = label,
        imageUrl = null,
        videoUrl = null,
        isCall = false;

  const ChatListItem.incomingPhoto({
    required this.imageUrl,
    required this.time,
    this.label,
    this.dateKey,
  })  : type = ChatListItemType.incoming,
        text = label ?? 'Photo',
        voiceUrl = null,
        durationSeconds = null,
        videoUrl = null,
        isCall = false;

  const ChatListItem.outgoingPhoto({
    required this.imageUrl,
    required this.time,
    this.label,
    this.dateKey,
  })  : type = ChatListItemType.outgoing,
        text = label ?? 'Photo',
        voiceUrl = null,
        durationSeconds = null,
        videoUrl = null,
        isCall = false;

  const ChatListItem.incomingVideo({
    required this.videoUrl,
    required this.time,
    this.label,
    this.dateKey,
  })  : type = ChatListItemType.incoming,
        text = label ?? 'Video',
        voiceUrl = null,
        durationSeconds = null,
        imageUrl = null,
        isCall = false;

  const ChatListItem.outgoingVideo({
    required this.videoUrl,
    required this.time,
    this.label,
    this.dateKey,
  })  : type = ChatListItemType.outgoing,
        text = label ?? 'Video',
        voiceUrl = null,
        durationSeconds = null,
        imageUrl = null,
        isCall = false;

  final ChatListItemType type;
  final String? label;
  final String? text;
  final String? time;
  final String? voiceUrl;
  final int? durationSeconds;
  final String? imageUrl;
  final String? videoUrl;
  final bool isCall;
  final String? dateKey;

  bool get isVoice => voiceUrl != null && voiceUrl!.isNotEmpty;
  bool get isPhoto => imageUrl != null && imageUrl!.isNotEmpty;
  bool get isVideo => videoUrl != null && videoUrl!.isNotEmpty;
}

enum ChatListItemType { divider, incoming, outgoing }
