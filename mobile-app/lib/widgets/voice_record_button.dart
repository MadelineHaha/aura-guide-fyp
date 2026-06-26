import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'accessibility_live_message.dart';
import 'accessible_focus_region.dart';

/// Container button for recording the voice passphrase.
class VoiceRecordButton extends StatelessWidget {
  const VoiceRecordButton({
    super.key,
    required this.isRecording,
    required this.hasValidSample,
    required this.onActivate,
    this.isAnalyzing = false,
    this.onStop,
    this.onRetake,
    this.accessibilityMessage,
    this.heardPreview,
    this.prompt,
    this.accent = const Color(0xFF63C3C4),
    this.subtext = const Color(0xFFB0B0B0),
  });

  final bool isRecording;
  final bool hasValidSample;
  final bool isAnalyzing;
  final VoidCallback onActivate;
  final VoidCallback? onStop;
  final VoidCallback? onRetake;
  final String? accessibilityMessage;
  final String? heardPreview;
  final String? prompt;
  final Color accent;
  final Color subtext;

  @override
  Widget build(BuildContext context) {
    final title = isAnalyzing
        ? context.l10n.t('patientOnboardingPinVerifying')
        : isRecording
        ? (onStop != null ? 'Recording... Tap to stop' : context.l10n.t('voiceRecordRecording'))
        : hasValidSample
            ? context.l10n.t('voiceRecordCaptured')
            : context.l10n.t('voiceRecordTapToRecord');

    final canRecord = !hasValidSample && !isRecording && !isAnalyzing;
    final canTap = canRecord || (isRecording && onStop != null);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AccessibleFocusRegion(
          label: hasValidSample
              ? context.l10n.t('voiceRecordCapturedA11y')
              : context.l10n.t('voiceRecordTapA11y'),
          onActivate: canTap
              ? () {
                  if (isRecording) {
                    onStop?.call();
                  } else {
                    onActivate();
                  }
                }
              : null,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canTap
                  ? () {
                      if (isRecording) {
                        onStop?.call();
                      } else {
                        onActivate();
                      }
                    }
                  : null,
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: isRecording
                      ? const Color(0xFF1A2A2B)
                      : isAnalyzing
                          ? const Color(0xFF1A2A2B)
                          : const Color(0xFF141414),
                  border: Border.all(
                    color: hasValidSample
                        ? const Color(0xFF4CAF6A)
                        : isRecording || isAnalyzing
                            ? accent
                            : const Color(0xFF3A3A3A),
                    width: hasValidSample || isRecording || isAnalyzing ? 1.6 : 1.2,
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                  child: Column(
                    children: [
                      Icon(
                        isAnalyzing
                            ? Icons.hourglass_top
                            : isRecording
                                ? Icons.graphic_eq
                                : Icons.mic_none_outlined,
                        color: hasValidSample
                            ? const Color(0xFF4CAF6A)
                            : accent,
                        size: 28,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        prompt ?? context.l10n.t('voiceRecordPrompt'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: subtext,
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                      if (!hasValidSample &&
                          !isAnalyzing &&
                          heardPreview != null &&
                          heardPreview!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          context.l10n.t('voiceRecordHeard', {
                            'text': heardPreview!,
                          }),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: accent,
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AccessibilityLiveMessage(message: accessibilityMessage),
        if (hasValidSample && onRetake != null) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetake,
            child: Text(
              context.l10n.t('voiceRecordAgain'),
              style: TextStyle(color: accent, fontSize: 15),
            ),
          ),
        ],
      ],
    );
  }
}
