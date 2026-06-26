import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../models/chat_list_item.dart';
import '../../theme/app_colors.dart';
import '../../widgets/chat_date_divider.dart';

class DoctorChatMessageBubble extends StatelessWidget {
  const DoctorChatMessageBubble({
    super.key,
    required this.item,
  });

  final ChatListItem item;

  @override
  Widget build(BuildContext context) {
    if (item.type == ChatListItemType.divider) {
      return ChatDateDivider(label: item.label ?? '');
    }

    final outgoing = item.type == ChatListItemType.outgoing;
    if (item.isPhoto) {
      return _PhotoBubble(
        imageUrl: item.imageUrl,
        label: item.text ?? 'Photo',
        time: item.time ?? '',
        outgoing: outgoing,
      );
    }
    if (item.isVoice) {
      return _VoiceBubble(
        label: item.text ?? 'Voice message',
        voiceUrl: item.voiceUrl,
        durationSeconds: item.durationSeconds ?? 0,
        time: item.time ?? '',
        outgoing: outgoing,
      );
    }
    if (item.isVideo) {
      return _VideoBubble(
        videoUrl: item.videoUrl,
        label: item.text ?? 'Video',
        time: item.time ?? '',
        outgoing: outgoing,
      );
    }

    final text = item.text ?? '';
    final isVideoCall = item.isCall && text.toLowerCase().contains('video');
    return _TextBubble(
      text: text,
      time: item.time ?? '',
      outgoing: outgoing,
      leadingIcon: item.isCall
          ? (isVideoCall ? Icons.videocam_outlined : Icons.call_outlined)
          : null,
    );
  }
}

class _TextBubble extends StatelessWidget {
  const _TextBubble({
    required this.text,
    required this.time,
    required this.outgoing,
    this.leadingIcon,
  });

  final String text;
  final String time;
  final bool outgoing;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final bg = outgoing
        ? AppColors.accent.withValues(alpha: 0.22)
        : AppColors.card;
    final border = outgoing ? AppColors.accent : AppColors.border;

    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(outgoing ? 14 : 4),
            bottomRight: Radius.circular(outgoing ? 4 : 14),
          ),
          border: Border.all(color: border.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leadingIcon != null) ...[
                  Icon(leadingIcon, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    text,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                time,
                style: const TextStyle(color: AppColors.subtext, fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhotoBubble extends StatelessWidget {
  const _PhotoBubble({
    required this.imageUrl,
    required this.label,
    required this.time,
    required this.outgoing,
  });

  final String? imageUrl;
  final String label;
  final String time;
  final bool outgoing;

  Uint8List? _decodeDataUrl(String dataUrl) {
    final match = RegExp(r'^data:[^;]+;base64,(.+)$').firstMatch(dataUrl);
    if (match == null) return null;
    try {
      return base64Decode(match.group(1)!);
    } catch (_) {
      return null;
    }
  }

  void _openPreview(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _PhotoPreviewPage(imageUrl: url, label: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _openPreview(context),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.72,
          ),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (url == null || url.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(label, style: const TextStyle(color: Colors.white)),
                )
              else
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(11),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: url.startsWith('data:')
                        ? () {
                            final bytes = _decodeDataUrl(url);
                            if (bytes == null) {
                              return const _MediaPlaceholder(icon: Icons.broken_image);
                            }
                            return Image.memory(bytes, fit: BoxFit.cover);
                          }()
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const _MediaPlaceholder(icon: Icons.broken_image),
                          ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    const Icon(Icons.photo, size: 16, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (time.isNotEmpty)
                      Text(
                        time,
                        style: const TextStyle(
                          color: AppColors.subtext,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoiceBubble extends StatefulWidget {
  const _VoiceBubble({
    required this.label,
    required this.voiceUrl,
    required this.durationSeconds,
    required this.time,
    required this.outgoing,
  });

  final String label;
  final String? voiceUrl;
  final int durationSeconds;
  final String time;
  final bool outgoing;

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final url = widget.voiceUrl;
    if (url == null || url.isEmpty) return;

    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }

    await _player.play(UrlSource(url));
    if (!mounted) return;
    setState(() => _playing = true);
    _player.onPlayerComplete.first.then((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        decoration: BoxDecoration(
          color: widget.outgoing
              ? AppColors.accent.withValues(alpha: 0.22)
              : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: widget.voiceUrl == null ? null : _togglePlayback,
              icon: Icon(_playing ? Icons.stop_circle : Icons.play_circle_fill),
              color: AppColors.accent,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  if (widget.time.isNotEmpty)
                    Text(
                      widget.time,
                      style: const TextStyle(
                        color: AppColors.subtext,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VideoBubble extends StatelessWidget {
  const _VideoBubble({
    required this.videoUrl,
    required this.label,
    required this.time,
    required this.outgoing,
  });

  final String? videoUrl;
  final String label;
  final String time;
  final bool outgoing;

  void _openPreview(BuildContext context) {
    final url = videoUrl;
    if (url == null || url.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => _VideoPreviewPage(videoUrl: url, label: label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: outgoing ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: () => _openPreview(context),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          width: MediaQuery.sizeOf(context).width * 0.68,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Container(
                height: 140,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(11),
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.play_circle_outline,
                    color: AppColors.accent,
                    size: 56,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    const Icon(Icons.videocam, size: 16, color: AppColors.accent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (time.isNotEmpty)
                      Text(
                        time,
                        style: const TextStyle(
                          color: AppColors.subtext,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      color: const Color(0xFF2A2A2A),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white54, size: 40),
    );
  }
}

class _PhotoPreviewPage extends StatelessWidget {
  const _PhotoPreviewPage({required this.imageUrl, required this.label});

  final String imageUrl;
  final String label;

  Uint8List? _decodeDataUrl(String dataUrl) {
    final match = RegExp(r'^data:[^;]+;base64,(.+)$').firstMatch(dataUrl);
    if (match == null) return null;
    try {
      return base64Decode(match.group(1)!);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(label),
      ),
      body: Center(
        child: InteractiveViewer(
          child: imageUrl.startsWith('data:')
              ? () {
                  final bytes = _decodeDataUrl(imageUrl);
                  if (bytes == null) {
                    return const _MediaPlaceholder(icon: Icons.broken_image);
                  }
                  return Image.memory(bytes, fit: BoxFit.contain);
                }()
              : Image.network(imageUrl, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

class _VideoPreviewPage extends StatefulWidget {
  const _VideoPreviewPage({required this.videoUrl, required this.label});

  final String videoUrl;
  final String label;

  @override
  State<_VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<_VideoPreviewPage> {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initPlayer());
  }

  Future<void> _initPlayer() async {
    try {
      final url = widget.videoUrl;
      late VideoPlayerController controller;
      if (url.startsWith('data:')) {
        final match = RegExp(r'^data:[^;]+;base64,(.+)$').firstMatch(url);
        if (match == null) throw StateError('Invalid video data.');
        final bytes = base64Decode(match.group(1)!);
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/chat_video_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
        await file.writeAsBytes(bytes);
        controller = VideoPlayerController.file(file);
      } else {
        controller = VideoPlayerController.networkUrl(Uri.parse(url));
      }
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loading = false;
      });
      await controller.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  void dispose() {
    unawaited(_controller?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.label),
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator(color: AppColors.accent)
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not play video.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.subtext),
                    ),
                  )
                : AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: VideoPlayer(_controller!),
                  ),
      ),
    );
  }
}
