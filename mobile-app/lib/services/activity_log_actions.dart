/// Canonical activity log actions used for auditing and report analytics.
class ActivityLogActions {
  ActivityLogActions._();

  static const login = 'Login';
  static const logout = 'Logout';
  static const bookAppointment = 'Book Appointment';
  static const updateAppointment = 'Update Appointment';
  static const updateAppointmentStatus = 'Update Appointment Status';
  static const acceptAppointment = 'Accept Appointment';
  static const completeAppointment = 'Complete Appointment';
  static const updatePatient = 'Update Patient Record';
  static const registerAccount = 'Register Account';
  static const sendMessage = 'Send Message';
  static const markMedication = 'Mark Medication Taken';
  static const emergencyAlert = 'Emergency Alert Submitted';
  static const voiceCall = 'Voice Call Made';
  static const healthRecordViewed = 'Health Record Viewed';
  static const failedGps = 'Failed GPS Retrieval';
  static const cameraDenied = 'Camera Permission Denied';
  static const voiceRecognitionFailure = 'Voice Recognition Failure';
  static const networkTimeout = 'Network Timeout';
  static const failedLogin = 'Failed Login';
  static const unauthorizedAccess = 'Unauthorized Access Attempt';
  static const passwordChange = 'Password Change';
  static const accountLockout = 'Account Lockout';
  static const respondEmergency = 'Respond to Emergency';
  static const assignCaregiver = 'Assign Caregiver';
  static const resolveEmergency = 'Resolve Emergency Alert';
}
