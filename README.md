# Aura Guide

**Voice-first assistive healthcare platform for visually impaired and elderly users.**

Final Year Project — a full-stack system that helps patients move safely, manage daily care, and reach healthcare staff, while giving clinics a web portal to manage patients, staff, and emergencies.

![Flutter](https://img.shields.io/badge/Flutter-02569B?logo=flutter&logoColor=white)
![Firebase](https://img.shields.io/badge/Firebase-FFCA28?logo=firebase&logoColor=black)
![Python](https://img.shields.io/badge/Python-3776AB?logo=python&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-20-339933?logo=node.js&logoColor=white)

---

## Overview

Aura Guide combines a **Flutter mobile app**, **Firebase backend**, **staff admin web portal**, and **on-device AI** to support independent living with accessibility at the center.

| Platform   | Users                                      |
| ---------- | ------------------------------------------ |
| Mobile app | Patients, doctors, therapists, caregivers  |
| Admin web  | Clinic administrators and healthcare staff |

**Languages supported:** English · Bahasa Melayu · 中文

---

## Key Features

### Patient (Mobile)

- **Voice assistant** — hands-free navigation with speech-to-text (STT) and text-to-speech (TTS)
- **Voice-only mode** — control the app without touch
- **Obstacle detection** — camera + YOLO model with spoken warnings
- **Fall detection** — accelerometer-based detection with voice check-in
- **Emergency SOS** — instant alerts to healthcare staff
- **Navigation** — GPS, compass, and map-based walking guidance
- **Medications** — reminders, adherence tracking, push notifications
- **Appointments & health records**
- **Chat & voice/video calls** (WebRTC)
- **Voice login** — passphrase-based authentication

### Healthcare Staff (Mobile + Web)

- Patient management and medical records
- Medication and appointment scheduling
- Therapy sessions and rehabilitation plans
- Emergency alert monitoring
- In-app communication with patients and caregivers
- Medication adherence dashboards and reports
- Role-based access (admin, doctor, therapist, caregiver)

---

## Tech Stack

| Layer              | Technologies                                                       |
| ------------------ | ------------------------------------------------------------------ |
| Mobile             | Flutter, Dart                                                      |
| Backend            | Firebase Auth, Cloud Firestore, Cloud Functions, FCM              |
| Admin web          | HTML, CSS, JavaScript, Firebase Web SDK                            |
| Cloud functions    | Node.js 20                                                         |
| AI / ML            | Python, FastAPI, scikit-learn, TensorFlow, Ultralytics YOLO11      |
| On-device inference| TensorFlow Lite (`tflite_flutter`)                                 |
| Voice              | `speech_to_text`, `flutter_tts`                                    |
| Real-time calls    | WebRTC (`flutter_webrtc`)                                          |
| Sensors            | Camera, GPS, compass, accelerometer                                |

---

## Project Structure

```
aura-guide-fyp/
├── mobile-app/       # Flutter app (patient + staff mobile roles)
├── admin-web/        # Staff/admin web dashboard
├── functions/        # Firebase Cloud Functions (Node.js)
├── ai-model/         # ML training, export scripts, and API
├── firebase.json     # Firebase project configuration
├── firestore.rules   # Firestore security rules
└── storage.rules     # Cloud Storage security rules
```

---

## Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Flutter App    │────▶│  Firebase        │◀────│  Admin Web      │
│  (Patient/Staff)│     │  Auth · Firestore│     │  Portal         │
└────────┬────────┘     │  Functions · FCM │     └─────────────────┘
         │                └──────────────────┘
         │  On-device
         ▼
┌─────────────────┐     ┌──────────────────┐
│  TFLite Models  │     │  AI Model (Python)│
│  YOLO · Emergency│     │  Training · FastAPI│
└─────────────────┘     └──────────────────┘
```

---

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart 3.8+)
- [Node.js 20](https://nodejs.org/) (for Cloud Functions)
- [Firebase CLI](https://firebase.google.com/docs/cli)
- A Firebase project (Auth, Firestore, Functions, FCM enabled)
- Android Studio / Xcode (for mobile builds)
- Python 3.10+ (optional — for AI model training and API)

---

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/aura-guide-fyp.git
cd aura-guide-fyp
```

### 2. Firebase setup

1. Create a project in [Firebase Console](https://console.firebase.google.com/)
2. Enable **Authentication**, **Firestore**, **Cloud Functions**, **Cloud Messaging**, and **Storage**
3. Link your local project:

```bash
firebase login
firebase use --add
```

4. Configure the mobile app:

```bash
cd mobile-app
dart pub global activate flutterfire_cli
flutterfire configure
```

5. Update admin web config in `admin-web/js/firebase-config.js`

### 3. Mobile app

```bash
cd mobile-app
flutter pub get
flutter run
```

> Camera, microphone, location, and motion permissions are required for navigation, obstacle detection, fall detection, and voice features.

### 4. Admin web portal

```bash
cd admin-web
npm install
npm start
```

Open `http://localhost:5500` and sign in with a staff account.

### 5. Cloud Functions

```bash
cd functions
npm install
cd ..
firebase deploy --only functions,firestore:rules,storage
```

See [`functions/README.md`](functions/README.md) for scheduled jobs (medication reminders, appointment sync).

### 6. AI models (optional)

```bash
cd ai-model
python -m venv venv

# Windows
venv\Scripts\activate

# macOS / Linux
source venv/bin/activate

pip install ultralytics scikit-learn tensorflow fastapi uvicorn joblib pandas

# Train YOLO obstacle model
python train.py

# Train emergency text classifier
python scripts/train_emergency_model.py

# Export to TFLite for mobile
python export_tflite.py
```

Place exported `.tflite` models under `mobile-app/assets/ai/`.

To run the optional emergency classification API:

```bash
cd ai-model
uvicorn api:app --reload
```

---

## User Roles

| Role          | Access                                                         |
| ------------- | -------------------------------------------------------------- |
| **Patient**   | Voice assistant, navigation, SOS, medications, appointments    |
| **Doctor**    | Patient list, adherence alerts, chat, emergencies              |
| **Therapist** | Therapy sessions, rehab plans, patient reports                 |
| **Caregiver** | Linked patients, notifications, emergency alerts               |
| **Admin**     | Full clinic management via web dashboard                       |

---

## Cloud Functions

| Function                         | Description                                              |
| -------------------------------- | -------------------------------------------------------- |
| `dispatchMedicationReminders`    | Scheduled FCM push when medication is due                |
| `createDailyMedicationReminders` | Creates daily dose rows at midnight (clinic time)        |
| `syncDailyMedicationReminders`   | Callable sync for on-demand reminder rows                |
| `ensureMedicationSlotReminders`  | Ensures slot-template reminder rows exist                |
| `markMissedAppointments`         | Marks overdue appointments as missed                     |
| `invitePatient` / `inviteHealthcareStaff` / `inviteCaregiver` | Admin invite flows |
| `verifyPatientOnboardingPin`     | Patient onboarding with User ID + PIN                      |
| `broadcastAnnouncement`          | Clinic-wide announcements                                |

Clinic timezone defaults to **Asia/Kuala_Lumpur (UTC+8)**.

---

## Screenshots

<!-- Add screenshots or a demo video here -->

| Main Menu | Obstacle Detection | Admin Dashboard |
| --------- | ------------------ | --------------- |
| _add screenshot_ | _add screenshot_ | _add screenshot_ |

---

## Development Notes

- Medication reminders use **FCM** — patients must register an FCM token on sign-in
- On-device models live in `mobile-app/assets/ai/` (YOLO obstacle + emergency text)
- Large training artifacts (`.pt`, run folders, virtualenvs) should stay out of version control
- Do not commit private keys or production credentials

---

## License

This project was developed as a Final Year Project. All rights reserved unless a license is added separately.
