import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/staff_option.dart';

/// Reads `healthcarestaff` matching Firestore schema:
/// `staffID`, `name`, `role` (Doctor | Therapist | Caregiver), `status` (Active), `email`, …
class HealthcareStaffService {
  HealthcareStaffService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const collection = 'healthcarestaff';

  static const roleDoctor = 'doctor';
  static const roleTherapist = 'therapist';
  static const roleCaregiver = 'caregiver';

  static const roleLabels = {
    roleDoctor: 'Doctor',
    roleTherapist: 'Therapist',
    roleCaregiver: 'Caregiver',
  };

  /// UI role key → Firestore `role` field value (matches your console).
  static String firestoreRoleForKey(String roleKey) {
    switch (roleKey) {
      case roleDoctor:
        return 'Doctor';
      case roleTherapist:
        return 'Therapist';
      case roleCaregiver:
        return 'Caregiver';
      default:
        return roleKey;
    }
  }

  static bool _isActiveStatus(dynamic status) {
    return status?.toString().trim().toLowerCase() == 'active';
  }

  static String? _readStaffId(Map<String, dynamic> data) {
    for (final key in ['staffID', 'staffId', 'staff_id']) {
      final v = data[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Maps Firestore `role` text to doctor | therapist | caregiver.
  static String? categoryFromString(String? value) {
    if (value == null) return null;
    final r = value.trim().toLowerCase();
    if (r.isEmpty) return null;

    if (r == 'doctor' || r == 'dr' || r == 'physician') {
      return roleDoctor;
    }
    if (r == 'therapist' || r == 'therapy') {
      return roleTherapist;
    }
    if (r == 'caregiver' || r == 'nurse') {
      return roleCaregiver;
    }
    return null;
  }

  static String? categoryFromData(Map<String, dynamic> data) {
    final role = data['role']?.toString();
    return categoryFromString(role);
  }

  static const _specialtyFields = [
    'specialty',
    'department',
    'specialisation',
    'specialization',
  ];

  static String specialtyFromData(Map<String, dynamic> data) {
    for (final field in _specialtyFields) {
      final v = data[field]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return 'General Practice';
  }

  static String roleLabelForCategory(String category) =>
      roleLabels[category] ?? category;

  StaffOption? _staffOptionFromData(Map<String, dynamic> data) {
    if (!_isActiveStatus(data['status'])) return null;

    final staffId = _readStaffId(data);
    if (staffId == null) return null;

    final category = categoryFromData(data);
    if (category == null) return null;

    final name = data['name']?.toString().trim() ?? staffId;
    final rating = (data['rating'] is num)
        ? (data['rating'] as num).toDouble()
        : 4.8;
    final location = data['location']?.toString().trim() ??
        'Clinic — main building';

    return StaffOption(
      staffId: staffId,
      name: name,
      specialty: specialtyFromData(data),
      category: category,
      roleLabel: roleLabelForCategory(category),
      rating: rating,
      location: location,
    );
  }

  /// Query Active staff only (required for Firestore list + security rules).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _queryActiveStaff({
    String? firestoreRole,
  }) async {
    Query<Map<String, dynamic>> query =
        _firestore.collection(collection).where('status', isEqualTo: 'Active');

    if (firestoreRole != null) {
      query = query.where('role', isEqualTo: firestoreRole);
    }

    final snap = await query.get();
    return snap.docs;
  }

  /// Loads staff for [roleKey] (doctor / therapist / caregiver) from Firestore.
  Future<List<StaffOption>> fetchByRole(String roleKey) async {
    final firestoreRole = firestoreRoleForKey(roleKey);
    final list = <StaffOption>[];

    try {
      var docs = await _queryActiveStaff(firestoreRole: firestoreRole);
      for (final doc in docs) {
        final option = _staffOptionFromData(doc.data());
        if (option != null && option.category == roleKey) {
          list.add(option);
        }
      }

      // Fallback: role casing mismatch in DB — load all Active and filter.
      if (list.isEmpty) {
        docs = await _queryActiveStaff();
        for (final doc in docs) {
          final data = doc.data();
          final role = data['role']?.toString().trim().toLowerCase() ?? '';
          if (role != firestoreRole.toLowerCase()) continue;
          final option = _staffOptionFromData(data);
          if (option != null && option.category == roleKey) {
            list.add(option);
          }
        }
      }
    } on FirebaseException catch (e) {
      if (kDebugMode) {
        debugPrint('healthcarestaff query error: ${e.code} ${e.message}');
      }
      if (e.code == 'failed-precondition') {
        final docs = await _queryActiveStaff();
        for (final doc in docs) {
          final option = _staffOptionFromData(doc.data());
          if (option != null && option.category == roleKey) {
            list.add(option);
          }
        }
      } else {
        rethrow;
      }
    }

    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  Future<Map<String, List<StaffOption>>> fetchGroupedByRole() async {
    final grouped = <String, List<StaffOption>>{
      roleDoctor: [],
      roleTherapist: [],
      roleCaregiver: [],
    };

    final docs = await _queryActiveStaff();
    for (final doc in docs) {
      final option = _staffOptionFromData(doc.data());
      if (option == null) continue;
      grouped[option.category]!.add(option);
    }

    for (final list in grouped.values) {
      list.sort((a, b) => a.name.compareTo(b.name));
    }
    return grouped;
  }
}
