import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../auth_session.dart';
import '../models/chat_list_item.dart';
import '../models/conversation_thread.dart';
import '../models/message_entity.dart';
import '../models/staff_option.dart';
import '../utils/chat_time_format.dart';
import '../utils/clinic_datetime.dart';
import '../utils/localized_staff_name.dart';
import 'app_settings_service.dart';
import 'activity_log_actions.dart';
import 'activity_log_service.dart';
import 'healthcare_staff_service.dart';
import 'user_profile_service.dart';

class CommunicationService {
  CommunicationService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    UserProfileService? profileService,
    HealthcareStaffService? staffService,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _profileService = profileService ?? UserProfileService(),
        _staffService = staffService ?? HealthcareStaffService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final UserProfileService _profileService;
  final HealthcareStaffService _staffService;

  static const _conversations = 'conversations';
  static const _messages = 'messages';
  static const _conversationCounter = 'system/conversationCounter';
  static const _messageCounter = 'system/messageCounter';

  static const auraGuideTitle = 'Aura Guide';
  static const auraGuideStaffId = 'S00000';

  Future<String?> _patientUserId() async {
    final user = AuthSession.resolveUser() ?? _auth.currentUser;
    if (user == null) return null;
    final result =
        await _profileService.loadProfile(user.uid, syncAuthFirst: false);
    final id = (result.data['userId'] as String?)?.trim() ??
        (result.data['patientId'] as String?)?.trim();
    if (id == null || id.isEmpty) return null;

    // Rules read users/{authUid}.userId — keep in sync with profile (like booking).
    await _firestore.collection('users').doc(user.uid).set(
      {'userId': id},
      SetOptions(merge: true),
    );
    return id;
  }

  String? _pickId(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  int _timestampMs(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is String) {
      final parsed = DateTime.tryParse(value.replaceFirst(' ', 'T'));
      if (parsed != null) return parsed.millisecondsSinceEpoch;
    }
    return 0;
  }

  bool _isActiveConversationStatus(String? status) {
    return (status ?? 'active').trim().toLowerCase() == 'active';
  }

  bool _isArchivedConversationStatus(String? status) {
    return (status ?? '').trim().toLowerCase() == 'archived';
  }

  void _clearThreadStreamCaches() {
    _threadsStreamCache = null;
    _archivedThreadsStreamCache = null;
  }

  bool _isValidConversationId(String id) {
    final trimmed = id.trim();
    return trimmed.isNotEmpty;
  }

  Map<String, dynamic> _mapConversation(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return {
      'docId': doc.id,
      'conversationId': data['conversationId']?.toString() ?? doc.id,
      'status': (data['status'] as String?)?.trim() ?? 'Active',
      'participant1Id': _pickId(data, [
        'participant1Id',
        'participant1ID',
        'Participant1ID',
      ]),
      'participant2Id': _pickId(data, [
        'participant2Id',
        'participant2ID',
        'Participant2ID',
      ]),
      'createdAt': data['createdAt'] ?? data['createdDate'],
      'preview': _pickId(data, [
            'lastMessage',
            'lastMessageContent',
            'lastMessageText',
            'preview',
            'messagePreview',
          ]) ??
          (data['lastMessage'] is Map
              ? (data['lastMessage'] as Map)['content']?.toString()
              : null),
      'previewTime': data['lastMessageAt'] ??
          data['lastMessageTime'] ??
          data['lastMessageTimestamp'] ??
          (data['lastMessage'] is Map
              ? (data['lastMessage'] as Map)['timestamp']
              : null),
      'lastSenderId': _pickId(data, [
        'lastSenderId',
        'lastSenderID',
        'lastMessageSenderId',
      ]),
      'patientUnread': data['patientUnread'] == true ||
          data['unreadForPatient'] == true,
    };
  }

  MessageEntity? _parseMessageDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return MessageEntity.fromFirestore(doc.id, doc.data());
  }

  Map<String, dynamic> _messageToRenderMap(MessageEntity message) {
    return {
      'messageId': message.messageId,
      'conversationId': message.conversationId,
      'messageType': message.messageType,
      'content': message.content,
      'timestamp': message.timestamp,
      'deliveryStatus': message.deliveryStatus,
      'senderId': message.senderId,
      'receiverId': message.receiverId,
      'callDuration': message.callDuration,
      'callDurationSeconds': message.callDurationSeconds,
      'deliveredAt': message.deliveredAt,
      'readAt': message.readAt,
      'hiddenFor': message.hiddenFor,
      'deletedForEveryone': message.deletedForEveryone,
      'replyPreview': message.replyPreview,
      'forwardedFromMessageId': message.forwardedFromMessageId,
    };
  }

  bool _isMessageVisibleForPatient(
    Map<String, dynamic> message,
    String patientId,
  ) {
    if (message['deletedForEveryone'] == true) return false;
    final hiddenFor = message['hiddenFor'];
    if (hiddenFor is List && hiddenFor.map((e) => e.toString()).contains(patientId)) {
      return false;
    }
    return true;
  }

  String _otherParticipantId(Map<String, dynamic> conversation, String patientId) {
    final p1 = conversation['participant1Id'] as String?;
    final p2 = conversation['participant2Id'] as String?;
    if (p1 == patientId) return p2 ?? '';
    if (p2 == patientId) return p1 ?? '';
    return '';
  }

  String _staffDisplayName(Map<String, dynamic>? staff, String staffId) {
    if (staff == null) return staffId;
    final name = (staff['name'] as String?)?.trim() ?? staffId;
    final role = staff['role']?.toString() ??
        HealthcareStaffService.roleLabelForCategory(
          HealthcareStaffService.categoryFromData(staff) ?? '',
        );
    return LocalizedStaffName.format(
      name,
      AppSettingsService.instance.settings.languageCode,
      role: role,
    );
  }

  String _initials(String name) {
    final parts = name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    final letters = parts.map((p) => p[0]).take(2).join();
    return letters.isEmpty ? '?' : letters.toUpperCase();
  }

  bool _isAuraGuideParticipant(String id) =>
      id == auraGuideStaffId || id.toUpperCase() == 'AURA';

  Future<Map<String, Map<String, dynamic>>> _staffLookup() async {
    final snap = await _firestore
        .collection(HealthcareStaffService.collection)
        .where('status', isEqualTo: 'Active')
        .get();
    final map = <String, Map<String, dynamic>>{};
    for (final doc in snap.docs) {
      final data = doc.data();
      final sid = _pickId(data, ['staffID', 'staffId', 'staff_id']);
      if (sid != null) map[sid] = data;
    }
    return map;
  }

  void _addConversationDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    Set<String> seen,
    List<Map<String, dynamic>> list,
    String patientId, {
    required bool archivedOnly,
  }) {
    final mapped = _mapConversation(doc);
    final id = mapped['conversationId'] as String;
    if (!seen.add(id)) return;

    final status = mapped['status'] as String?;
    if (archivedOnly) {
      if (!_isArchivedConversationStatus(status)) return;
    } else {
      if (!_isActiveConversationStatus(status)) return;
    }

    final p1 = mapped['participant1Id'] as String?;
    final p2 = mapped['participant2Id'] as String?;
    final isParticipant = p1 == patientId || p2 == patientId;
    if (!isParticipant) return;

    list.add(mapped);
  }

  /// Loads the patient's rows from Firestore `conversations`.
  Future<List<Map<String, dynamic>>> _fetchConversationsForPatient(
    String patientId, {
    bool archivedOnly = false,
  }) async {
    final seen = <String>{};
    final list = <Map<String, dynamic>>[];

    Future<void> runQuery(String field) async {
      final snap = await _firestore
          .collection(_conversations)
          .where(field, isEqualTo: patientId)
          .get();
      for (final doc in snap.docs) {
        _addConversationDoc(
          doc,
          seen,
          list,
          patientId,
          archivedOnly: archivedOnly,
        );
      }
    }

    try {
      await runQuery('participant1Id');
      await runQuery('participant2Id');
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') rethrow;
    }
    try {
      await runQuery('participant1ID');
      await runQuery('participant2ID');
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') rethrow;
    }
    return list;
  }

  Future<Map<String, Map<String, dynamic>>> _latestMessageByConversation(
    List<String> conversationIds,
    String patientId,
  ) async {
    final latest = <String, Map<String, dynamic>>{};
    for (final conversationId in conversationIds) {
      final snap = await _firestore
          .collection(_messages)
          .where('conversationId', isEqualTo: conversationId)
          .get();
      Map<String, dynamic>? best;
      var bestMs = 0;
      for (final doc in snap.docs) {
        final entity = _parseMessageDoc(doc);
        if (entity == null) continue;
        final type = entity.messageType.toLowerCase();
        if (!_isDisplayableMessageType(type)) continue;
        final map = _messageToRenderMap(entity);
        if (!_isMessageVisibleForPatient(map, patientId)) continue;
        final ms = _timestampMs(map['timestamp']);
        if (ms >= bestMs) {
          bestMs = ms;
          best = map;
        }
      }
      if (best != null) latest[conversationId] = best;
    }
    return latest;
  }

  bool _isDisplayableMessageType(String type) {
    return type == 'text' ||
        type == 'voice' ||
        type == 'call' ||
        type == 'photo' ||
        type == 'video' ||
        type == 'document';
  }

  String _previewTextForMessage(Map<String, dynamic> message) {
    final type = (message['messageType'] as String).toLowerCase();
    switch (type) {
      case 'voice':
        final media = _parseVoiceMessageContent(message['content']);
        final durationSeconds = _voiceDurationSeconds(message, media);
        return _formatVoiceMessageLabel(durationSeconds);
      case 'call':
        return _formatCallMessageText(message);
      case 'photo':
        return 'Photo';
      case 'video':
        return 'Video';
      case 'document':
        return 'Document';
      default:
        final content = (message['content'] as String?)?.trim() ?? '';
        return content.isEmpty ? 'Message' : content;
    }
  }

  ConversationThread? _threadFromConversation({
    required Map<String, dynamic> conversation,
    required String patientId,
    required Map<String, Map<String, dynamic>> staffLookup,
    Map<String, dynamic>? latestMessage,
  }) {
    final conversationId = conversation['conversationId'] as String;
    if (!_isValidConversationId(conversationId)) return null;

    final otherId = _otherParticipantId(conversation, patientId);
    if (otherId.isEmpty) return null;

    final isAura = _isAuraGuideParticipant(otherId);
    final staff = staffLookup[otherId];
    final title =
        isAura ? auraGuideTitle : _staffDisplayName(staff, otherId);
    final specialty = isAura
        ? 'Care assistant'
        : HealthcareStaffService.specialtyFromData(staff ?? {});

    final previewFromConversation =
        conversation['preview'] as String?;
    final preview = latestMessage != null
        ? _previewTextForMessage(latestMessage)
        : previewFromConversation?.isNotEmpty == true
            ? previewFromConversation!
            : 'No messages yet';

    final ts = latestMessage?['timestamp'] ??
        conversation['previewTime'] ??
        conversation['createdAt'];
    final lastMs = _timestampMs(ts);

    var unread = conversation['patientUnread'] as bool? ?? false;
    if (!unread && latestMessage != null) {
      unread = latestMessage['receiverId'] == patientId &&
          (latestMessage['deliveryStatus'] as String).toLowerCase() != 'read';
    } else if (!unread && conversation['lastSenderId'] != null) {
      unread = conversation['lastSenderId'] != patientId;
    }

    return ConversationThread(
      conversationId: conversationId,
      title: title,
      preview:
          preview.length > 40 ? '${preview.substring(0, 37)}...' : preview,
      timeLabel: ChatTimeFormat.listTime(ts),
      lastMessageAtMs:
          lastMs > 0 ? lastMs : DateTime.now().millisecondsSinceEpoch,
      unread: unread,
      staffId: isAura ? '' : otherId,
      isAuraGuide: isAura,
      specialty: specialty,
      initials: isAura ? 'AG' : _initials(title),
    );
  }

  Future<List<ConversationThread>> _buildThreadsFromConversations(
    List<Map<String, dynamic>> conversations,
    String patientId,
  ) async {
    if (conversations.isEmpty) return [];

    final staffLookup = await _staffLookup();
    final conversationIds = conversations
        .map((conversation) => conversation['conversationId'] as String)
        .toList();
    final latestByConversation = await _latestMessageByConversation(
      conversationIds,
      patientId,
    );

    final threads = <ConversationThread>[];
    for (final conversation in conversations) {
      final conversationId = conversation['conversationId'] as String;
      final thread = _threadFromConversation(
        conversation: conversation,
        patientId: patientId,
        staffLookup: staffLookup,
        latestMessage: latestByConversation[conversationId],
      );
      if (thread != null) threads.add(thread);
    }

    threads.sort((a, b) => b.lastMessageAtMs.compareTo(a.lastMessageAtMs));
    return threads;
  }

  /// Message list is driven by Firestore `conversations` (preview/time on doc when set).
  Future<List<ConversationThread>> fetchThreads() async {
    final patientId = await _patientUserId();
    if (patientId == null) return [];

    final conversations = await _fetchConversationsForPatient(patientId);
    return _buildThreadsFromConversations(conversations, patientId);
  }

  Future<List<ConversationThread>> fetchArchivedThreads() async {
    final patientId = await _patientUserId();
    if (patientId == null) return [];

    final conversations = await _fetchConversationsForPatient(
      patientId,
      archivedOnly: true,
    );
    return _buildThreadsFromConversations(conversations, patientId);
  }

  Stream<List<ConversationThread>>? _threadsStreamCache;
  Stream<List<ConversationThread>>? _archivedThreadsStreamCache;

  /// Cached stream so rebuilds do not recreate listeners (which caused endless loading).
  Stream<List<ConversationThread>> watchThreads() {
    return _threadsStreamCache ??= _createWatchConversationThreadsStream(
      fetchThreads,
    );
  }

  Stream<List<ConversationThread>> watchArchivedThreads() {
    return _archivedThreadsStreamCache ??=
        _createWatchConversationThreadsStream(fetchArchivedThreads);
  }

  Stream<List<ConversationThread>> _createWatchConversationThreadsStream(
    Future<List<ConversationThread>> Function() fetch,
  ) {
    return Stream.multi((controller) async {
      Timer? debounce;

      Future<void> emitNow() async {
        if (controller.isClosed) return;
        try {
          controller.add(await fetch());
        } catch (e, st) {
          if (!controller.isClosed) {
            controller.addError(e, st);
          }
        }
      }

      void scheduleEmit() {
        debounce?.cancel();
        debounce = Timer(const Duration(milliseconds: 250), emitNow);
      }

      try {
        final patientId = await _patientUserId();
        if (patientId == null) {
          controller.add([]);
          await controller.close();
          return;
        }

        await emitNow();

        final subs = <StreamSubscription<dynamic>>[];
        for (final field in [
          'participant1Id',
          'participant2Id',
          'participant1ID',
          'participant2ID',
        ]) {
          subs.add(
            _firestore
                .collection(_conversations)
                .where(field, isEqualTo: patientId)
                .snapshots()
                .listen((_) => scheduleEmit(), onError: controller.addError),
          );
        }

        controller.onCancel = () {
          debounce?.cancel();
          for (final sub in subs) {
            sub.cancel();
          }
        };
      } catch (e, st) {
        if (!controller.isClosed) {
          controller.addError(e, st);
        }
      }
    });
  }

  List<ChatListItem> buildChatItems(
    List<Map<String, dynamic>> messages,
    String patientId,
  ) {
    final displayMessages = messages
        .where((m) {
          final type = (m['messageType'] as String).toLowerCase();
          return type == 'text' || type == 'call' || type == 'voice';
        })
        .where((m) => _isMessageVisibleForPatient(m, patientId))
        .toList()
      ..sort(
        (a, b) => _timestampMs(a['timestamp']).compareTo(
          _timestampMs(b['timestamp']),
        ),
      );

    final items = <ChatListItem>[];
    String? lastDivider;
    for (final message in displayMessages) {
      final divider = ChatTimeFormat.dividerLabel(message['timestamp']);
      if (divider != lastDivider) {
        items.add(ChatListItem.divider(label: divider));
        lastDivider = divider;
      }
      final isOutgoing = message['senderId'] == patientId;
      final clock = ChatTimeFormat.messageClock(message['timestamp']);
      final type = (message['messageType'] as String).toLowerCase();
      if (type == 'call') {
        final text = _formatCallMessageText(message);
        if (isOutgoing) {
          items.add(ChatListItem.outgoing(text: text, time: clock));
        } else {
          items.add(ChatListItem.incoming(text: text, time: clock));
        }
        continue;
      }

      if (type == 'voice') {
        final media = _parseVoiceMessageContent(message['content']);
        final durationSeconds = _voiceDurationSeconds(message, media);
        final label = _formatVoiceMessageLabel(durationSeconds);
        if (isOutgoing) {
          items.add(
            ChatListItem.outgoingVoice(
              label: label,
              voiceUrl: media?.url,
              durationSeconds: durationSeconds,
              time: clock,
            ),
          );
        } else {
          items.add(
            ChatListItem.incomingVoice(
              label: label,
              voiceUrl: media?.url,
              durationSeconds: durationSeconds,
              time: clock,
            ),
          );
        }
        continue;
      }

      final deleted = message['deletedForEveryone'] == true;
      final replyPreview = (message['replyPreview'] as String?)?.trim();
      final forwarded =
          (message['forwardedFromMessageId'] as String?)?.trim().isNotEmpty ==
              true;
      var text = deleted
          ? 'This message was deleted'
          : message['content'] as String;
      if (!deleted && replyPreview != null && replyPreview.isNotEmpty) {
        text = '↩ $replyPreview\n$text';
      } else if (!deleted && forwarded) {
        text = 'Forwarded\n$text';
      }
      if (isOutgoing) {
        items.add(ChatListItem.outgoing(text: text, time: clock));
      } else {
        items.add(ChatListItem.incoming(text: text, time: clock));
      }
    }
    return items;
  }

  String _formatCallDurationLabel(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatCallMessageText(Map<String, dynamic> message) {
    final content = (message['content'] as String?)?.trim() ?? '';
    if (content.isNotEmpty) return content;

    final rawSeconds = message['callDurationSeconds'];
    final seconds = rawSeconds is num ? rawSeconds.toInt() : 0;
    if (seconds > 0) {
      return 'Voice call · ${_formatCallDurationLabel(seconds)}';
    }

    final duration = message['callDuration'];
    if (duration is num && duration > 0) {
      return 'Voice call · ${duration.toInt()} min';
    }
    return 'Voice call';
  }

  Stream<List<ChatListItem>> watchMessages({
    required String conversationId,
  }) async* {
    final patientId = await _patientUserId();
    if (patientId == null) {
      yield [];
      return;
    }

    await for (final snap in _firestore
        .collection(_messages)
        .where('conversationId', isEqualTo: conversationId)
        .snapshots()) {
      final messages = snap.docs
          .map(_parseMessageDoc)
          .whereType<MessageEntity>()
          .map(_messageToRenderMap)
          .toList();
      yield buildChatItems(messages, patientId);
    }
  }

  Future<DocumentReference<Map<String, dynamic>>> _conversationDocumentRef(
    String conversationId,
  ) async {
    final trimmedId = conversationId.trim();
    if (trimmedId.isEmpty) {
      throw StateError('Invalid conversation.');
    }

    final ref = _firestore.collection(_conversations).doc(trimmedId);
    final snap = await ref.get();
    if (snap.exists) return ref;

    final patientId = await _patientUserId();
    if (patientId == null) {
      throw StateError('Patient profile not found.');
    }

    for (final row in await _fetchConversationsForPatient(
      patientId,
      archivedOnly: true,
    )) {
      if (row['conversationId'] == trimmedId) {
        final docId = row['docId'] as String? ?? trimmedId;
        return _firestore.collection(_conversations).doc(docId);
      }
    }
    for (final row in await _fetchConversationsForPatient(patientId)) {
      if (row['conversationId'] == trimmedId) {
        final docId = row['docId'] as String? ?? trimmedId;
        return _firestore.collection(_conversations).doc(docId);
      }
    }

    throw StateError('Conversation not found.');
  }

  Future<void> archiveConversation(String conversationId) async {
    if (await _patientUserId() == null) {
      throw StateError('Patient profile not found.');
    }

    final ref = await _conversationDocumentRef(conversationId);
    await ref.update({
      'status': 'Archived',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _clearThreadStreamCaches();
  }

  /// Cancel archive: set Firestore `conversations/{id}.status` to `Active`.
  Future<void> unarchiveConversation(String conversationId) async {
    if (await _patientUserId() == null) {
      throw StateError('Patient profile not found.');
    }

    final ref = await _conversationDocumentRef(conversationId);
    await ref.update({
      'status': 'Active',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    _clearThreadStreamCaches();
  }

  String? _conversationIdWithStaff(
    List<Map<String, dynamic>> conversations,
    String patientId,
    String staffId,
  ) {
    for (final conversation in conversations) {
      final other = _otherParticipantId(conversation, patientId);
      if (other == staffId) {
        return conversation['conversationId'] as String;
      }
    }
    return null;
  }

  Future<void> markConversationRead({
    required String conversationId,
  }) async {
    final patientId = await _patientUserId();
    if (patientId == null) return;

    final snap = await _firestore
        .collection(_messages)
        .where('conversationId', isEqualTo: conversationId)
        .get();

    final batch = _firestore.batch();
    var count = 0;
    for (final doc in snap.docs) {
      final msg = _parseMessageDoc(doc);
      if (msg == null) continue;
      if (msg.receiverId != patientId) continue;
      if (msg.deliveryStatus.toLowerCase() == 'read') continue;
      final data = doc.data();
      final updates = <String, dynamic>{
        'deliveryStatus': MessageEntity.deliveryRead,
        'readAt': FieldValue.serverTimestamp(),
      };
      if (data['deliveredAt'] == null) {
        updates['deliveredAt'] = FieldValue.serverTimestamp();
      }
      batch.update(doc.reference, updates);
      count++;
      if (count >= 400) break;
    }
    if (count > 0) await batch.commit();
  }

  Future<String> ensureConversationWithStaff(String staffId) async {
    final patientId = await _patientUserId();
    if (patientId == null) {
      throw StateError('Patient profile not found.');
    }

    final trimmedStaff = staffId.trim();

    final active = await _fetchConversationsForPatient(patientId);
    final activeId =
        _conversationIdWithStaff(active, patientId, trimmedStaff);
    if (activeId != null) return activeId;

    final archived = await _fetchConversationsForPatient(
      patientId,
      archivedOnly: true,
    );
    final archivedId =
        _conversationIdWithStaff(archived, patientId, trimmedStaff);
    if (archivedId != null) {
      await unarchiveConversation(archivedId);
      return archivedId;
    }

    return _createConversation(
      staffId: trimmedStaff,
      patientId: patientId,
    );
  }

  Future<String> _createConversation({
    required String staffId,
    required String patientId,
  }) async {
    final counterRef = _firestore.doc(_conversationCounter);
    return _firestore.runTransaction<String>((transaction) async {
      final counterSnap = await transaction.get(counterRef);
      final next = counterSnap.exists
          ? (counterSnap.data()?['next'] as num?)?.toInt() ?? 1
          : 1;
      final conversationId = 'C${next.toString().padLeft(5, '0')}';
      final ref = _firestore.collection(_conversations).doc(conversationId);
      transaction.set(counterRef, {'next': next + 1}, SetOptions(merge: true));
      transaction.set(ref, {
        'conversationId': conversationId,
        'status': 'Active',
        'participant1Id': staffId,
        'participant2Id': patientId,
        'createdAt': FieldValue.serverTimestamp(),
        'createdDate': _formatCreatedDateString(),
      });
      return conversationId;
    });
  }

  String _formatCreatedDateString() {
    final d = ClinicDateTime.nowClinic();
    final y = d.year;
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$y-$m-$day $hh:$mm:00';
  }

  Future<String> _reserveMessageId() async {
    final counterRef = _firestore.doc(_messageCounter);
    return _firestore.runTransaction<String>((transaction) async {
      final counterSnap = await transaction.get(counterRef);
      final next = counterSnap.exists
          ? (counterSnap.data()?['next'] as num?)?.toInt() ?? 1
          : 1;
      final messageId = 'G${next.toString().padLeft(5, '0')}';
      transaction.set(counterRef, {'next': next + 1}, SetOptions(merge: true));
      return messageId;
    });
  }

  /// Persists one row in `messages` per ERD Table 4.9.
  Future<String> persistMessage(MessageEntity message) async {
    if (!MessageEntity.messageIdPattern.hasMatch(message.messageId)) {
      throw StateError('Invalid message ID.');
    }
    if (!MessageEntity.conversationIdPattern.hasMatch(message.conversationId)) {
      throw StateError('Invalid conversation ID.');
    }

    final ref = _firestore.collection(_messages).doc(message.messageId);
    await ref.set(message.toFirestoreMap(useServerTimestamp: true));
    _clearThreadStreamCaches();
    return message.messageId;
  }

  Future<String> sendTextMessage({
    required String conversationId,
    required String staffId,
    required String content,
  }) async {
    final patientId = await _patientUserId();
    if (patientId == null) {
      throw StateError('Patient profile not found.');
    }

    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw StateError('Message cannot be empty.');
    }
    if (trimmed.length > 255) {
      throw StateError('Message must be 255 characters or less.');
    }

    final messageId = await _reserveMessageId();
    final message = MessageEntity(
      messageId: messageId,
      conversationId: conversationId.trim(),
      messageType: MessageEntity.messageTypeText,
      content: trimmed,
      timestamp: FieldValue.serverTimestamp(),
      deliveryStatus: MessageEntity.deliverySent,
      senderId: patientId,
      receiverId: staffId.trim(),
      callDuration: null,
    );

    await persistMessage(message);
    unawaited(
      ActivityLogService.instance.log(
        action: ActivityLogActions.sendMessage,
        details: 'Sent text message to staff $staffId.',
      ),
    );
    return messageId;
  }

  static const _inlineVoiceMaxBytes = 900000;

  Future<String> sendVoiceMessage({
    required String conversationId,
    required String staffId,
    required Uint8List audioBytes,
    required String mimeType,
    required String fileName,
    required int durationSeconds,
  }) async {
    final patientId = await _patientUserId();
    if (patientId == null) {
      throw StateError('Patient profile not found.');
    }
    if (audioBytes.isEmpty) {
      throw StateError('Recording is empty.');
    }
    if (audioBytes.length > _inlineVoiceMaxBytes) {
      throw StateError('Voice message is too long.');
    }

    final base64Audio = base64Encode(audioBytes);
    final fileData = 'data:$mimeType;base64,$base64Audio';
    final content = jsonEncode({
      'fileData': fileData,
      'fileName': fileName,
      'mimeType': mimeType,
      'durationSeconds': durationSeconds.clamp(0, 600),
    });

    final messageId = await _reserveMessageId();
    final message = MessageEntity(
      messageId: messageId,
      conversationId: conversationId.trim(),
      messageType: MessageEntity.messageTypeVoice,
      content: content,
      timestamp: FieldValue.serverTimestamp(),
      deliveryStatus: MessageEntity.deliverySent,
      senderId: patientId,
      receiverId: staffId.trim(),
      callDuration: durationSeconds > 0
          ? (durationSeconds / 60).ceil().clamp(1, 9999)
          : null,
      callDurationSeconds: durationSeconds > 0 ? durationSeconds : null,
    );

    return persistMessage(message);
  }

  _ParsedVoiceMedia? _parseVoiceMessageContent(dynamic rawContent) {
    final raw = rawContent?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is! Map) return null;
      final fileData = parsed['fileData']?.toString().trim();
      if (fileData != null && fileData.isNotEmpty) {
        return _ParsedVoiceMedia(
          url: fileData,
          fileName: parsed['fileName']?.toString() ?? 'Voice message',
          mimeType: parsed['mimeType']?.toString() ?? '',
        );
      }
      final url = parsed['url']?.toString().trim();
      if (url != null && url.isNotEmpty) {
        return _ParsedVoiceMedia(
          url: url,
          fileName: parsed['fileName']?.toString() ?? 'Voice message',
          mimeType: parsed['mimeType']?.toString() ?? '',
        );
      }
    } catch (_) {
      if (raw.startsWith('data:') || raw.startsWith('http')) {
        return _ParsedVoiceMedia(url: raw, fileName: 'Voice message', mimeType: '');
      }
    }
    return null;
  }

  int _voiceDurationSeconds(
    Map<String, dynamic> message,
    _ParsedVoiceMedia? media,
  ) {
    final rawContent = message['content']?.toString() ?? '';
    try {
      final parsed = jsonDecode(rawContent);
      if (parsed is Map) {
        final fromContent = parsed['durationSeconds'];
        if (fromContent is num) return fromContent.toInt().clamp(0, 600);
      }
    } catch (_) {}

    final rawSeconds = message['callDurationSeconds'];
    if (rawSeconds is num) return rawSeconds.toInt().clamp(0, 600);

    final duration = message['callDuration'];
    if (duration is num && duration > 0) {
      return (duration * 60).round().clamp(0, 600);
    }
    return 0;
  }

  String _formatVoiceMessageLabel(int durationSeconds) {
    if (durationSeconds <= 0) return 'Voice message';
    return 'Voice message · ${_formatCallDurationLabel(durationSeconds)}';
  }

  Future<String> sendCallMessage({
    required String conversationId,
    required String staffId,
    required int durationSeconds,
    required String status,
  }) async {
    final patientId = await _patientUserId();
    if (patientId == null) {
      throw StateError('Patient profile not found.');
    }

    final connectedSeconds = durationSeconds.clamp(0, 86400);
    final content = _buildCallMessageContent(connectedSeconds, status);
    final callDuration = connectedSeconds > 0
        ? (connectedSeconds / 60).ceil().clamp(1, 9999)
        : null;

    final messageId = await _reserveMessageId();
    final message = MessageEntity(
      messageId: messageId,
      conversationId: conversationId.trim(),
      messageType: MessageEntity.messageTypeCall,
      content: content,
      timestamp: FieldValue.serverTimestamp(),
      deliveryStatus: MessageEntity.deliverySent,
      senderId: patientId,
      receiverId: staffId.trim(),
      callDuration: callDuration,
      callDurationSeconds: connectedSeconds > 0 ? connectedSeconds : null,
    );

    await persistMessage(message);
    if (status == 'completed') {
      unawaited(
        ActivityLogService.instance.log(
          action: ActivityLogActions.voiceCall,
          details: 'Voice call with staff $staffId (${connectedSeconds}s).',
          userId: patientId,
        ),
      );
    }
    return messageId;
  }

  String _buildCallMessageContent(int connectedSeconds, String status) {
    if (status == 'unanswered' || status == 'missed') {
      return 'Voice call · Not answered';
    }
    if (status == 'declined') {
      return 'Voice call · Declined';
    }
    if (connectedSeconds > 0) {
      return 'Voice call · ${_formatCallDurationLabel(connectedSeconds)}';
    }
    return 'Voice call';
  }

  Future<String?> currentPatientUserId() => _patientUserId();

  Future<String> resolveStaffDisplayName(String staffId) async {
    final trimmed = staffId.trim();
    if (trimmed.isEmpty) return staffId;
    final lookup = await _staffLookup();
    return _staffDisplayName(lookup[trimmed], trimmed);
  }

  Future<List<StaffOption>> fetchCallableStaff() async {
    final grouped = await _staffService.fetchGroupedByRole();
    final doctors = grouped[HealthcareStaffService.roleDoctor] ?? [];
    if (doctors.isNotEmpty) return doctors;

    final all = <StaffOption>[];
    for (final list in grouped.values) {
      all.addAll(list);
    }
    return all;
  }

  int countUnread(List<ConversationThread> threads) =>
      threads.where((t) => t.unread).length;

  /// Unread conversations for the main menu Communication tile subtitle.
  Stream<int> watchUnreadMessageCount() =>
      watchThreads().map(countUnread);
}

class _ParsedVoiceMedia {
  const _ParsedVoiceMedia({
    required this.url,
    required this.fileName,
    required this.mimeType,
  });

  final String url;
  final String fileName;
  final String mimeType;
}
