const STORAGE_KEY = "staffLoginLockout";
export const MAX_LOGIN_ATTEMPTS = 3;
const BASE_LOCKOUT_MS = 2 * 60 * 1000;
const MAX_LOCKOUT_MS = 30 * 60 * 1000;

function defaultState() {
  return { failedAttempts: 0, lockoutUntil: 0, lockoutCount: 0 };
}

function loadState() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return defaultState();
    const parsed = JSON.parse(raw);
    return {
      failedAttempts: Number(parsed.failedAttempts) || 0,
      lockoutUntil: Number(parsed.lockoutUntil) || 0,
      lockoutCount: Number(parsed.lockoutCount) || 0,
    };
  } catch {
    return defaultState();
  }
}

function saveState(state) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}

function lockoutDurationMs(lockoutCount) {
  const duration = BASE_LOCKOUT_MS * Math.max(lockoutCount, 1);
  return Math.min(duration, MAX_LOCKOUT_MS);
}

function normalizeExpiredLockout(state) {
  const now = Date.now();
  if (state.lockoutUntil > 0 && state.lockoutUntil <= now) {
    state.failedAttempts = 0;
    state.lockoutUntil = 0;
    saveState(state);
  }
  return state;
}

export function formatLockoutRemaining(remainingMs) {
  const totalSeconds = Math.max(0, Math.ceil(remainingMs / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

export function getLoginLockoutStatus() {
  const state = normalizeExpiredLockout(loadState());
  const now = Date.now();

  if (state.lockoutUntil > now) {
    const remainingMs = state.lockoutUntil - now;
    return {
      locked: true,
      remainingMs,
      remainingLabel: formatLockoutRemaining(remainingMs),
      lockoutCount: state.lockoutCount,
      attemptsRemaining: 0,
    };
  }

  return {
    locked: false,
    remainingMs: 0,
    remainingLabel: "",
    lockoutCount: state.lockoutCount,
    attemptsRemaining: Math.max(0, MAX_LOGIN_ATTEMPTS - state.failedAttempts),
  };
}

export function recordLoginFailure() {
  const state = normalizeExpiredLockout(loadState());
  const now = Date.now();

  if (state.lockoutUntil > now) {
    return {
      locked: true,
      justLocked: false,
      remainingMs: state.lockoutUntil - now,
      remainingLabel: formatLockoutRemaining(state.lockoutUntil - now),
      lockoutCount: state.lockoutCount,
      attemptsRemaining: 0,
    };
  }

  state.failedAttempts += 1;

  if (state.failedAttempts >= MAX_LOGIN_ATTEMPTS) {
    state.lockoutCount += 1;
    const lockoutMs = lockoutDurationMs(state.lockoutCount);
    state.lockoutUntil = now + lockoutMs;
    state.failedAttempts = 0;
    saveState(state);

    return {
      locked: true,
      justLocked: true,
      lockoutMs,
      remainingMs: lockoutMs,
      remainingLabel: formatLockoutRemaining(lockoutMs),
      lockoutCount: state.lockoutCount,
      attemptsRemaining: 0,
    };
  }

  saveState(state);
  return {
    locked: false,
    justLocked: false,
    remainingMs: 0,
    remainingLabel: "",
    lockoutCount: state.lockoutCount,
    attemptsRemaining: MAX_LOGIN_ATTEMPTS - state.failedAttempts,
  };
}

export function clearLoginLockout() {
  localStorage.removeItem(STORAGE_KEY);
}

export function lockoutMessage(status) {
  if (!status.locked) return "";
  return `Too many failed login attempts. Please wait ${status.remainingLabel} before trying again.`;
}

export function attemptsRemainingMessage(attemptsRemaining) {
  if (attemptsRemaining <= 0) return "";
  const noun = attemptsRemaining === 1 ? "attempt" : "attempts";
  return `${attemptsRemaining} ${noun} remaining before a temporary lockout.`;
}
