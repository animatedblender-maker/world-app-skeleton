/** Matterya strong password policy — keep in sync with apps/api/src/auth/password-policy.ts */

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

export function validateStrongPassword(password: unknown): PasswordValidation {
  if (password === null || password === undefined || typeof password !== 'string') {
    return {
      ok: false,
      code: 'EMPTY_PASSWORD',
      message: 'Password is required. Enter a password to continue.',
    };
  }
  if (password.length === 0 || password.trim().length === 0) {
    return {
      ok: false,
      code: 'EMPTY_PASSWORD',
      message: 'Password cannot be empty. Choose a strong password to continue.',
    };
  }
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
  if (/^(.)\1+$/.test(password)) {
    return {
      ok: false,
      code: 'WEAK_PASSWORD',
      message: 'Password cannot be the same character repeated. Mix letters, numbers, and symbols.',
    };
  }
  return { ok: true };
}

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

export function isStrongPassword(password: string): boolean {
  return validateStrongPassword(password).ok;
}
