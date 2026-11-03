/**
 * Matterya-owned password reset.
 * Emails go through Resend as Matterya <no-reply@matterya.com> — never Supabase Auth mail.
 */
import crypto from 'node:crypto';
import { pool } from '../db.js';
import { setAuthUserPassword, supabaseAdminConfigured } from '../supabase-admin.js';
import {
  buildResetPasswordEmailHtml,
  buildResetPasswordEmailText,
  mailConfigured,
  mailFromAddress,
  publicWebOrigin,
  sendMail,
} from '../mail/mail.service.js';
import { assertStrongPassword } from './password-policy.js';

const EXPIRES_HOURS = Number(process.env.PASSWORD_RESET_EXPIRES_HOURS ?? 2);
const requestCooldownMs = 60_000;
const lastRequestByEmail = new Map<string, number>();

type AuthUserRow = {
  id: string;
  email?: string | null;
  email_confirmed_at?: string | null;
};

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function validateEmail(email: string): void {
  if (!email || email.trim().length === 0) {
    throw Object.assign(new Error('Email is required. Enter your email address.'), {
      code: 'EMPTY_EMAIL',
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

async function findAuthUserByEmail(email: string): Promise<AuthUserRow | null> {
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
}

function resetUrlForToken(token: string): string {
  return `${publicWebOrigin()}/reset-password?token=${encodeURIComponent(token)}`;
}

const neutralOkMessage =
  'If an account exists for that email, we sent a Matterya password reset link from no-reply@matterya.com. Open it to choose a new password.';

/**
 * Request a reset email. Always returns the same neutral message so we do not
 * leak whether the address is registered.
 */
export async function requestPasswordReset(
  rawEmail: string
): Promise<{ ok: true; message: string; emailSent: boolean; from?: string }> {
  if (!supabaseAdminConfigured()) {
    throw Object.assign(new Error('Password reset is temporarily unavailable.'), {
      code: 'ADMIN_NOT_CONFIGURED',
      status: 503,
    });
  }

  if (!mailConfigured() && (process.env.ALLOW_SKIP_EMAIL ?? '').trim() !== 'true') {
    throw Object.assign(
      new Error(
        'Cannot send from no-reply@matterya.com yet: set RESEND_API_KEY on Render and verify matterya.com in Resend (DNS). MAIL_FROM should be: Matterya <no-reply@matterya.com>'
      ),
      { code: 'MAIL_NOT_CONFIGURED', status: 503 }
    );
  }

  const email = normalizeEmail(rawEmail);
  validateEmail(email);

  const now = Date.now();
  const last = lastRequestByEmail.get(email) ?? 0;
  if (now - last < requestCooldownMs) {
    throw Object.assign(new Error('Please wait a minute before requesting another email.'), {
      code: 'RATE_LIMITED',
      status: 429,
    });
  }
  lastRequestByEmail.set(email, now);

  const user = await findAuthUserByEmail(email);
  // Only confirmed accounts get a reset link (signup still unfinished → confirm first).
  if (!user?.email_confirmed_at) {
    return { ok: true, message: neutralOkMessage, emailSent: false };
  }

  const token = crypto.randomBytes(32).toString('hex');
  const expiresAt = new Date(Date.now() + EXPIRES_HOURS * 60 * 60 * 1000);
  const from = mailFromAddress();

  try {
    await pool.query(
      `
      insert into public.password_resets (user_id, email, token, expires_at)
      values ($1::uuid, $2, $3, $4::timestamptz)
      `,
      [user.id, email, token, expiresAt.toISOString()]
    );
  } catch (err: any) {
    const msg = String(err?.message ?? err);
    if (err?.code === '42P01' || msg.includes('password_resets')) {
      throw Object.assign(
        new Error(
          'Password reset table is missing. Apply migration 20261103240000_password_resets.sql on Supabase.'
        ),
        { code: 'MIGRATION_REQUIRED', status: 503 }
      );
    }
    throw err;
  }

  const resetUrl = resetUrlForToken(token);
  const send = await sendMail({
    to: email,
    subject: 'Reset your Matterya password',
    html: buildResetPasswordEmailHtml({ email, resetUrl, expiresHours: EXPIRES_HOURS }),
    text: buildResetPasswordEmailText({ email, resetUrl, expiresHours: EXPIRES_HOURS }),
  });

  if (send.skipped) {
    console.info('[auth] password reset link (mail skipped / dev):', resetUrl);
  }

  return {
    ok: true,
    message: neutralOkMessage,
    emailSent: !send.skipped,
    from,
  };
}

/** Consume a one-time token and set a strong new password via admin API. */
export async function resetPasswordWithToken(
  token: string,
  newPassword: unknown
): Promise<{ ok: true; email: string }> {
  const clean = (token ?? '').trim();
  if (!clean || clean.length < 16) {
    throw Object.assign(new Error('Invalid or missing password reset link.'), {
      code: 'INVALID_TOKEN',
      status: 400,
    });
  }

  assertStrongPassword(newPassword);
  const strongPassword = String(newPassword);

  if (!supabaseAdminConfigured()) {
    throw Object.assign(new Error('Password reset is temporarily unavailable.'), {
      code: 'ADMIN_NOT_CONFIGURED',
      status: 503,
    });
  }

  let rows: any[];
  try {
    const result = await pool.query(
      `
      select id, user_id::text as user_id, email, expires_at, used_at
      from public.password_resets
      where token = $1
      limit 1
      `,
      [clean]
    );
    rows = result.rows;
  } catch (err: any) {
    if (err?.code === '42P01') {
      throw Object.assign(
        new Error(
          'Password reset table is missing. Apply migration 20261103240000_password_resets.sql on Supabase.'
        ),
        { code: 'MIGRATION_REQUIRED', status: 503 }
      );
    }
    throw err;
  }

  const row = rows[0] as
    | {
        id: string;
        user_id: string;
        email: string;
        expires_at: string;
        used_at: string | null;
      }
    | undefined;

  if (!row) {
    throw Object.assign(new Error('This password reset link is invalid.'), {
      code: 'TOKEN_NOT_FOUND',
      status: 404,
    });
  }

  if (row.used_at) {
    throw Object.assign(new Error('This password reset link was already used. Request a new one.'), {
      code: 'TOKEN_USED',
      status: 410,
    });
  }

  if (new Date(row.expires_at).getTime() < Date.now()) {
    throw Object.assign(
      new Error('This password reset link has expired. Request a new one from the login screen.'),
      { code: 'TOKEN_EXPIRED', status: 410 }
    );
  }

  await setAuthUserPassword(row.user_id, strongPassword);
  await pool.query(`update public.password_resets set used_at = now() where id = $1`, [row.id]);
  // Invalidate any other unused tokens for this user.
  await pool.query(
    `
    update public.password_resets
    set used_at = coalesce(used_at, now())
    where user_id = $1::uuid and used_at is null and id <> $2
    `,
    [row.user_id, row.id]
  );

  return { ok: true, email: row.email };
}
