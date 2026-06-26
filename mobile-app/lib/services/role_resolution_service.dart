import 'package:cloud_firestore/cloud_firestore.dart';

/// Resolved mobile account from Firestore (`healthcarestaff`, `caregiver`, `users`).
enum MobileAppRole {
  patient,
  doctor,
  therapist,
  caregiver,
  admin,
  unknown,
}

class AccountResolution {
  const AccountResolution._({
    required this.kind,
    this.role,
    this.profile = const {},
    this.sourceCollection,
    this.message,
  });

  const AccountResolution.resolved({
    required MobileAppRole role,
    required Map<String, dynamic> profile,
    required String sourceCollection,
  }) : this._(
          kind: AccountResolutionKind.resolved,
          role: role,
          profile: profile,
          sourceCollection: sourceCollection,
        );

  const AccountResolution.onboardingPending({
    required Map<String, dynamic> profile,
  }) : this._(
          kind: AccountResolutionKind.onboardingPending,
          role: MobileAppRole.patient,
          profile: profile,
          sourceCollection: 'users',
        );

  const AccountResolution.inactive({required String message})
      : this._(
          kind: AccountResolutionKind.inactive,
          message: message,
        );

  const AccountResolution.notFound({required String message})
      : this._(
          kind: AccountResolutionKind.notFound,
          message: message,
        );

  final AccountResolutionKind kind;
  final MobileAppRole? role;
  final Map<String, dynamic> profile;
  final String? sourceCollection;
  final String? message;
}

enum AccountResolutionKind {
  resolved,
  onboardingPending,
  inactive,
  notFound,
}

/// Role-based routing aligned with the staff web portal collections.
class RoleResolutionService {
  RoleResolutionService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static const usersCollection = 'users';
  static const staffCollection = 'healthcarestaff';
  static const caregiverCollection = 'caregiver';

  static bool isActiveStatus(dynamic status) {
    return status?.toString().trim().toLowerCase() == 'active';
  }

  static MobileAppRole normalizeStaffRole(dynamic role) {
    final value = role?.toString().trim().toLowerCase() ?? '';
    switch (value) {
      case 'doctor':
      case 'dr':
      case 'physician':
        return MobileAppRole.doctor;
      case 'therapist':
      case 'therapy':
        return MobileAppRole.therapist;
      case 'caregiver':
      case 'nurse':
        return MobileAppRole.caregiver;
      case 'admin':
      case 'administrator':
        return MobileAppRole.admin;
      default:
        return MobileAppRole.unknown;
    }
  }

  AccountResolution resolveFromSnapshots({
    DocumentSnapshot<Map<String, dynamic>>? staffDoc,
    DocumentSnapshot<Map<String, dynamic>>? caregiverDoc,
    DocumentSnapshot<Map<String, dynamic>>? userDoc,
  }) {
    if (staffDoc?.exists == true) {
      final data = staffDoc!.data() ?? {};
      if (!isActiveStatus(data['status'])) {
        return const AccountResolution.inactive(
          message: 'Your staff account is inactive. Contact your administrator.',
        );
      }
      final role = normalizeStaffRole(data['role']);
      if (role == MobileAppRole.unknown) {
        return const AccountResolution.inactive(
          message: 'Your staff role is not supported on mobile.',
        );
      }
      return AccountResolution.resolved(
        role: role,
        profile: data,
        sourceCollection: staffCollection,
      );
    }

    if (caregiverDoc?.exists == true) {
      final data = caregiverDoc!.data() ?? {};
      if (!isActiveStatus(data['status'])) {
        return const AccountResolution.inactive(
          message: 'Your caregiver account is inactive.',
        );
      }
      return AccountResolution.resolved(
        role: MobileAppRole.caregiver,
        profile: data,
        sourceCollection: caregiverCollection,
      );
    }

    if (userDoc?.exists == true) {
      final data = userDoc!.data() ?? {};
      if (data['onboardingPending'] == true) {
        return AccountResolution.onboardingPending(profile: data);
      }
      return AccountResolution.resolved(
        role: MobileAppRole.patient,
        profile: data,
        sourceCollection: usersCollection,
      );
    }

    return const AccountResolution.notFound(
      message: 'No account profile found. Please contact support.',
    );
  }

  Stream<AccountResolution> watchAccount(String uid) {
    return Stream.multi((controller) {
      DocumentSnapshot<Map<String, dynamic>>? staffDoc;
      DocumentSnapshot<Map<String, dynamic>>? caregiverDoc;
      DocumentSnapshot<Map<String, dynamic>>? userDoc;
      var staffReady = false;
      var caregiverReady = false;
      var userReady = false;

      void emitIfReady() {
        if (!staffReady || !caregiverReady || !userReady) return;
        if (controller.isClosed) return;
        controller.add(
          resolveFromSnapshots(
            staffDoc: staffDoc,
            caregiverDoc: caregiverDoc,
            userDoc: userDoc,
          ),
        );
      }

      final staffSub = _firestore
          .collection(staffCollection)
          .doc(uid)
          .snapshots()
          .listen(
        (snap) {
          staffDoc = snap;
          staffReady = true;
          emitIfReady();
        },
        onError: controller.addError,
      );

      final caregiverSub = _firestore
          .collection(caregiverCollection)
          .doc(uid)
          .snapshots()
          .listen(
        (snap) {
          caregiverDoc = snap;
          caregiverReady = true;
          emitIfReady();
        },
        onError: controller.addError,
      );

      final userSub = _firestore
          .collection(usersCollection)
          .doc(uid)
          .snapshots()
          .listen(
        (snap) {
          userDoc = snap;
          userReady = true;
          emitIfReady();
        },
        onError: controller.addError,
      );

      controller.onCancel = () {
        staffSub.cancel();
        caregiverSub.cancel();
        userSub.cancel();
      };
    });
  }
}
