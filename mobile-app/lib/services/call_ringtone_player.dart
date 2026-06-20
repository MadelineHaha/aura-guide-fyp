import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

enum CallRingtoneMode {
  /// Du-du-du ringback while placing an outgoing call.
  outgoing,

  /// Ring-ring-ring while receiving an incoming call.
  incoming,
}

/// Repeating call tones for outgoing and incoming voice calls.
class CallRingtonePlayer {
  CallRingtonePlayer()
      : _primary = AudioPlayer(),
        _secondary = AudioPlayer();

  final AudioPlayer _primary;
  final AudioPlayer _secondary;

  static const _asset = 'sounds/sos_beep.wav';
  static const _outgoingCycleInterval = Duration(milliseconds: 2800);
  static const _incomingCycleInterval = Duration(milliseconds: 4500);
  static const _outgoingBeatOffsetsMs = [0, 420, 840];
  static const _incomingBeatOffsetsMs = [0, 1050, 2100];

  CallRingtoneMode _mode = CallRingtoneMode.outgoing;
  bool _playing = false;
  Timer? _cycleTimer;
  int _cycleToken = 0;

  Future<void> start({CallRingtoneMode mode = CallRingtoneMode.outgoing}) async {
    if (_playing && _mode == mode) return;
    await stop();
    _mode = mode;
    _playing = true;
    final token = ++_cycleToken;
    await _playCycle(token);
    final interval =
        mode == CallRingtoneMode.incoming ? _incomingCycleInterval : _outgoingCycleInterval;
    _cycleTimer = Timer.periodic(interval, (_) {
      unawaited(_playCycle(_cycleToken));
    });
  }

  Future<void> _playCycle(int token) async {
    if (!_playing || token != _cycleToken) return;

    final offsets = _mode == CallRingtoneMode.incoming
        ? _incomingBeatOffsetsMs
        : _outgoingBeatOffsetsMs;

    var previousOffset = 0;
    for (final offset in offsets) {
      if (!_playing || token != _cycleToken) return;
      final waitMs = offset - previousOffset;
      if (waitMs > 0) {
        await Future.delayed(Duration(milliseconds: waitMs));
      }
      previousOffset = offset;
      if (!_playing || token != _cycleToken) return;
      if (_mode == CallRingtoneMode.incoming) {
        unawaited(_playIncomingRing());
      } else {
        unawaited(_playOutgoingBeat());
      }
    }
  }

  Future<void> _playOutgoingBeat() async {
    await _primary.setReleaseMode(ReleaseMode.stop);
    await _secondary.setReleaseMode(ReleaseMode.stop);
    unawaited(_primary.play(AssetSource(_asset), volume: 1.0));
    await Future.delayed(const Duration(milliseconds: 45));
    unawaited(_secondary.play(AssetSource(_asset), volume: 0.92));
  }

  Future<void> _playIncomingRing() async {
    await _primary.setReleaseMode(ReleaseMode.stop);
    unawaited(_primary.play(AssetSource(_asset), volume: 0.32));
  }

  Future<void> stop() async {
    if (!_playing) return;
    _playing = false;
    _cycleToken++;
    _cycleTimer?.cancel();
    _cycleTimer = null;
    await Future.wait([
      _primary.stop(),
      _secondary.stop(),
    ]);
  }

  Future<void> dispose() async {
    await stop();
    await Future.wait([
      _primary.dispose(),
      _secondary.dispose(),
    ]);
  }
}
