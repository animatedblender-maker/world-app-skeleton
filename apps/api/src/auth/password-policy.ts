/**
 * Matterya strong password policy (signup + password reset).
 * Keep messages user-facing and specific so clients can show them as-is.
 */

export const PASSWORD_MIN_LENGTH = 8;
export const PASSWORD_MAX_LENGTH = 128;

export const PASSWORD_REQUIREMENTS_HINT =
  'Use at least 8 characters with uppercase, lowercase, a number, and a symbol character (!@#$%…).';

const COMMON_PASSWORDS = new Set(
  [
    'password',
    'password1',
    'password12',
    'password123',
    '12345678',
    '123456789',
    '1234567890',
    'qwerty123',
    'qwertyui',
    'letmein1',
    'welcome1',
    'admin123',
    'iloveyou',
    'monkey12',
    'abc12345',
    'passw0rd',
    'matterya',
    'matterya1',
  ].map((s) => s.toLowerCase())
);

export type PasswordValidation =
  | { ok: true }
  | { ok: false; code: 'EMPTY_PASSWORD' | 'WEAK_PASSWORD'; message: string };

/**
 * Validate a new password for signup / reset.
 * Login should only reject empty passwords (existing accounts may predate this policy).
 */
export function validateStrongPassword(password: unknown): PasswordValidation {
  if (password === null || password === undefined) {
    return {
      ok: false,
      code: 'EMPTY_PASSWORD',
      message: 'Password is required. Enter a password to continue.',
    };
  }
  if (typeof password !== 'string') {
    return {
      ok: false,
      code: 'EMPTY_PASSWORD',
      message: 'Password is required. Enter a password to continue.',
    };
  }

  // Reject empty / whitespace-only before other checks.
  if (password.length === 0 || password.trim().length === 0) {
    return {
      ok: false,
      code: 'EMPTY_PASSWORD',
      message: 'Password cannot be empty. Choose a strong password to continue.',
    };
  }

  // Do not trim for length/composition — spaces only count if intentional in middle.
  if (password.length < PASSWORD_MIN_LENGTH) {
    return {
      ok: false,
      code: 'WEAK_PASSWORD',
      message: `Password is too short. Use at least ${PASSWORD_MIN_LENGTH} characters, including uppercase, lowercase, a number, and a symbol character.`,
    };
  }

  if (password.length > PASSWORD_MAX_LENGTH) {
    return {
      ok: false,
      code: 'WEAK_PASSWORD',
      message: `Password is too long. Use at most ${PASSWORD_MAX_LENGTH} characters.`,
    };
  }

  if (/\s/.test(password)) {
    return {
      ok: false,
      code: 'WEAK_PASSWORD',
      message: 'Password cannot contain spaces. Use letters, numbers, and symbols only.',
    };
  }

  if (!/[a-z]/.test(password)) {
    return {
      ok: false,
      code: 'WEAK_PASSWORD',
      message: 'Password must include at least one lowercase letter (a–z).',
    };
  }

  if (!/[A-Z]/.test(password)) {
    return {
      ok: false,
      code: 'WEAK_PASSWORD',
      message: 'Password must include at least one uppercase letter (A–Z).',
    };
  }

  if (!/[0-9]/.test(password)) {
    return {
      ok: false,
      code: 'WEAK_PASSWORD',
      message: 'Password must include at least one number (0–9).',
    };
  }

  // Symbol: anything not letter/digit
  if (!/[^A-Za-z0-9]/.test(password)) {
    return {
      ok: false,
      code: 'WEAK_PASSWORD',
      message: 'Password must include at least one special character (for example ! @ # $ % & *).',
    };
  }

  if (COMMON_PASSWORDS.has(password.toLowerCase())) {
    return {
      ok: false,
      code: 'WEAK_PASSWORD',
      message: 'That password is too common. Choose something unique that only you would use.',
    };
  }

  // Very simple keyboard-run / repeated char rejection
  if (/^(.)\1+$/.test(password)) {
    return {
      ok: false,
      code: 'WEAK_PASSWORD',
      message: 'Password cannot be the same character repeated. Mix letters, numbers, and symbols.',
    };
  }

  return { ok: true };
}

/** Login only: reject missing/empty password with a clear message. */
export function validatePasswordPresent(password: unknown): PasswordValidation {
  if (password === null || password === undefined || typeof password !== 'string') {
    return {
      ok: false,
      code: 'EMPTY_PASSWORD',
      message: 'Password is required. Enter your password to log in.',
    };
  }
  if (password.length === 0 || password.trim().length === 0) {
    return {
      ok: false,
      code: 'EMPTY_PASSWORD',
      message: 'Password cannot be empty. Enter your password to log in.',
    };
  }
  return { ok: true };
}

export function assertStrongPassword(password: unknown): void {
  const result = validateStrongPassword(password);
  if (!result.ok) {
    throw Object.assign(new Error(result.message), {
      code: result.code,
      status: 400,
    });
  }
}
