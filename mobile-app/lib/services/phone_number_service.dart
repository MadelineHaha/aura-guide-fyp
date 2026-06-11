import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mobile_number/mobile_number.dart';

class PhoneNumberService {
  PhoneNumberService._();

  static final PhoneNumberService instance = PhoneNumberService._();

  Future<String?> detectSimPhoneNumber() async {
    if (kIsWeb) return null;

    try {
      if (!await _ensurePermission()) return null;
      final number = await MobileNumber.mobileNumber;
      final trimmed = number?.trim() ?? '';
      return trimmed.isEmpty ? null : trimmed;
    } catch (e) {
      debugPrint('PhoneNumberService detect failed: $e');
      return null;
    }
  }

  Future<bool> _ensurePermission() async {
    if (await MobileNumber.hasPhonePermission) return true;
    await MobileNumber.requestPhonePermission;
    return MobileNumber.hasPhonePermission;
  }

  static String normalize(String? raw) {
    if (raw == null) return '';
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length >= 8) {
      return digits.substring(digits.length - min(10, digits.length));
    }
    return digits;
  }

  static bool numbersMatch(String? a, String? b) {
    final left = normalize(a);
    final right = normalize(b);
    if (left.isEmpty || right.isEmpty) return false;
    return left == right || left.endsWith(right) || right.endsWith(left);
  }
}
