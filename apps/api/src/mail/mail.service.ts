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

export function mailConfigured(): boolean {
  return Boolean((process.env.RESEND_API_KEY ?? '').trim());
}

export function mailFromAddress(): string {
  return (
    (process.env.MAIL_FROM ?? '').trim() ||
    'Matterya <noreply@matterya.com>'
  );
}

export async function sendMail(input: SendMailInput): Promise<{ ok: boolean; id?: string; skipped?: boolean }> {
  const apiKey = (process.env.RESEND_API_KEY ?? '').trim();
  if (!apiKey) {
    console.warn(
      '[mail] RESEND_API_KEY not set — email not sent. To:',
      input.to,
      'Subject:',
      input.subject
    );
    return { ok: true, skipped: true };
  }

  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: mailFromAddress(),
      to: [input.to],
      subject: input.subject,
      html: input.html,
      text: input.text,
    }),
  });

  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`MAIL_SEND_FAILED: ${res.status} ${body.slice(0, 300)}`);
  }

  const json = (await res.json().catch(() => ({}))) as { id?: string };
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

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}
