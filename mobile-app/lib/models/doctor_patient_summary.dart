class DoctorPatientSummary {
  const DoctorPatientSummary({
    required this.authUid,
    required this.patientId,
    required this.name,
    required this.email,
    required this.accountStatus,
    this.assignedCaregiverUid = '',
    this.assignedCaregiverPublicId = '',
    this.assignedCaregiverName = '',
  });

  final String authUid;
  final String patientId;
  final String name;
  final String email;
  final String accountStatus;
  final String assignedCaregiverUid;
  final String assignedCaregiverPublicId;
  final String assignedCaregiverName;

  bool get isActive =>
      accountStatus.trim().toLowerCase() != 'inactive';

  bool get hasAssignedCaregiver =>
      assignedCaregiverPublicId.isNotEmpty || assignedCaregiverUid.isNotEmpty;
}
