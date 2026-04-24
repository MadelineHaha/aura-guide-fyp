import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'main_menu_page.dart';
import 'services/voice_profile_service.dart';

class VoiceLoginPage extends StatefulWidget {
  const VoiceLoginPage({super.key});

  @override
  State<VoiceLoginPage> createState() => _VoiceLoginPageState();
}

class _VoiceLoginPageState extends State<VoiceLoginPage> {
  final _speech = SpeechToText();
  final _voiceProfile = VoiceProfileService();

  bool _isRecording = false;
  bool _hasSample = false;
  bool _enteringDashboard = false;
  String _capturedPhrase = '';

  static const Color _accent = Color(0xFF63C3C4);
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _isRecording = false);
      return;
    }

    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' && mounted) {
          setState(() => _isRecording = false);
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isRecording = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice capture failed: ${error.errorMsg}')),
        );
      },
    );

    if (!available) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required.')),
      );
      return;
    }

    setState(() {
      _isRecording = true;
      _capturedPhrase = '';
    });

    await _speech.listen(
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 2),
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: (result) {
        if (!mounted) return;
        final normalized = _voiceProfile.normalize(result.recognizedWords);
        setState(() {
          _capturedPhrase = normalized;
          _hasSample = normalized.isNotEmpty;
        });
      },
    );
  }

  Future<void> _enterDashboard() async {
    if (!_hasSample) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please record your voice sample first.',
            style: TextStyle(fontSize: 15),
          ),
        ),
      );
      return;
    }

    setState(() => _enteringDashboard = true);
    try {
      final matched = await _voiceProfile.findMatchingProfile(_capturedPhrase);
      if (matched == null) {
        if (!mounted) return;
        setState(() => _enteringDashboard = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Voice does not match any registered profile.')),
        );
        return;
      }

      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      if (!mounted) return;
      setState(() => _enteringDashboard = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice verified. Welcome ${matched['name'] ?? 'User'}!')),
      );
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (context) => const MainMenuPage(),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _enteringDashboard = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Voice login failed: $e')),
      );
    }
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'Login Account',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 36),
              const Text(
                'Voice Login',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Tap the microphone and speak your passphrase',
                textAlign: TextAlign.center,
                style: TextStyle(color: _subtext, fontSize: 15, height: 1.35),
              ),
              const SizedBox(height: 34),
              Center(
                child: GestureDetector(
                  onTap: _toggleRecording,
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: const BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.mic,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _isRecording ? 'Listening...' : 'Tap to speak',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _capturedPhrase.isEmpty
                    ? 'Please say: "Sign me in"'
                    : 'Captured: "$_capturedPhrase"',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _subtext, fontSize: 15),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final active = _hasSample || (_isRecording && i < 2);
                  return Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: active ? _accent : const Color(0xFF4D4D4D),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 36),
              FilledButton(
                onPressed: _enteringDashboard ? null : _enterDashboard,
                style: FilledButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _enteringDashboard
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text(
                        'Enter Dashboard',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
