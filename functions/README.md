# Aura Guide Cloud Functions

This folder contains backend sync logic to keep Authentication and Firestore profile data aligned.

## What this implements

- `onAuthUserCreate`  
  Creates/merges `users/{uid}` with auth metadata when a user account is created.

- `onAuthUserDelete`  
  Marks profile as inactive when auth account is deleted.

- `syncMyAuthProfile` (Callable HTTPS)  
  Lets the app trigger immediate sync for the currently signed-in user.

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

## Notes

- Default project is configured in `.firebaserc` as `auraguide-46d15`.
- Call `syncMyAuthProfile` from app after verification return for near-instant email sync.
