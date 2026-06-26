import 'dart:async';

import 'package:flutter/material.dart';

import 'auth_session.dart';
import 'l10n/app_localizations.dart';
import 'models/patient_notification_item.dart';
import 'services/medication_push_service.dart';
import 'services/notifications_service.dart';
import 'services/notification_history_service.dart';
import 'services/user_profile_service.dart';
import 'widgets/accessible_focus_region.dart';
import 'widgets/app_back_button.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  static const Color _bg = Color(0xFF000000);
  static const Color _subtext = Color(0xFFB0B0B0);
  static const Color _accent = Color(0xFF63C3C4);

  final _service = NotificationsService();
  late final Stream<List<PatientNotificationItem>> _notificationsStream;
  Timer? _refreshTimer;
  bool _markedViewed = false;

  Future<void> _markNotificationsViewed(List<PatientNotificationItem> items) async {
    if (_markedViewed) return;
    _markedViewed = true;
    final patientId = await _servicePatientId();
    if (patientId != null) {
      await _service.markAllViewedForPatient(patientId);
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final upTo = items.isEmpty
        ? now
        : items
            .map((item) => item.sortMillis)
            .fold<int>(now, (max, value) => value > max ? value : max);
    unawaited(NotificationHistoryService.instance.markViewed(upToMillis: upTo));
  }

  Future<String?> _servicePatientId() async {
    final user = AuthSession.resolveUser();
    if (user == null) return null;
    final profile = await UserProfileService().loadProfile(user.uid, syncAuthFirst: false);
    return (profile.data['userId'] as String?)?.trim() ??
        (profile.data['patientId'] as String?)?.trim();
  }

  @override
  void initState() {
    super.initState();
    _notificationsStream = _service.watchForCurrentPatient();
    unawaited(MedicationPushService.instance.registerForReminders());
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _statusLabel(BuildContext context, PatientNotificationStatus status) {
    final l10n = context.l10n;
    return switch (status) {
      PatientNotificationStatus.delivered =>
        l10n.t('notificationStatusDelivered'),
      PatientNotificationStatus.completed =>
        l10n.t('notificationStatusCompleted'),
      PatientNotificationStatus.missed => l10n.t('notificationStatusMissed'),
      PatientNotificationStatus.upcoming =>
        l10n.t('notificationStatusUpcoming'),
      PatientNotificationStatus.pending =>
        l10n.t('notificationStatusPending'),
    };
  }

  Color _statusColor(PatientNotificationStatus status) {
    return switch (status) {
      PatientNotificationStatus.delivered => _accent,
      PatientNotificationStatus.completed => const Color(0xFF8BC34A),
      PatientNotificationStatus.missed => const Color(0xFFE57373),
      PatientNotificationStatus.upcoming => const Color(0xFF90CAF9),
      PatientNotificationStatus.pending => const Color(0xFFFFB74D),
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: AppBackButton.appBarLeadingWidth,
        leading: const AppBackButton(),
        title: Text(
          l10n.t('notification'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<List<PatientNotificationItem>>(
        stream: _notificationsStream,
        initialData: const [],
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final message = l10n.t('couldNotLoadNotifications');
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _subtext, height: 1.4),
                ),
              ),
            );
          }

          final items = snapshot.data ?? const [];
          final waiting =
              snapshot.connectionState == ConnectionState.waiting &&
                  items.isEmpty;

          if (!waiting) {
            unawaited(_markNotificationsViewed(items));
          }

          if (waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _accent),
            );
          }

          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: AccessibleFocusRegion(
                  label: l10n.t('noNotifications'),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_none_outlined,
                        size: 56,
                        color: _subtext.withValues(alpha: 0.7),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.t('noNotifications'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _subtext,
                          fontSize: 16,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              final statusLabel = _statusLabel(context, item.status);
              final statusColor = _statusColor(item.status);
              final a11y = l10n.t('notificationItemA11y', {
                'title': item.title,
                'time': item.timeLabel,
                'body': item.body,
                'status': statusLabel,
              });

              return AccessibleFocusRegion(
                label: a11y,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF141414),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.notifications_outlined,
                          color: _accent,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    statusLabel,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${item.dateLabel} · ${item.timeLabel}',
                              style: const TextStyle(
                                color: _subtext,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.body,
                              style: const TextStyle(
                                color: Color(0xFFD8D8D8),
                                fontSize: 14,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
