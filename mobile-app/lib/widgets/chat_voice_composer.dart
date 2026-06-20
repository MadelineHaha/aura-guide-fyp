import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'accessible_focus_region.dart';

class ChatVoiceComposer extends StatelessWidget {
  const ChatVoiceComposer({
    super.key,
    required this.recording,
    required this.elapsedSeconds,
    required this.sending,
    required this.onCancel,
    required this.onSend,
  });

  final bool recording;
  final int elapsedSeconds;
  final bool sending;
  final VoidCallback onCancel;
  final VoidCallback onSend;

  static const Color _inputBg = Color(0xFF2A2A2A);
  static const Color _accent = Color(0xFF63C3C4);
  static const Color _recordRed = Color(0xFFE03131);

  String _formatElapsed(int seconds) {
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${remaining.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final statusText = l10n.t('voiceMessageRecording');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _inputBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: recording ? _recordRed : const Color(0xFF3A3A3A),
                    width: recording ? 1.6 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    AccessibleFocusRegion(
                      label: l10n.t('voiceMessageCancelA11y'),
                      onActivate: sending ? null : onCancel,
                      child: IconButton(
                        onPressed: sending ? null : onCancel,
                        icon: const Icon(Icons.close_rounded, color: Colors.white70),
                        tooltip: l10n.t('cancel'),
                      ),
                    ),
                    Icon(
                      recording ? Icons.fiber_manual_record : Icons.graphic_eq_rounded,
                      color: recording ? _recordRed : _accent,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            statusText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatElapsed(elapsedSeconds),
                            style: const TextStyle(
                              color: Color(0xFFB0B0B0),
                              fontSize: 13,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Material(
              color: _accent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: sending || !recording ? null : onSend,
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: sending
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Icon(Icons.send_rounded, color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
