/**
 * Firebase web app config — replace with your project values.
 * Firebase Console → Project settings → Your apps → SDK setup and configuration
 */
export const firebaseConfig = {
  apiKey: "AIzaSyCQlrH2N3KG64xQhMQEkSLy-QPkfVzuU6k",
  authDomain: "auraguide-46d15.firebaseapp.com",
  projectId: "auraguide-46d15",
  storageBucket: "auraguide-46d15.firebasestorage.app",
  messagingSenderId: "1031218970443",
  appId: "1:1031218970443:web:b608f4a5800a34174572ce",
};

/** True once you paste real values from Firebase Console (not YOUR_* placeholders). */
export function isFirebaseConfigured() {
  return (
    firebaseConfig.apiKey &&
    !firebaseConfig.apiKey.startsWith("YOUR_") &&
    firebaseConfig.projectId &&
    !firebaseConfig.projectId.startsWith("YOUR_")
  );
}
