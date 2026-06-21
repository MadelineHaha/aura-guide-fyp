import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth_session.dart';
import 'user_profile_service.dart';

/// Writes immutable audit entries to Firestore for the admin logs page.
class ActivityLogService {
  ActivityLogService._();

  static final ActivityLogService instance = ActivityLogService._();

  static const _collection = 'activityLogs';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final UserProfileService _profileService = UserProfileService();
  String? _cachedIp;
  DateTime? _cachedIpAt;

  /// Pre-resolve the device public IP so later log writes are not delayed.
  Future<void> warmUp() async {
    await _resolveClientIp();
  }

  Future<String> _resolveClientIp() async {
    final cachedAt = _cachedIpAt;
    if (_cachedIp != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 5)) {
      return _cachedIp!;
    }

    const endpoints = [
      'https://api.ipify.org?format=json',
      'https://api64.ipify.org?format=json',
      'https://ifconfig.me/ip',
      'https://icanhazip.com',
    ];

    for (final endpoint in endpoints) {
      try {
        final ip = await _fetchIpFromEndpoint(endpoint);
        if (ip != null && ip.isNotEmpty) {
          _cachedIp = ip;
          _cachedIpAt = DateTime.now();
          return ip;
        }
      } catch (error) {
        debugPrint('ActivityLogService IP lookup failed ($endpoint): $error');
      }
    }

    return _cachedIp ?? '—';
  }

  Future<String?> _fetchIpFromEndpoint(String url) async {
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return null;

    final body = response.body.trim();
    if (body.isEmpty) return null;

    if (url.contains('format=json')) {
      final data = jsonDecode(body);
      if (data is Map) {
        final ip = (data['ip'] as String?)?.trim();
        if (ip != null && ip.isNotEmpty) return ip;
      }
      return null;
    }

    if (_looksLikeIp(body)) return body;
    return null;
  }

  bool _looksLikeIp(String value) {
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(value)) return true;
    return value.contains(':');
  }

  Future<String> _resolveIpAddress(String? ipAddress) async {
    final value = ipAddress?.trim() ?? '';
    if (value.isNotEmpty &&
        value != '—' &&
        value != 'Mobile app' &&
        value != 'System') {
      return value;
    }
    return _resolveClientIp();
  }

  Future<String> _resolveClientIpQuick() async {
    try {
      return await _resolveClientIp().timeout(
        const Duration(milliseconds: 2500),
        onTimeout: () => _cachedIp ?? '—',
      );
    } catch (_) {
      return _cachedIp ?? '—';
    }
  }

  Future<void> log({
    required String action,
    required String details,
    String type = 'info',
    String? userName,
    String? userId,
    String source = 'mobile',
    String? ipAddress,
  }) async {
    final actionText = action.trim();
    if (actionText.isEmpty) return;

    try {
      final resolved = await _resolveActor(
        userName: userName,
        userId: userId,
        allowAnonymousSystem: source == 'system',
      );
      if (resolved == null && source != 'system') return;

      final resolvedIp = await _resolveIpAddress(ipAddress);

      await _firestore.collection(_collection).add({
        'timestamp': Timestamp.now(),
        'userName': resolved?.userName ?? 'System',
        'userId': resolved?.userId ?? '—',
        'action': actionText,
        'details': details.trim(),
        'type': type,
        'ipAddress': resolvedIp,
        'source': source,
      });
    } catch (error, stack) {
      debugPrint('ActivityLogService.log failed: $error\n$stack');
    }
  }

  Future<void> logWarning({
    required String action,
    required String details,
    String? userName,
    String? userId,
    String source = 'mobile',
  }) async {
    await log(
      action: action,
      details: details,
      type: 'warning',
      userName: userName,
      userId: userId,
      source: source,
    );
  }

  Future<void> logSecurityAudit({
    required String action,
    required String details,
    String? userName,
    String? userId,
    String source = 'mobile',
  }) async {
    final actionText = action.trim();
    if (actionText.isEmpty) return;

    try {
      final actor = await _resolveActor(userName: userName, userId: userId);
      final resolvedName = actor?.userName ??
          (userName?.trim().isNotEmpty == true ? userName!.trim() : 'Unknown');
      final resolvedId = actor?.userId ??
          (userId?.trim().isNotEmpty == true ? userId!.trim() : '—');
      final resolvedIp = await _resolveClientIpQuick();

      await _firestore.collection(_collection).add({
        'timestamp': Timestamp.now(),
        'userName': resolvedName,
        'userId': resolvedId,
        'action': actionText,
        'details': details.trim(),
        'type': 'security',
        'ipAddress': resolvedIp,
        'source': source,
      });
    } catch (error, stack) {
      final code = (error as dynamic).code?.toString() ?? '';
      if (code == 'permission-denied') {
        debugPrint(
          'ActivityLogService.logSecurityAudit denied. '
          'Deploy Firestore rules: firebase deploy --only firestore:rules\n'
          '$error\n$stack',
        );
      } else {
        debugPrint('ActivityLogService.logSecurityAudit failed: $error\n$stack');
      }
    }
  }

  Future<void> logSystem({
    required String action,
    required String details,
    String type = 'info',
    String? relatedUserId,
    String? relatedUserName,
  }) async {
    final suffix = relatedUserId == null || relatedUserId.isEmpty
        ? ''
        : ' (patient ${relatedUserName ?? relatedUserId} / $relatedUserId)';
    await log(
      action: action,
      details: '$details$suffix',
      type: type,
      userName: 'System',
      userId: '—',
      source: 'system',
      ipAddress: 'System',
    );
  }

  Future<_Actor?> _resolveActor({
    String? userName,
    String? userId,
    bool allowAnonymousSystem = false,
  }) async {
    final user = AuthSession.resolveUser() ?? _auth.currentUser;
    if (user != null) {
      return _resolvePatientFromUsersCollection(user);
    }

    if (userName != null &&
        userName.isNotEmpty &&
        userId != null &&
        userId.isNotEmpty) {
      return _Actor(userName: userName, userId: userId);
    }

    if (userName != null && userName.isNotEmpty) {
      return _Actor(
        userName: userName,
        userId: userId?.trim().isNotEmpty == true ? userId!.trim() : '—',
      );
    }

    return allowAnonymousSystem ? const _Actor(userName: 'System', userId: '—') : null;
  }

  Future<_Actor> _resolvePatientFromUsersCollection(User user) async {
    try {
      final profile =
          await _profileService.loadProfile(user.uid, syncAuthFirst: false);
      final data = profile.data;
      final resolvedName = (data['fullName'] as String?)?.trim() ??
          (data['name'] as String?)?.trim() ??
          user.email?.split('@').first ??
          'Patient';
      var resolvedId = UserProfileService.patientId(data);
      if (resolvedId.isEmpty) {
        resolvedId = user.uid;
      }
      return _Actor(userName: resolvedName, userId: resolvedId);
    } catch (error) {
      debugPrint('ActivityLogService user lookup failed: $error');
      return _Actor(
        userName: user.email?.split('@').first ?? 'Patient',
        userId: user.uid,
      );
    }
  }
}

class _Actor {
  const _Actor({required this.userName, required this.userId});

  final String userName;
  final String userId;
}
