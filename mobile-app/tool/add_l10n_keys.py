#!/usr/bin/env python3
"""Add missing l10n keys to the compressed catalog and regenerate Dart maps."""
from __future__ import annotations

import base64
import json
import pathlib
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
GEN = ROOT / "tool" / "generate_l10n.py"

NEW_KEYS = {
    "editProfile": "Edit Profile",
    "playAudio": "Play Audio",
    "stopAudio": "Stop Audio",
    "todayProgress": "Today's Progress",
    "medicationTaken": "Taken",
    "medicationNotTaken": "Not taken",
    "medicationItemA11y": "{name}. {time}. {dosage}. {status}",
    "todayProgressA11y": "Today's Progress. {takenCount} of {total} taken. {percent} percent.",
    "ok": "OK",
    "searchResults": "Search results",
    "yourLocation": "Your location",
    "here": "Here",
    "locationUnavailable": "Location unavailable. Enable location permission to see your current address.",
    "locationUnavailableGps": "Location unavailable. Enable GPS or search for an address below.",
    "noPlacesFoundForQuery": 'No places found for "{query}". Try a full address or place name.',
    "noPlacesFoundShort": 'No places found for "{query}".',
    "couldNotSearchPlaces": "Could not search places. Check your connection.",
    "noRecentDestinations": "No recent destinations yet. Your navigation history will appear here.",
    "homeAddressSaved": "Home address saved.",
    "workAddressSaved": "Work address saved.",
    "setHomeAddress": "Set home address",
    "setWorkAddress": "Set work address",
    "searchForPlace": "Search for a place",
    "couldNotSaveAddress": "Could not save address: {error}",
    "couldNotLoadWalkingRoute": "Could not load walking route. Using straight-line guidance.",
    "navigationListeningA11y": "Listening. Speak your destination.",
    "stopListening": "Stop listening",
    "voiceSearch": "Voice search",
    "placeSearchResultA11y": "{label}. {address}.{distancePart} Double tap to navigate.",
    "yourLocationSelectA11y": "Your location. {address}. Double tap to select.",
    "homeSetNowA11y": "Home. Set now. Double tap to choose your home address.",
    "workSetNowA11y": "Work. Set now. Double tap to choose your work address.",
    "homeNavigateA11y": "Home. {address}. Double tap to navigate. Long press to change.",
    "workNavigateA11y": "Work. {address}. Double tap to navigate. Long press to change.",
    "couldNotLoadStaff": "Could not load staff: {error}",
    "couldNotLoadAvailableTimes": "Could not load available times: {error}",
    "couldNotBook": "Could not book: {error}",
    "noTimesForDateDetail": "No times available for this date. Taken slots are hidden. Add Available rows in appointments, or use default hours if none exist yet.",
    "firestorePermissionStaff": "Permission denied reading healthcarestaff. Deploy Firestore rules: firebase deploy --only firestore:rules",
    "firestoreIndexAppointments": "Firestore index missing for appointments (staffId + dateTime). Run: firebase deploy --only firestore:indexes",
    "firestorePermissionAppointments": "Firestore blocked reading appointments for slot lookup. Run: firebase deploy --only firestore:rules",
    "firestorePermissionBooking": "Booking was blocked by Firestore rules. Deploy rules: firebase deploy --only firestore:rules",
    "passwordMustMinLength": "Password must be at least 8 characters.",
    "passwordMustMaxLength": "Password must be at most 255 characters.",
    "passwordMustUppercase": "Password must include at least one uppercase letter.",
    "passwordMustLowercase": "Password must include at least one lowercase letter.",
    "passwordMustDigit": "Password must include at least one number.",
    "passwordMustSpecial": "Password must include at least one special character.",
    "pleaseRepeatPassword": "Please repeat your password.",
    "passwordsDoNotMatch": "Passwords do not match.",
    "passwordReqMinLength": "At least 8 characters",
    "passwordReqUpperLower": "One uppercase and one lowercase letter",
    "passwordReqDigit": "At least one number",
    "passwordReqSpecial": "At least one special character",
    "verifyEmailBeforeSave": "Verify your new email before saving your profile. Open the verification link in your email, then tap Save Profile again.",
    "verifyEmailBeforeSaveWithTarget": "Verify {email} before saving your profile. Open the verification link in your email, then tap Save Profile again.",
    "verificationLinkSentThenSave": "Verification link sent to {email}. Verify that email, then tap Save Profile again to save your profile.",
    "emailNotVerifiedEditingBanner": "Email not verified yet. Open the verification link, then tap Save Profile. Your profile will not be saved until then.",
    "editingModeOnBanner": "Editing mode is ON. Update fields then tap Save Profile.",
    "emailCannotBeEmpty": "Email cannot be empty.",
    "emailChangeNotAllowed": "This account cannot change email because no current email is linked.",
    "emailAlreadyUsed": "This email is already used by another account.",
    "passwordRequiredForEmail": "Password is required to change email.",
    "passwordRequiredDialog": "Password is required",
    "failedToUpdateEmail": "Failed to update email.",
    "couldNotSyncProfile": "Could not sync profile: {error}",
    "firestoreReadFailed": "Firestore read failed: {error}\nCheck Firestore rules allow read on users/{uid}",
    "sessionRefreshingRetry": "Session is refreshing. Tap Retry in a moment — you are not logged out.",
    "couldNotPlayAudio": "Could not play audio. Stop the app and run flutter run again.",
    "authWrongPasswordEmail": "Incorrect password. Email verification was not sent.",
    "authInvalidEmail": "The new email address format is invalid.",
    "authEmailAlreadyInUse": "This email is already linked to another Firebase account.",
    "authRequiresRecentLogin": "Please sign out, sign in again, then retry changing email.",
    "authTooManyRequests": "Too many attempts. Wait a few minutes, then try again.",
    "authCouldNotSendVerification": "Could not send verification email ({code}).",
    "noDocumentAtUsers": "No document at users/{uid}",
    "patientIdDisplay": "Patient ID: {id}",
    "patientIdDash": "Patient ID: -",
    "microphonePermissionRequiredSettings": "Microphone permission is required. Please allow microphone access in your device settings.",
    "voiceSearchNotAvailableWithError": "Voice search is not available: {error}",
    "speechRecognitionUnavailable": "Speech recognition is not available on this device.",
    "listeningEllipsis": "Listening…",
}


def _load_payload() -> str:
    text = GEN.read_text(encoding="utf-8")
    start = text.index("_PAYLOAD = '") + len("_PAYLOAD = '")
    end = text.index("'", start)
    return text[start:end]


def main() -> None:
    import importlib.util

    spec = importlib.util.spec_from_file_location("gen", GEN)
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)

    catalog = gen._catalog()
    added = 0
    for lang in ("en", "ms", "zh"):
        for key, value in NEW_KEYS.items():
            if key not in catalog[lang]:
                catalog[lang][key] = value
                if lang == "en":
                    added += 1

    payload = base64.b64encode(
        zlib.compress(json.dumps(catalog, ensure_ascii=False).encode("utf-8"))
    ).decode("ascii")

    text = GEN.read_text(encoding="utf-8")
    old_payload = _load_payload()
    GEN.write_text(text.replace(f"_PAYLOAD = '{old_payload}'", f"_PAYLOAD = '{payload}'"), encoding="utf-8")

    gen.main()
    print(f"Added {added} new English keys; regenerated l10n maps.")


if __name__ == "__main__":
    main()
