/** Canonical activity log actions used for auditing and report analytics. */
export const LOG_ACTIONS = {
  LOGIN: "Login",
  LOGOUT: "Logout",
  BOOK_APPOINTMENT: "Book Appointment",
  UPDATE_APPOINTMENT: "Update Appointment",
  UPDATE_APPOINTMENT_STATUS: "Update Appointment Status",
  ACCEPT_APPOINTMENT: "Accept Appointment",
  COMPLETE_APPOINTMENT: "Complete Appointment",
  UPDATE_PATIENT: "Update Patient Record",
  CREATE_PATIENT: "Create Patient Account",
  CREATE_STAFF: "Create Staff Account",
  UPDATE_STAFF: "Update Staff Account",
  REGISTER_ACCOUNT: "Register Account",
  SEND_MESSAGE: "Send Message",
  MARK_MEDICATION: "Mark Medication Taken",
  EMERGENCY_ALERT: "Emergency Alert Submitted",
  VOICE_CALL: "Voice Call Made",
  HEALTH_RECORD_VIEWED: "Health Record Viewed",
  FAILED_GPS: "Failed GPS Retrieval",
  CAMERA_DENIED: "Camera Permission Denied",
  VOICE_RECOGNITION_FAILURE: "Voice Recognition Failure",
  NETWORK_TIMEOUT: "Network Timeout",
  FAILED_LOGIN: "Failed Login",
  UNAUTHORIZED_ACCESS: "Unauthorized Access Attempt",
  PASSWORD_CHANGE: "Password Change",
  ACCOUNT_LOCKOUT: "Account Lockout",
  RESPOND_EMERGENCY: "Respond to Emergency",
  ASSIGN_CAREGIVER: "Assign Caregiver",
  RESOLVE_EMERGENCY: "Resolve Emergency Alert",
};

export function computeReportAnalytics(logs) {
  const countAction = (action) =>
    logs.filter((log) => log.action === action).length;

  return {
    userActivity: {
      totalLogins: countAction(LOG_ACTIONS.LOGIN),
      totalAppointmentsBooked: countAction(LOG_ACTIONS.BOOK_APPOINTMENT),
      totalEmergencyAlerts: countAction(LOG_ACTIONS.EMERGENCY_ALERT),
      totalVoiceCalls: countAction(LOG_ACTIONS.VOICE_CALL),
      totalHealthRecordsViewed: countAction(LOG_ACTIONS.HEALTH_RECORD_VIEWED),
    },
    warning: {
      failedGps: countAction(LOG_ACTIONS.FAILED_GPS),
      cameraDenied: countAction(LOG_ACTIONS.CAMERA_DENIED),
      voiceRecognitionFailure: countAction(LOG_ACTIONS.VOICE_RECOGNITION_FAILURE),
      networkTimeout: countAction(LOG_ACTIONS.NETWORK_TIMEOUT),
    },
    security: {
      failedLogin: countAction(LOG_ACTIONS.FAILED_LOGIN),
      unauthorizedAccess: countAction(LOG_ACTIONS.UNAUTHORIZED_ACCESS),
      passwordChanges: countAction(LOG_ACTIONS.PASSWORD_CHANGE),
      accountLockouts: countAction(LOG_ACTIONS.ACCOUNT_LOCKOUT),
    },
  };
}
