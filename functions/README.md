# Aura Guide Cloud Functions

This folder contains backend sync logic to keep Authentication and Firestore profile data aligned.

## What this implements

- `onAuthUserCreate`  
  Creates/merges `users/{uid}` with auth metadata when a user account is created.

- `onAuthUserDelete`  
  Marks profile as inactive when auth account is deleted.

- `syncMyAuthProfile` (Callable HTTPS)  
  Lets the app trigger immediate sync for the currently signed-in user.

- `dispatchMedicationReminders` (Pub/Sub schedule, every 1 minute)  
  Sends FCM push notifications to patients when a `medicationreminders` entry is due
  (clinic time UTC+8). Requires the mobile app to save `users/{uid}.fcmToken`.

## One-time setup

1. Install Firebase CLI globally (if not installed):
   - `npm i -g firebase-tools`
2. Login:
   - `firebase login`
3. Install functions dependencies:
   - `cd functions`
   - `npm install`

## Deploy

From repo root:

- `firebase deploy --only functions`

After first deploy, enable the Cloud Scheduler job for `dispatchMedicationReminders`
in Google Cloud Console if it is paused.

## Notes

- Default project is configured in `.firebaserc` as `auraguide-46d15`.
- Call `syncMyAuthProfile` from app after verification return for near-instant email sync.
