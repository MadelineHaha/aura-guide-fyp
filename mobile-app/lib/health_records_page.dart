import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/health_record_item.dart';
import 'services/health_record_audio_service.dart';
import 'services/health_records_service.dart';
import 'widgets/accessible_focus_region.dart';
import 'widgets/app_back_button.dart';
import 'widgets/audio_feedback_title.dart';

class HealthRecordsPage extends StatefulWidget {
  const HealthRecordsPage({super.key});

  @override
  State<HealthRecordsPage> createState() => _HealthRecordsPageState();
}

class _HealthRecordsPageState extends State<HealthRecordsPage> {
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFF999999);
  static const Color _accent = Color(0xFF63C3C4);

  final _service = HealthRecordsService();
  final _audio = HealthRecordAudioService();
  late final Stream<List<HealthRecordItem>> _recordsStream;
  String? _playingRecordId;
  bool _audioBusy = false;

  @override
  void initState() {
    super.initState();
    _recordsStream = _service.watchForCurrentPatient();
  }

  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  Future<void> _onPlayAudio(HealthRecordItem record) async {
    if (_playingRecordId == record.recordId && _audioBusy) {
      await _audio.stop();
      if (!mounted) return;
      setState(() {
        _playingRecordId = null;
        _audioBusy = false;
      });
      return;
    }

    if (_audioBusy) {
      await _audio.stop();
    }

    setState(() {
      _audioBusy = true;
      _playingRecordId = record.recordId;
    });

    try {
      await _audio.play(record);
    } catch (e) {
      if (!mounted) return;
      final message = e is StateError
          ? e.message
          : 'Could not play audio. Stop the app and run flutter run again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _playingRecordId = null;
          _audioBusy = false;
        });
      }
    }
  }

  Future<void> _onExport(HealthRecordItem record) async {
    final buffer = StringBuffer()
      ..write(record.recordType)
      ..writeln()
      ..writeln('Date: ${record.dateCreated}')
      ..writeln('Doctor: ${record.doctorName}')
      ..writeln()
      ..write(record.summary);
    if (record.filePath.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('File: ${record.fileType} (${record.filePath})');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Record summary copied to clipboard.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: AppBackButton.appBarLeadingWidth,
        leading: const AppBackButton(),
        title: AudioFeedbackTitle(
          label: 'Health Records',
          child: const Text(
            'Health Records',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<List<HealthRecordItem>>(
        stream: _recordsStream,
        initialData: const [],
        builder: (context, snapshot) {
          final records = snapshot.data ?? const [];
          final permissionDenied = snapshot.hasError &&
              snapshot.error.toString().contains('permission-denied');

          if (snapshot.hasError && !permissionDenied) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load health records.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _subtext, height: 1.4),
                ),
              ),
            );
          }

          if (permissionDenied || records.isEmpty) {
            final waiting = !permissionDenied &&
                snapshot.connectionState == ConnectionState.waiting &&
                records.isEmpty;
            if (waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _accent),
              );
            }
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'There is no health record yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _subtext, fontSize: 15),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: records.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, index) {
              final record = records[index];
              return AccessibleFocusRegion(
                label:
                    '${record.recordType}. ${record.dateCreated}. ${record.doctorName}. ${record.summary}',
                child: _HealthRecordCard(
                  record: record,
                  isPlayingAudio: _playingRecordId == record.recordId,
                  onPlayAudio: () => _onPlayAudio(record),
                  onExport: () => _onExport(record),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _HealthRecordCard extends StatelessWidget {
  const _HealthRecordCard({
    required this.record,
    required this.isPlayingAudio,
    required this.onPlayAudio,
    required this.onExport,
  });

  final HealthRecordItem record;
  final bool isPlayingAudio;
  final VoidCallback onPlayAudio;
  final VoidCallback onExport;

  static const Color _card = Color(0xFF1A1A1A);
  static const Color _subtext = Color(0xFF999999);
  static const Color _accent = Color(0xFF63C3C4);
  static const Color _exportBg = Color(0xFF333333);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF333333)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  record.recordType,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                record.dateCreated,
                style: const TextStyle(color: _subtext, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            record.doctorName,
            style: const TextStyle(color: _subtext, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text(
            record.summary,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: isPlayingAudio ? 'Stop Audio' : 'Play Audio',
                  backgroundColor: _accent,
                  foregroundColor: Colors.black,
                  onTap: onPlayAudio,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  label: 'Export',
                  backgroundColor: _exportBg,
                  foregroundColor: Colors.white,
                  onTap: onExport,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: foregroundColor,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
