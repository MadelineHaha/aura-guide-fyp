/// Consultation types aligned with the admin web portal booking form.
typedef AppointmentTypeOption = ({
  String key,
  String titleKey,
  String subtitleKey,
  String canonicalType,
});

class AppointmentTypes {
  AppointmentTypes._();

  static const doctorOptions = <AppointmentTypeOption>[
    (
      key: 'general_checkup',
      titleKey: 'sessionGeneralCheckup',
      subtitleKey: 'sessionGeneralCheckupDesc',
      canonicalType: 'General Check-up',
    ),
    (
      key: 'follow_up_consultation',
      titleKey: 'sessionFollowUpConsultation',
      subtitleKey: 'sessionFollowUpConsultationDesc',
      canonicalType: 'Follow-up Consultation',
    ),
    (
      key: 'urgent_consultation',
      titleKey: 'sessionUrgentConsultation',
      subtitleKey: 'sessionUrgentConsultationDesc',
      canonicalType: 'Urgent Consultation',
    ),
    (
      key: 'chronic_disease_review',
      titleKey: 'sessionChronicDiseaseReview',
      subtitleKey: 'sessionChronicDiseaseReviewDesc',
      canonicalType: 'Chronic Disease Review',
    ),
    (
      key: 'medication_review',
      titleKey: 'sessionMedicationReview',
      subtitleKey: 'sessionMedicationReviewDesc',
      canonicalType: 'Medication Review',
    ),
    (
      key: 'pre_operative_assessment',
      titleKey: 'sessionPreOperativeAssessment',
      subtitleKey: 'sessionPreOperativeAssessmentDesc',
      canonicalType: 'Pre-operative Assessment',
    ),
  ];

  static const therapistOptions = <AppointmentTypeOption>[
    (
      key: 'physical_therapy',
      titleKey: 'sessionPhysicalTherapy',
      subtitleKey: 'sessionPhysicalTherapyDesc',
      canonicalType: 'Physical Therapy Session',
    ),
    (
      key: 'occupational_therapy',
      titleKey: 'sessionOccupationalTherapy',
      subtitleKey: 'sessionOccupationalTherapyDesc',
      canonicalType: 'Occupational Therapy Session',
    ),
    (
      key: 'rehabilitation',
      titleKey: 'sessionRehabilitation',
      subtitleKey: 'sessionRehabilitationDesc',
      canonicalType: 'Rehabilitation Session',
    ),
    (
      key: 'pain_management',
      titleKey: 'sessionPainManagement',
      subtitleKey: 'sessionPainManagementDesc',
      canonicalType: 'Pain Management Session',
    ),
    (
      key: 'speech_therapy',
      titleKey: 'sessionSpeechTherapy',
      subtitleKey: 'sessionSpeechTherapyDesc',
      canonicalType: 'Speech Therapy Session',
    ),
    (
      key: 'mental_health_counseling',
      titleKey: 'sessionMentalHealthCounseling',
      subtitleKey: 'sessionMentalHealthCounselingDesc',
      canonicalType: 'Mental Health Counseling',
    ),
  ];

  static const allOptions = [...doctorOptions, ...therapistOptions];

  static List<AppointmentTypeOption> optionsForRole(String? roleKey) {
    switch (roleKey) {
      case 'doctor':
        return doctorOptions;
      case 'therapist':
        return therapistOptions;
      default:
        return allOptions;
    }
  }

  static AppointmentTypeOption? optionForKey(String key) {
    for (final option in allOptions) {
      if (option.key == key) return option;
    }
    return null;
  }

  static bool isTherapistAppointmentType(String? value) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return false;
    for (final option in therapistOptions) {
      if (option.canonicalType == trimmed) return true;
    }
    final lower = trimmed.toLowerCase();
    return lower == 'therapy session' || lower == 'therapist session';
  }
}
