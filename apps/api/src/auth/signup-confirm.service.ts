import crypto from 'node:crypto';
import { pool } from '../db.js';
import {
  createAuthUser,
  setAuthUserEmailConfirmed,
  supabaseAdminConfigured,
} from '../supabase-admin.js';
import {
  buildConfirmEmailHtml,
  buildConfirmEmailText,
  mailConfigured,
  publicWebOrigin,
  sendMail,
} from '../mail/mail.service.js';
import { assertStrongPassword, PASSWORD_REQUIREMENTS_HINT } from './password-policy.js';

const TOKEN_BYTES = 32;
const EXPIRES_HOURS = Number(process.env.EMAIL_CONFIRM_EXPIRES_HOURS ?? 48);
const resendCooldownMs = 60_000;
const lastResendByEmail = new Map<string, number>();

export type SignupResult = {
  ok: true;
  needsEmailConfirm: true;
  isExistingEmail: false;
  email: string;
  /** Only present when mail is not configured (dev) — never rely on this in production UI. */
  devConfirmUrl?: string;
};

export type ConfirmResult = {
  ok: true;
  email: string;
  alreadyConfirmed?: boolean;
};

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

type AuthUserRow = {
  id: string;
  email?: string | null;
  email_confirmed_at?: string | null;
};

/** Prefer direct auth.users lookup (reliable with DATABASE_URL). */
async function findAuthUserByEmail(email: string): Promise<AuthUserRow | null> {
  try {
    const { rows } = await pool.query(
      `
      select id::text as id, email, email_confirmed_at
      from auth.users
      where lower(email) = lower($1)
      limit 1
      `,
      [email]
    );
    return (rows[0] as AuthUserRow | undefined) ?? null;
  } catch (err) {
    console.warn('[auth] auth.users lookup failed:', (err as Error)?.message ?? err);
    return null;
  }
}

function validateEmail(email: string): void {
  if (!email || email.trim().length === 0) {
    throw Object.assign(new Error('Email is required. Enter your email address.'), {
      code: 'INVALID_EMAIL',
      status: 400,
    });
  }
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) {
    throw Object.assign(new Error('Enter a valid email address.'), {
      code: 'INVALID_EMAIL',
      status: 400,
    });
  }
}

function newToken(): string {
  return crypto.randomBytes(TOKEN_BYTES).toString('hex');
}

function confirmUrlForToken(token: string): string {
  const base = publicWebOrigin();
  return `${base}/confirm-email?token=${encodeURIComponent(token)}`;
}

async function issueConfirmation(userId: string, email: string): Promise<{
  token: string;
  confirmUrl: string;
  mailSkipped: boolean;
}> {
  const token = newToken();
  const expiresAt = new Date(Date.now() + EXPIRES_HOURS * 3600_000);

  await pool.query(
    `
    insert into public.email_confirmations (user_id, email, token, expires_at)
    values ($1, $2, $3, $4)
    `,
    [userId, email, token, expiresAt.toISOString()]
  );

  const confirmUrl = confirmUrlForToken(token);
  const send = await sendMail({
    to: email,
    subject: 'Confirm your Matterya account',
    html: buildConfirmEmailHtml({ email, confirmUrl, expiresHours: EXPIRES_HOURS }),
    text: buildConfirmEmailText({ email, confirmUrl, expiresHours: EXPIRES_HOURS }),
  });

  if (send.skipped) {
    console.info('[auth] confirmation link (mail skipped):', confirmUrl);
  }

  return { token, confirmUrl, mailSkipped: !!send.skipped };
}

export async function signupWithMatteryaEmail(
  rawEmail: string,
  password: unknown
): Promise<SignupResult> {
  if (!supabaseAdminConfigured()) {
    throw Object.assign(new Error('Signup is temporarily unavailable (admin not configured).'), {
      code: 'ADMIN_NOT_CONFIGURED',
      status: 503,
    });
  }

  const email = normalizeEmail(rawEmail);
  validateEmail(email);
  // Strong policy — rejects empty, short, and low-complexity passwords with specific messages.
  assertStrongPassword(password);

  const existing = await findAuthUserByEmail(email);
  if (existing) {
    // Already confirmed → treat as existing account (don’t leak more).
    if (existing.email_confirmed_at) {
      throw Object.assign(new Error('This email is already registered.'), {
        code: 'EMAIL_EXISTS',
        status: 409,
        isExistingEmail: true,
      });
    }
    // Unconfirmed: rotate token + resend (same as resend).
    await issueConfirmation(existing.id, email);
    return {
      ok: true,
      needsEmailConfirm: true,
      isExistingEmail: false,
      email,
    };
  }

  // assertStrongPassword already ensured password is a non-empty strong string.
  const strongPassword = String(password);

  let created;
  try {
    created = await createAuthUser({ email, password: strongPassword, emailConfirm: false });
  } catch (err: any) {
    const msg = String(err?.message ?? err);
    if (/already|exists|registered|duplicate/i.test(msg)) {
      throw Object.assign(new Error('This email is already registered.'), {
        code: 'EMAIL_EXISTS',
        status: 409,
        isExistingEmail: true,
      });
    }
    throw err;
  }

  const issued = await issueConfirmation(created.id, email);
  return {
    ok: true,
    needsEmailConfirm: true,
    isExistingEmail: false,
    email,
    ...(issued.mailSkipped && process.env.NODE_ENV !== 'production'
      ? { devConfirmUrl: issued.confirmUrl }
      : {}),
  };
}

export async function confirmEmailWithToken(token: string): Promise<ConfirmResult> {
  const clean = (token ?? '').trim();
  if (!clean || clean.length < 16) {
    throw Object.assign(new Error('Invalid or missing confirmation link.'), {
      code: 'INVALID_TOKEN',
      status: 400,
    });
  }

  const { rows } = await pool.query(
    `
    select id, user_id, email, expires_at, confirmed_at
    from public.email_confirmations
    where token = $1
    limit 1
    `,
    [clean]
  );
  const row = rows[0] as
    | {
        id: string;
        user_id: string;
        email: string;
        expires_at: string;
        confirmed_at: string | null;
      }
    | undefined;

  if (!row) {
    throw Object.assign(new Error('This confirmation link is invalid.'), {
      code: 'TOKEN_NOT_FOUND',
      status: 404,
    });
  }

  if (row.confirmed_at) {
    return { ok: true, email: row.email, alreadyConfirmed: true };
  }

  if (new Date(row.expires_at).getTime() < Date.now()) {
    throw Object.assign(new Error('This confirmation link has expired. Request a new one from Sign Up.'), {
      code: 'TOKEN_EXPIRED',
      status: 410,
    });
  }

  if (!supabaseAdminConfigured()) {
    throw Object.assign(new Error('Confirmation is temporarily unavailable.'), {
      code: 'ADMIN_NOT_CONFIGURED',
      status: 503,
    });
  }

  await setAuthUserEmailConfirmed(row.user_id, true);

  await pool.query(
    `update public.email_confirmations set confirmed_at = now() where id = $1`,
    [row.id]
  );

  return { ok: true, email: row.email };
}

export async function resendConfirmation(rawEmail: string): Promise<{ ok: true; email: string }> {
  if (!supabaseAdminConfigured()) {
    throw Object.assign(new Error('Resend is temporarily unavailable.'), {
      code: 'ADMIN_NOT_CONFIGURED',
      status: 503,
    });
  }

  const email = normalizeEmail(rawEmail);
  validateEmail(email);

  const now = Date.now();
  const last = lastResendByEmail.get(email) ?? 0;
  if (now - last < resendCooldownMs) {
    throw Object.assign(new Error('Please wait a minute before requesting another email.'), {
      code: 'RATE_LIMITED',
      status: 429,
    });
  }

  const user = await findAuthUserByEmail(email);
  // Always return ok-ish messaging to avoid email enumeration on resend for confirmed users.
  if (!user) {
    lastResendByEmail.set(email, now);
    return { ok: true, email };
  }
  if (user.email_confirmed_at) {
    lastResendByEmail.set(email, now);
    return { ok: true, email };
  }

  await issueConfirmation(user.id, email);
  lastResendByEmail.set(email, now);
  return { ok: true, email };
}

export function authMailStatus() {
  return {
    mailConfigured: mailConfigured(),
    adminConfigured: supabaseAdminConfigured(),
    publicWebOrigin: publicWebOrigin(),
    expiresHours: EXPIRES_HOURS,
    passwordPolicy: PASSWORD_REQUIREMENTS_HINT,
  };
}
