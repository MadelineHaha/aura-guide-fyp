/**
 * Registers Firestore listener cleanup when the staff page is hidden or unloaded.
 * Listeners push updates only when Firestore data changes (no polling).
 */

const listeners = new Set();

function runCleanup() {
  for (const unsub of listeners) {
    try {
      unsub();
    } catch {
      /* ignore */
    }
  }
  listeners.clear();
}

let lifecycleBound = false;

function bindLifecycle() {
  if (lifecycleBound) return;
  lifecycleBound = true;
  window.addEventListener("pagehide", runCleanup);
  window.addEventListener("beforeunload", runCleanup);
}

/** Track an unsubscribe function; returns the same function for chaining. */
export function trackFirestoreListener(unsubscribe) {
  if (typeof unsubscribe !== "function") return unsubscribe;
  bindLifecycle();
  listeners.add(unsubscribe);
  return unsubscribe;
}

/** Stop a single listener and remove it from the registry. */
export function releaseFirestoreListener(unsubscribe) {
  if (typeof unsubscribe !== "function") return;
  listeners.delete(unsubscribe);
  try {
    unsubscribe();
  } catch {
    /* ignore */
  }
}
