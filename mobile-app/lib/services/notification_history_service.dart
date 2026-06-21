import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/clinic_datetime.dart';

class NotificationHistoryEntry {
  const NotificationHistoryEntry({
    required this.id,
    required this.title,
    required this.body,
    required this.shownAt,
    this.reminderId,
  });

  final String id;
  final String title;
  final String body;
  final DateTime shownAt;
  final String? reminderId;

  String get timeLabel {
    final clinic = ClinicDateTime.fromFirestore(
      Timestamp.fromMillisecondsSinceEpoch(
        shownAt.toUtc().millisecondsSinceEpoch,
      ),
    );
    if (clinic == null) return '—';
    final hour = clinic.hour;
    final minute = clinic.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    return '$h12:$minute $period';
  }

  String get dateLabel {
    final clinic = ClinicDateTime.fromFirestore(
      Timestamp.fromMillisecondsSinceEpoch(
        shownAt.toUtc().millisecondsSinceEpoch,
      ),
    );
    if (clinic == null) return '';
    final y = clinic.year;
    final m = clinic.month.toString().padLeft(2, '0');
    final d = clinic.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/// Persists notification alerts shown on this device.
class NotificationHistoryService {
  NotificationHistoryService._();

  static final NotificationHistoryService instance =
      NotificationHistoryService._();

  static const _storageKey = 'notification_history_v1';
  static const _maxEntries = 100;

  final StreamController<void> _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  Future<void> record({
    required String title,
    required String body,
    String? reminderId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_storageKey) ?? const [];
      final entry = jsonEncode({
        'id': '${DateTime.now().millisecondsSinceEpoch}_${existing.length}',
        'title': title,
        'body': body,
        'reminderId': reminderId,
        'shownAt': DateTime.now().toUtc().millisecondsSinceEpoch,
      });
      final next = [entry, ...existing].take(_maxEntries).toList();
      await prefs.setStringList(_storageKey, next);
      _changes.add(null);
    } catch (error, stack) {
      debugPrint('NotificationHistoryService.record failed: $error\n$stack');
    }
  }

  Future<List<NotificationHistoryEntry>> readAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_storageKey) ?? const [];
      final entries = <NotificationHistoryEntry>[];
      for (final line in raw) {
        try {
          final map = jsonDecode(line) as Map<String, dynamic>;
          final shownMs = map['shownAt'] as num?;
          if (shownMs == null) continue;
          entries.add(
            NotificationHistoryEntry(
              id: (map['id'] as String?) ?? line,
              title: (map['title'] as String?)?.trim() ?? '',
              body: (map['body'] as String?)?.trim() ?? '',
              shownAt: DateTime.fromMillisecondsSinceEpoch(
                shownMs.toInt(),
                isUtc: true,
              ).toLocal(),
              reminderId: (map['reminderId'] as String?)?.trim(),
            ),
          );
        } catch (_) {
          continue;
        }
      }
      return entries;
    } catch (error, stack) {
      debugPrint('NotificationHistoryService.readAll failed: $error\n$stack');
      return const [];
    }
  }
}
