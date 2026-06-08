import 'package:cloud_firestore/cloud_firestore.dart';

/// Table 4.9 — Message entity (`messages` collection, document id = [messageId]).
class MessageEntity {
  const MessageEntity({
    required this.messageId,
    required this.conversationId,
    required this.messageType,
    required this.content,
    required this.timestamp,
    required this.deliveryStatus,
    required this.senderId,
    required this.receiverId,
    this.callDuration,
    this.deliveredAt,
    this.readAt,
    this.hiddenFor = const [],
    this.deletedForEveryone = false,
    this.replyPreview,
    this.forwardedFromMessageId,
  });

  static final RegExp messageIdPattern = RegExp(r'^G\d{5}$');
  static final RegExp conversationIdPattern = RegExp(r'^C\d{5}$');

  static const messageTypeText = 'Text';
  static const messageTypeVoice = 'Voice';
  static const messageTypeCall = 'Call';

  static const deliverySent = 'Sent';
  static const deliveryDelivered = 'Delivered';
  static const deliveryRead = 'Read';

  final String messageId;
  final String conversationId;
  final String messageType;
  final String content;
  final dynamic timestamp;
  final String deliveryStatus;
  final String senderId;
  final String receiverId;
  final int? callDuration;
  final dynamic deliveredAt;
  final dynamic readAt;
  final List<String> hiddenFor;
  final bool deletedForEveryone;
  final String? replyPreview;
  final String? forwardedFromMessageId;

  bool get isValidMessageId => messageIdPattern.hasMatch(messageId);

  Map<String, dynamic> toFirestoreMap({bool useServerTimestamp = false}) {
    return {
      'messageId': messageId,
      'conversationId': conversationId,
      'messageType': messageType,
      'content': content,
      'callDuration': callDuration,
      'timestamp': useServerTimestamp ? FieldValue.serverTimestamp() : timestamp,
      'deliveryStatus': deliveryStatus,
      'senderId': senderId,
      'receiverId': receiverId,
      if (deliveredAt != null) 'deliveredAt': deliveredAt,
      if (readAt != null) 'readAt': readAt,
      if (hiddenFor.isNotEmpty) 'hiddenFor': hiddenFor,
      if (deletedForEveryone) 'deletedForEveryone': deletedForEveryone,
      if (replyPreview != null && replyPreview!.isNotEmpty)
        'replyPreview': replyPreview,
      if (forwardedFromMessageId != null &&
          forwardedFromMessageId!.isNotEmpty)
        'forwardedFromMessageId': forwardedFromMessageId,
    };
  }

  static MessageEntity? fromFirestore(
    String docId,
    Map<String, dynamic> data,
  ) {
    final messageId = (data['messageId'] as String?)?.trim() ?? docId;
    if (!messageIdPattern.hasMatch(messageId)) return null;

    final conversationId = _pick(
      data,
      ['conversationId', 'conversationID', 'Conversation ID'],
    );
    if (conversationId == null || !conversationIdPattern.hasMatch(conversationId)) {
      return null;
    }

    final senderId = _pick(data, ['senderId', 'senderID', 'SenderID']);
    final receiverId = _pick(data, ['receiverId', 'receiverID', 'ReceiverID']);
    if (senderId == null || receiverId == null) return null;

    final rawDuration = data['callDuration'];
    int? callDuration;
    if (rawDuration is int) {
      callDuration = rawDuration;
    } else if (rawDuration is num) {
      callDuration = rawDuration.toInt();
    }

    final hiddenRaw = data['hiddenFor'];
    final hiddenFor = hiddenRaw is List
        ? hiddenRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList()
        : <String>[];

    return MessageEntity(
      messageId: messageId,
      conversationId: conversationId,
      messageType: (data['messageType'] as String?)?.trim() ?? messageTypeText,
      content: (data['content'] as String?)?.trim() ?? '',
      timestamp: data['timestamp'] ?? data['Timestamp'],
      deliveryStatus:
          (data['deliveryStatus'] as String?)?.trim() ?? deliverySent,
      senderId: senderId,
      receiverId: receiverId,
      callDuration: callDuration,
      deliveredAt: data['deliveredAt'],
      readAt: data['readAt'],
      hiddenFor: hiddenFor,
      deletedForEveryone: data['deletedForEveryone'] == true,
      replyPreview: (data['replyPreview'] as String?)?.trim(),
      forwardedFromMessageId:
          (data['forwardedFromMessageId'] as String?)?.trim(),
    );
  }

  static String? _pick(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }
}
