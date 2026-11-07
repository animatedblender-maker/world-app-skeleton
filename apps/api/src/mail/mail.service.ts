/**
 * Matterya outbound email (signup confirmation, etc.).
 * Preferred: Resend API (RESEND_API_KEY).
 * Optional: generic SMTP HTTP bridge not required — Resend is enough for prod.
 */

export type SendMailInput = {
  to: string;
  subject: string;
  html: string;
  text?: string;
};

/** Read Resend API key (primary + common typos / aliases). */
export function resendApiKey(): string {
  return (
    process.env.RESEND_API_KEY ??
    process.env.RESEND_KEY ??
    process.env.RESEND_API ??
    ''
  ).trim();
}

export function mailConfigured(): boolean {
  return Boolean(resendApiKey());
}

/** Default sender for Matterya product mail — requires domain verified at Resend. */
export function mailFromAddress(): string {
  const raw = (process.env.MAIL_FROM ?? '').trim();
  const fallback = 'Matterya <no-reply@matterya.com>';
  if (!raw) return fallback;
  // Legacy Render MAIL_FROM used noreply@ — always ship as no-reply@.
  return raw.replace(/\bnoreply@matterya\.com\b/gi, 'no-reply@matterya.com');
}

/**
 * When RESEND_API_KEY is missing:
 * - production / default → throw (never pretend we emailed)
 * - ALLOW_SKIP_EMAIL=true → log and skip (local dev only)
 */
export async function sendMail(input: SendMailInput): Promise<{ ok: boolean; id?: string; skipped?: boolean }> {
  const apiKey = resendApiKey();
  const allowSkip = (process.env.ALLOW_SKIP_EMAIL ?? '').trim() === 'true';

  if (!apiKey) {
    const msg =
      'Email delivery is not configured on the server (missing RESEND_API_KEY). In Render → matterya-api → Environment add RESEND_API_KEY=re_… then Manual Deploy.';
    console.error('[mail]', msg, 'To:', input.to, 'Subject:', input.subject);
    if (allowSkip) {
      console.warn('[mail] ALLOW_SKIP_EMAIL=true — skipping send (dev only).');
      return { ok: true, skipped: true };
    }
    throw Object.assign(new Error(msg), { code: 'MAIL_NOT_CONFIGURED', status: 503 });
  }

  const from = mailFromAddress();
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from,
      to: [input.to],
      subject: input.subject,
      html: input.html,
      text: input.text,
    }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    // Surface Resend domain / auth issues clearly (common: unverified from-domain).
    let detail = body.slice(0, 400);
    try {
      const j = JSON.parse(body) as { message?: string; name?: string };
      if (j?.message) detail = j.message;
    } catch {
      /* keep raw */
    }
    console.error('[mail] Resend failed', res.status, detail, 'from=', from);
    throw Object.assign(
      new Error(
        res.status === 403 || /domain|not verified|from/i.test(detail)
          ? `Could not send email: the sender domain for "${from}" is not verified in Resend. Verify matterya.com (or set MAIL_FROM to a verified address).`
          : `Could not send confirmation email (${res.status}). ${detail}`
      ),
      { code: 'MAIL_SEND_FAILED', status: 502 }
    );
  }

  const json = (await res.json().catch(() => ({}))) as { id?: string };
  console.info('[mail] sent', json.id, 'to', input.to);
  return { ok: true, id: json.id };
}

export function publicWebOrigin(): string {
  const raw =
    (process.env.PUBLIC_WEB_ORIGIN ?? '').trim() ||
    (process.env.WEB_ORIGIN ?? '').trim() ||
    'https://matterya.com';
  return raw.replace(/\/$/, '');
}

export function buildConfirmEmailHtml(opts: {
  email: string;
  confirmUrl: string;
  expiresHours: number;
}): string {
  const { email, confirmUrl, expiresHours } = opts;
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Confirm your Matterya account</title>
</head>
<body style="margin:0;padding:0;background:#f6f4ef;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1c1917;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f6f4ef;padding:32px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width:520px;background:#ffffff;border-radius:16px;border:1px solid #e7e5e4;overflow:hidden;">
          <tr>
            <td style="padding:28px 28px 8px;text-align:center;">
              <div style="font-size:28px;font-weight:700;letter-spacing:-0.02em;">Matterya</div>
              <div style="margin-top:6px;font-size:14px;color:#78716c;">Confirm your account</div>
            </td>
          </tr>
          <tr>
            <td style="padding:12px 28px 8px;font-size:15px;line-height:1.55;color:#44403c;">
              Hi — someone signed up for Matterya with <strong>${escapeHtml(email)}</strong>.
              Tap the button below to confirm this email and finish creating your account.
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:20px 28px;">
              <a href="${escapeHtml(confirmUrl)}"
                 style="display:inline-block;background:#0f766e;color:#ffffff;text-decoration:none;font-weight:700;font-size:15px;padding:14px 28px;border-radius:12px;">
                Confirm my email
              </a>
            </td>
          </tr>
          <tr>
            <td style="padding:0 28px 12px;font-size:13px;line-height:1.5;color:#78716c;">
              Or paste this link into your browser:<br />
              <a href="${escapeHtml(confirmUrl)}" style="color:#0f766e;word-break:break-all;">${escapeHtml(confirmUrl)}</a>
            </td>
          </tr>
          <tr>
            <td style="padding:8px 28px 28px;font-size:12px;line-height:1.5;color:#a8a29e;">
              This link expires in ${expiresHours} hours. If you didn’t create a Matterya account, you can ignore this email.
            </td>
          </tr>
        </table>
        <div style="margin-top:16px;font-size:11px;color:#a8a29e;">© Matterya · matterya.com</div>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

export function buildConfirmEmailText(opts: {
  email: string;
  confirmUrl: string;
  expiresHours: number;
}): string {
  return [
    'Confirm your Matterya account',
    '',
    `Someone signed up with ${opts.email}.`,
    `Open this link to confirm (expires in ${opts.expiresHours} hours):`,
    opts.confirmUrl,
    '',
    'If you did not sign up, ignore this email.',
    '— Matterya',
  ].join('\n');
}

/** Shared Matterya product email chrome (confirm + reset). */
function matteryaMailShell(opts: {
  title: string;
  eyebrow: string;
  bodyHtml: string;
  ctaLabel: string;
  ctaUrl: string;
  footerNote: string;
}): string {
  return `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(opts.title)}</title>
</head>
<body style="margin:0;padding:0;background:#f6f4ef;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;color:#1c1917;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f6f4ef;padding:32px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width:520px;background:#ffffff;border-radius:16px;border:1px solid #e7e5e4;overflow:hidden;">
          <tr>
            <td style="padding:28px 28px 8px;text-align:center;">
              <div style="font-size:28px;font-weight:700;letter-spacing:-0.02em;">Matterya</div>
              <div style="margin-top:6px;font-size:14px;color:#78716c;">${escapeHtml(opts.eyebrow)}</div>
            </td>
          </tr>
          <tr>
            <td style="padding:12px 28px 8px;font-size:15px;line-height:1.55;color:#44403c;">
              ${opts.bodyHtml}
            </td>
          </tr>
          <tr>
            <td align="center" style="padding:20px 28px;">
              <a href="${escapeHtml(opts.ctaUrl)}"
                 style="display:inline-block;background:#0f766e;color:#ffffff;text-decoration:none;font-weight:700;font-size:15px;padding:14px 28px;border-radius:12px;">
                ${escapeHtml(opts.ctaLabel)}
              </a>
            </td>
          </tr>
          <tr>
            <td style="padding:0 28px 12px;font-size:13px;line-height:1.5;color:#78716c;">
              Or paste this link into your browser:<br />
              <a href="${escapeHtml(opts.ctaUrl)}" style="color:#0f766e;word-break:break-all;">${escapeHtml(opts.ctaUrl)}</a>
            </td>
          </tr>
          <tr>
            <td style="padding:8px 28px 28px;font-size:12px;line-height:1.5;color:#a8a29e;">
              ${escapeHtml(opts.footerNote)}
            </td>
          </tr>
        </table>
        <div style="margin-top:16px;font-size:11px;color:#a8a29e;">© Matterya · matterya.com · no-reply@matterya.com</div>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

export function buildResetPasswordEmailHtml(opts: {
  email: string;
  resetUrl: string;
  expiresHours: number;
}): string {
  const { email, resetUrl, expiresHours } = opts;
  return matteryaMailShell({
    title: 'Reset your Matterya password',
    eyebrow: 'Password reset',
    bodyHtml: `Hi — we received a request to reset the password for <strong>${escapeHtml(email)}</strong>.
              Tap the button below to choose a new password.`,
    ctaLabel: 'Reset my password',
    ctaUrl: resetUrl,
    footerNote: `This link expires in ${expiresHours} hours. If you did not ask to reset your password, you can ignore this email.`,
  });
}

export function buildResetPasswordEmailText(opts: {
  email: string;
  resetUrl: string;
  expiresHours: number;
}): string {
  return [
    'Reset your Matterya password',
    '',
    `We received a request to reset the password for ${opts.email}.`,
    `Open this link to choose a new password (expires in ${opts.expiresHours} hours):`,
    opts.resetUrl,
    '',
    'If you did not ask to reset your password, ignore this email.',
    '— Matterya',
  ].join('\n');
}

/** Notice after password actually changed (Settings change or forgot-password complete). */
export function buildPasswordChangedEmailHtml(opts: {
  email: string;
  supportUrl: string;
}): string {
  const { email, supportUrl } = opts;
  return matteryaMailShell({
    title: 'Your Matterya password was changed',
    eyebrow: 'Security notice',
    bodyHtml: `The password for <strong>${escapeHtml(email)}</strong> was just changed.
              If you made this change, you’re all set — you can keep using Matterya as usual.
              If you did <strong>not</strong> change it, reset your password right away and contact support.`,
    ctaLabel: 'Open Matterya',
    ctaUrl: supportUrl,
    footerNote:
      'This is an automated security notice from Matterya. We never ask for your password by email.',
  });
}

export function buildPasswordChangedEmailText(opts: {
  email: string;
  supportUrl: string;
}): string {
  return [
    'Your Matterya password was changed',
    '',
    `The password for ${opts.email} was just changed.`,
    'If you made this change, you can ignore this email.',
    'If you did not change it, reset your password immediately:',
    opts.supportUrl,
    '',
    '— Matterya',
  ].join('\n');
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
