import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class LoginLockoutStatus {
  const LoginLockoutStatus({
    required this.locked,
    required this.remainingMs,
    required this.lockoutCount,
    required this.attemptsRemaining,
  });

  final bool locked;
  final int remainingMs;
  final int lockoutCount;
  final int attemptsRemaining;

  String get remainingLabel => LoginLockoutService.formatRemaining(remainingMs);
}

class LoginFailureResult {
  const LoginFailureResult({
    required this.locked,
    required this.justLocked,
    required this.remainingMs,
    required this.lockoutCount,
    required this.attemptsRemaining,
  });

  final bool locked;
  final bool justLocked;
  final int remainingMs;
  final int lockoutCount;
  final int attemptsRemaining;

  String get remainingLabel => LoginLockoutService.formatRemaining(remainingMs);
}

class LoginLockoutService {
  LoginLockoutService._();

  static final LoginLockoutService instance = LoginLockoutService._();

  static const maxAttempts = 3;
  static const baseLockoutMs = 2 * 60 * 1000;
  static const maxLockoutMs = 30 * 60 * 1000;
  static const _storageKey = 'patientLoginLockout';

  static String formatRemaining(int remainingMs) {
    final totalSeconds = (remainingMs / 1000).ceil().clamp(0, 9999);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<LoginLockoutStatus> getStatus() async {
    final state = await _normalizeExpired(await _loadState());
    final now = DateTime.now().millisecondsSinceEpoch;

    if (state.lockoutUntil > now) {
      return LoginLockoutStatus(
        locked: true,
        remainingMs: state.lockoutUntil - now,
        lockoutCount: state.lockoutCount,
        attemptsRemaining: 0,
      );
    }

    return LoginLockoutStatus(
      locked: false,
      remainingMs: 0,
      lockoutCount: state.lockoutCount,
      attemptsRemaining: (maxAttempts - state.failedAttempts).clamp(0, maxAttempts),
    );
  }

  Future<LoginFailureResult> recordFailure() async {
    var state = await _normalizeExpired(await _loadState());
    final now = DateTime.now().millisecondsSinceEpoch;

    if (state.lockoutUntil > now) {
      final remainingMs = state.lockoutUntil - now;
      return LoginFailureResult(
        locked: true,
        justLocked: false,
        remainingMs: remainingMs,
        lockoutCount: state.lockoutCount,
        attemptsRemaining: 0,
      );
    }

    state = state.copyWith(failedAttempts: state.failedAttempts + 1);

    if (state.failedAttempts >= maxAttempts) {
      final lockoutCount = state.lockoutCount + 1;
      final lockoutMs = _lockoutDurationMs(lockoutCount);
      state = _LockoutState(
        failedAttempts: 0,
        lockoutUntil: now + lockoutMs,
        lockoutCount: lockoutCount,
      );
      await _saveState(state);
      return LoginFailureResult(
        locked: true,
        justLocked: true,
        remainingMs: lockoutMs,
        lockoutCount: lockoutCount,
        attemptsRemaining: 0,
      );
    }

    await _saveState(state);
    return LoginFailureResult(
      locked: false,
      justLocked: false,
      remainingMs: 0,
      lockoutCount: state.lockoutCount,
      attemptsRemaining: maxAttempts - state.failedAttempts,
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  int _lockoutDurationMs(int lockoutCount) {
    final duration = baseLockoutMs * lockoutCount.clamp(1, 999);
    return duration > maxLockoutMs ? maxLockoutMs : duration;
  }

  Future<_LockoutState> _normalizeExpired(_LockoutState state) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (state.lockoutUntil > 0 && state.lockoutUntil <= now) {
      final cleared = state.copyWith(failedAttempts: 0, lockoutUntil: 0);
      await _saveState(cleared);
      return cleared;
    }
    return state;
  }

  Future<_LockoutState> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return const _LockoutState();

    try {
      final data = jsonDecode(raw);
      if (data is! Map) return const _LockoutState();
      return _LockoutState(
        failedAttempts: (data['failedAttempts'] as num?)?.toInt() ?? 0,
        lockoutUntil: (data['lockoutUntil'] as num?)?.toInt() ?? 0,
        lockoutCount: (data['lockoutCount'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const _LockoutState();
    }
  }

  Future<void> _saveState(_LockoutState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode({
        'failedAttempts': state.failedAttempts,
        'lockoutUntil': state.lockoutUntil,
        'lockoutCount': state.lockoutCount,
      }),
    );
  }
}

class _LockoutState {
  const _LockoutState({
    this.failedAttempts = 0,
    this.lockoutUntil = 0,
    this.lockoutCount = 0,
  });

  final int failedAttempts;
  final int lockoutUntil;
  final int lockoutCount;

  _LockoutState copyWith({
    int? failedAttempts,
    int? lockoutUntil,
    int? lockoutCount,
  }) {
    return _LockoutState(
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockoutUntil: lockoutUntil ?? this.lockoutUntil,
      lockoutCount: lockoutCount ?? this.lockoutCount,
    );
  }
}
