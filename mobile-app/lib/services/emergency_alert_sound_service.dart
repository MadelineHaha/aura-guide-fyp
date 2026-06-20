import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Plays a loud alert tone on each SOS countdown second.
class EmergencyAlertSoundService {
  EmergencyAlertSoundService._();

  static final EmergencyAlertSoundService instance =
      EmergencyAlertSoundService._();

  static const _channel = MethodChannel(
    'com.example.aura_guide_fyp/emergency_sound',
  );

  final AudioPlayer _player = AudioPlayer();
  bool _contextReady = false;
  bool _assetReady = false;

  Future<void> prepare() async {
    if (!kIsWeb && Platform.isAndroid) {
      return;
    }
    await _ensureAudioContext();
    await _ensureToneAsset();
  }

  Future<void> playCountdownAlert() async {
    await HapticFeedback.heavyImpact();

    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('playAlertBeep');
        return;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('EmergencyAlertSoundService Android beep failed: $e');
        }
      }
    }

    try {
      await _ensureAudioContext();
      final file = await _ensureToneAsset();
      await _player.stop();
      await _player.setVolume(1.0);
      await _player.setPlayerMode(PlayerMode.mediaPlayer);
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(DeviceFileSource(file.path));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('EmergencyAlertSoundService file beep failed: $e');
      }
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  Future<void> _ensureAudioContext() async {
    if (_contextReady) return;
    await AudioPlayer.global.setAudioContext(
      AudioContext(
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: {AVAudioSessionOptions.mixWithOthers},
        ),
        android: AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gain,
        ),
      ),
    );
    _contextReady = true;
  }

  Future<File> _ensureToneAsset() async {
    if (_assetReady) {
      final dir = await getTemporaryDirectory();
      return File('${dir.path}/sos_countdown_alert.wav');
    }

    final bytes = await rootBundle.load('assets/sounds/sos_beep.wav');
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/sos_countdown_alert.wav');
    await file.writeAsBytes(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      flush: true,
    );
    _assetReady = true;
    return file;
  }

  Future<void> stop() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('release');
      } catch (_) {
        // Ignore release errors.
      }
    }
    await _player.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
