import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

enum VoiceCallPhase {
  idle,
  connecting,
  ringing,
  incoming,
  connected,
  ended,
}

class VoiceCallEvent {
  const VoiceCallEvent({
    required this.phase,
    this.callId,
    this.remoteName,
    this.staffId,
    this.reason,
    this.durationSeconds = 0,
    this.wasConnected = false,
  });

  final VoiceCallPhase phase;
  final String? callId;
  final String? remoteName;
  final String? staffId;
  final String? reason;
  final int durationSeconds;
  final bool wasConnected;
}

class IncomingCallOffer {
  const IncomingCallOffer({
    required this.callId,
    required this.conversationId,
    required this.staffId,
    required this.offerSdp,
    required this.offerType,
  });

  final String callId;
  final String conversationId;
  final String staffId;
  final String offerSdp;
  final String offerType;
}

class VoiceCallService {
  VoiceCallService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const _callSessions = 'callSessions';
  static const _callCounter = 'system/callCounter';
  static const _ringTimeout = Duration(seconds: 45);

  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  final FirebaseFirestore _firestore;
  final _stateController = StreamController<VoiceCallEvent>.broadcast();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  RTCVideoRenderer? _remoteRenderer;
  String? _callId;
  String? _staffId;
  String? _remoteName;
  bool _isCaller = false;
  bool _initiatedByStaff = false;
  DateTime? _connectedAt;
  bool _isMuted = false;
  Timer? _ringTimer;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  bool _hasRemoteDescription = false;

  VoiceCallPhase _phase = VoiceCallPhase.idle;
  VoiceCallPhase get phase => _phase;

  MediaStream? get remoteStream => _remoteStream;
  MediaStream? get localStream => _localStream;
  bool get isMuted => _isMuted;
  DateTime? get connectedAt => _connectedAt;
  String? get activeCallId => _callId;
  String? get remoteName => _remoteName;

  Stream<VoiceCallEvent> get stateStream => _stateController.stream;

  void _emit(
    VoiceCallPhase phase, {
    String? reason,
    int durationSeconds = 0,
    bool wasConnected = false,
  }) {
    _phase = phase;
    if (!_stateController.isClosed) {
      _stateController.add(
        VoiceCallEvent(
          phase: phase,
          callId: _callId,
          remoteName: _remoteName,
          staffId: _staffId,
          reason: reason,
          durationSeconds: durationSeconds,
          wasConnected: wasConnected,
        ),
      );
    }
    if (phase == VoiceCallPhase.ended) {
      _phase = VoiceCallPhase.idle;
    }
  }

  Stream<IncomingCallOffer?> watchIncomingRingingCall({
    required String patientId,
    String? conversationId,
  }) {
    return _firestore
        .collection(_callSessions)
        .where('patientId', isEqualTo: patientId)
        .snapshots()
        .map((snapshot) {
      IncomingCallOffer? latest;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['status'] != 'ringing') continue;
        final initiatedBy = data['initiatedBy']?.toString() ?? '';
        if (initiatedBy == 'patient') continue;
        if (initiatedBy.isNotEmpty && initiatedBy != 'staff') continue;
        final docConversationId = data['conversationId']?.toString() ?? '';
        if (conversationId != null && docConversationId != conversationId) {
          continue;
        }
        final offer = data['offer'];
        if (offer is! Map) continue;
        final sdp = offer['sdp']?.toString() ?? '';
        final type = offer['type']?.toString() ?? '';
        if (sdp.isEmpty || type.isEmpty) continue;
        latest = IncomingCallOffer(
          callId: doc.id,
          conversationId: docConversationId,
          staffId: data['staffId']?.toString() ?? '',
          offerSdp: sdp,
          offerType: type,
        );
      }
      return latest;
    });
  }

  Future<void> startOutgoing({
    required String conversationId,
    required String staffId,
    required String patientId,
    required String remoteName,
    bool initiatedByStaff = false,
  }) async {
    if (_phase != VoiceCallPhase.idle) {
      throw StateError('A call is already in progress.');
    }

    _isCaller = true;
    _initiatedByStaff = initiatedByStaff;
    _staffId = staffId;
    _remoteName = remoteName;
    _emit(VoiceCallPhase.connecting);

    final localIceFrom = initiatedByStaff ? 'staff' : 'patient';
    final remoteIceFrom = initiatedByStaff ? 'patient' : 'staff';

    try {
      await _prepareLocalAudio();
      _pc = await createPeerConnection(_iceServers);
      await _attachLocalTracks();
      _wirePeerConnection(iceFrom: localIceFrom);

      _callId = await _reserveCallId();
      final callRef = _firestore.collection(_callSessions).doc(_callId);
      await callRef.set({
        'callId': _callId,
        'conversationId': conversationId,
        'staffId': staffId,
        'patientId': patientId,
        'status': 'ringing',
        'initiatedBy': initiatedByStaff ? 'staff' : 'patient',
        'offer': null,
        'answer': null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final offer = await _pc!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _pc!.setLocalDescription(offer);
      await callRef.update({
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });

      _watchCallSession(callRef);
      _watchRemoteIceCandidates(from: remoteIceFrom);
      _emit(VoiceCallPhase.ringing);
      _startRingTimeout();
    } catch (error, stackTrace) {
      debugPrint('VoiceCallService.startOutgoing failed: $error\n$stackTrace');
      await _cleanup();
      _emit(VoiceCallPhase.ended, reason: 'failed');
      rethrow;
    }
  }

  Future<void> answerIncoming({
    required IncomingCallOffer incoming,
    required String patientId,
    required String remoteName,
  }) async {
    if (_phase != VoiceCallPhase.idle) {
      throw StateError('A call is already in progress.');
    }

    _isCaller = false;
    _callId = incoming.callId;
    _staffId = incoming.staffId;
    _remoteName = remoteName;
    _emit(VoiceCallPhase.connecting);

    try {
      await _prepareLocalAudio();
      _pc = await createPeerConnection(_iceServers);
      await _attachLocalTracks();
      _wirePeerConnection(iceFrom: 'patient');

      final callRef = _firestore.collection(_callSessions).doc(_callId);
      await _setRemoteDescription(
        RTCSessionDescription(incoming.offerSdp, incoming.offerType),
      );

      final answer = await _pc!.createAnswer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': false,
      });
      await _pc!.setLocalDescription(answer);
      await callRef.update({
        'answer': {'sdp': answer.sdp, 'type': answer.type},
        'status': 'active',
        'connectedAt': FieldValue.serverTimestamp(),
      });

      _watchCallSession(callRef);
      _watchRemoteIceCandidates(from: 'staff');
      _clearRingTimeout();
    } catch (error, stackTrace) {
      debugPrint('VoiceCallService.answerIncoming failed: $error\n$stackTrace');
      await _cleanup();
      _emit(VoiceCallPhase.ended, reason: 'failed');
      rethrow;
    }
  }

  Future<void> declineIncoming(String callId) async {
    try {
      await _firestore.collection(_callSessions).doc(callId).update({
        'status': 'declined',
        'endedAt': FieldValue.serverTimestamp(),
        'endedBy': 'patient',
      });
    } catch (error) {
      debugPrint('VoiceCallService.declineIncoming failed: $error');
    }
  }

  bool toggleMute() {
    final tracks = _localStream?.getAudioTracks() ?? [];
    if (tracks.isEmpty) return _isMuted;
    _isMuted = !_isMuted;
    for (final track in tracks) {
      track.enabled = !_isMuted;
    }
    return _isMuted;
  }

  Future<void> dispose() async {
    if (_phase != VoiceCallPhase.idle) {
      await hangUp(reason: 'ended');
    }
    await _stateController.close();
  }

  Future<void> _prepareLocalAudio() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    await Helper.setSpeakerphoneOn(true);
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = true;
    }
  }

  Future<void> _attachRemotePlayback(MediaStream stream) async {
    _remoteRenderer ??= RTCVideoRenderer();
    await _remoteRenderer!.initialize();
    _remoteRenderer!.srcObject = stream;
    await Helper.setSpeakerphoneOn(true);
  }

  Future<void> _setRemoteDescription(RTCSessionDescription description) async {
    final pc = _pc;
    if (pc == null) return;
    await pc.setRemoteDescription(description);
    _hasRemoteDescription = true;
    await _flushPendingIceCandidates();
  }

  Future<void> _addRemoteIceCandidate(RTCIceCandidate candidate) async {
    final pc = _pc;
    if (pc == null) return;
    if (!_hasRemoteDescription) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }
    try {
      await pc.addCandidate(candidate);
    } catch (error) {
      debugPrint('VoiceCallService addCandidate failed: $error');
    }
  }

  Future<void> _flushPendingIceCandidates() async {
    final pc = _pc;
    if (pc == null || !_hasRemoteDescription) return;
    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      try {
        await pc.addCandidate(candidate);
      } catch (error) {
        debugPrint('VoiceCallService flush addCandidate failed: $error');
      }
    }
  }

  RTCIceCandidate? _parseRemoteCandidate(Map<String, dynamic> data) {
    final candidate = data['candidate']?.toString();
    if (candidate == null || candidate.isEmpty) return null;
    return RTCIceCandidate(
      candidate,
      data['sdpMid']?.toString(),
      (data['sdpMLineIndex'] as num?)?.toInt(),
    );
  }

  Future<void> _attachLocalTracks() async {
    final stream = _localStream;
    final pc = _pc;
    if (stream == null || pc == null) return;
    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }
  }

  Future<void> _handleRemoteTrack(RTCTrackEvent event) async {
    MediaStream? stream;
    if (event.streams.isNotEmpty) {
      stream = event.streams.first;
    } else {
      stream = await createLocalMediaStream('remote');
      await stream.addTrack(event.track);
    }

    _remoteStream = stream;
    await _attachRemotePlayback(stream);
    if (_connectedAt == null) {
      _connectedAt = DateTime.now();
      _clearRingTimeout();
      _emit(VoiceCallPhase.connected);
      if (_callId != null) {
        unawaited(
          _firestore.collection(_callSessions).doc(_callId).update({
            'status': 'active',
            'connectedAt': FieldValue.serverTimestamp(),
          }),
        );
      }
    }
  }

  void _wirePeerConnection({required String iceFrom}) {
    final pc = _pc;
    if (pc == null) return;

    pc.onTrack = (event) {
      unawaited(_handleRemoteTrack(event));
    };

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || _callId == null) return;
      unawaited(
        _firestore
            .collection(_callSessions)
            .doc(_callId)
            .collection('iceCandidates')
            .add({
          'from': iceFrom,
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
          'createdAt': FieldValue.serverTimestamp(),
        }),
      );
    };
  }

  void _watchCallSession(DocumentReference<Map<String, dynamic>> callRef) {
    final sub = callRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists || _pc == null) return;
      final data = snapshot.data();
      if (data == null) return;

      final answer = data['answer'];
      if (_isCaller &&
          answer is Map &&
          (await _pc!.getRemoteDescription()) == null) {
        final sdp = answer['sdp']?.toString() ?? '';
        final type = answer['type']?.toString() ?? '';
        if (sdp.isNotEmpty && type.isNotEmpty) {
          try {
            await _setRemoteDescription(RTCSessionDescription(sdp, type));
          } catch (error) {
            debugPrint('VoiceCallService setRemoteDescription failed: $error');
          }
        }
      }

      final status = data['status']?.toString() ?? '';
      if (_phase == VoiceCallPhase.ended || _phase == VoiceCallPhase.idle) {
        return;
      }
      if (status == 'declined' ||
          status == 'missed' ||
          status == 'unanswered' ||
          status == 'ended') {
        await hangUp(reason: status, skipRemoteUpdate: true);
      }
    });
    _subscriptions.add(sub);
  }

  void _watchRemoteIceCandidates({required String from}) {
    if (_callId == null) return;
    final seen = <String>{};
    final sub = _firestore
        .collection(_callSessions)
        .doc(_callId)
        .collection('iceCandidates')
        .where('from', isEqualTo: from)
        .snapshots()
        .listen((snapshot) {
      final pc = _pc;
      if (pc == null) return;
      for (final doc in snapshot.docs) {
        if (seen.contains(doc.id)) continue;
        seen.add(doc.id);
        final data = doc.data();
        final candidate = _parseRemoteCandidate(data);
        if (candidate == null) continue;
        unawaited(_addRemoteIceCandidate(candidate));
      }
    });
    _subscriptions.add(sub);
  }

  Future<void> hangUp({
    String reason = 'ended',
    bool skipRemoteUpdate = false,
  }) async {
    _clearRingTimeout();
    final wasConnected = _connectedAt != null;
    final durationSeconds = wasConnected
        ? DateTime.now().difference(_connectedAt!).inSeconds.clamp(0, 86400)
        : 0;
    final resolvedReason =
        !wasConnected && reason == 'ended' ? 'unanswered' : reason;

    if (_callId != null && !skipRemoteUpdate) {
      try {
        await _firestore.collection(_callSessions).doc(_callId).update({
          'status': resolvedReason,
          'endedAt': FieldValue.serverTimestamp(),
          'endedBy': _initiatedByStaff ? 'staff' : 'patient',
          'durationSeconds': wasConnected ? durationSeconds : null,
        });
      } catch (error) {
        debugPrint('VoiceCallService.hangUp update failed: $error');
      }
    }

    await _cleanup();
    _emit(
      VoiceCallPhase.ended,
      reason: resolvedReason,
      durationSeconds: durationSeconds,
      wasConnected: wasConnected,
    );
  }

  void _startRingTimeout() {
    _clearRingTimeout();
    _ringTimer = Timer(_ringTimeout, () {
      unawaited(hangUp(reason: 'missed'));
    });
  }

  void _clearRingTimeout() {
    _ringTimer?.cancel();
    _ringTimer = null;
  }

  Future<String> _reserveCallId() async {
    final counterRef = _firestore.doc(_callCounter);
    return _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(counterRef);
      final next = snap.exists ? (snap.data()?['next'] as num?)?.toInt() ?? 1 : 1;
      final callId = 'VC${next.toString().padLeft(5, '0')}';
      transaction.set(counterRef, {'next': next + 1}, SetOptions(merge: true));
      return callId;
    });
  }

  Future<void> _cleanup() async {
    _clearRingTimeout();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _pendingRemoteCandidates.clear();
    _hasRemoteDescription = false;

    final renderer = _remoteRenderer;
    if (renderer != null) {
      renderer.srcObject = null;
      await renderer.dispose();
    }
    _remoteRenderer = null;

    final local = _localStream;
    if (local != null) {
      for (final track in local.getTracks()) {
        await track.stop();
      }
      await local.dispose();
    }
    _localStream = null;

    final remote = _remoteStream;
    if (remote != null) {
      await remote.dispose();
    }
    _remoteStream = null;

    final pc = _pc;
    if (pc != null) {
      await pc.close();
    }
    _pc = null;

    _callId = null;
    _staffId = null;
    _remoteName = null;
    _connectedAt = null;
    _isMuted = false;
    _isCaller = false;
  }
}
