import { createHmac, timingSafeEqual } from 'node:crypto';
import type { Request, Response } from 'express';
import {
  getEngagementReport,
  renderEngagementReportHtml,
} from '../engagement/engagement.service.js';

/** Password gate for the public Matterya reports page (override via env). */
export const REPORTS_PAGE_PASSWORD =
  process.env.REPORTS_PAGE_PASSWORD?.trim() || '54isamr!';

const COOKIE_NAME = 'matterya_reports_auth';
const COOKIE_TTL_SEC = 60 * 60 * 24 * 14; // 14 days

function cookieSecret(): string {
  return (
    process.env.REPORTS_COOKIE_SECRET?.trim() ||
    process.env.ADMIN_PORTAL_KEY?.trim() ||
    'matterya-reports-cookie-v1'
  );
}

function signToken(): string {
  const exp = Math.floor(Date.now() / 1000) + COOKIE_TTL_SEC;
  const body = `ok.${exp}`;
  const sig = createHmac('sha256', cookieSecret()).update(body).digest('hex');
  return `${body}.${sig}`;
}

function verifyToken(token: string | undefined | null): boolean {
  if (!token || typeof token !== 'string') return false;
  const parts = token.split('.');
  if (parts.length !== 3 || parts[0] !== 'ok') return false;
  const exp = Number(parts[1]);
  if (!Number.isFinite(exp) || exp < Math.floor(Date.now() / 1000)) return false;
  const body = `${parts[0]}.${parts[1]}`;
  const expected = createHmac('sha256', cookieSecret()).update(body).digest('hex');
  try {
    const a = Buffer.from(parts[2], 'utf8');
    const b = Buffer.from(expected, 'utf8');
    if (a.length !== b.length) return false;
    return timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

function parseCookies(req: Request): Record<string, string> {
  const raw = req.headers.cookie ?? '';
  const out: Record<string, string> = {};
  for (const part of raw.split(';')) {
    const i = part.indexOf('=');
    if (i <= 0) continue;
    const k = part.slice(0, i).trim();
    const v = part.slice(i + 1).trim();
    if (k) out[k] = decodeURIComponent(v);
  }
  return out;
}

export function hasReportsAccess(req: Request): boolean {
  const cookies = parseCookies(req);
  if (verifyToken(cookies[COOKIE_NAME])) return true;
  // Still allow admin portal key / query for automation.
  const adminKey = process.env.ADMIN_PORTAL_KEY || 'worldapp-admin-2026';
  const key = String(req.headers['x-admin-key'] ?? req.query.key ?? '').trim();
  if (adminKey && key === adminKey) return true;
  return false;
}

function passwordOk(input: unknown): boolean {
  const got = String(input ?? '');
  const want = REPORTS_PAGE_PASSWORD;
  try {
    const a = Buffer.from(got, 'utf8');
    const b = Buffer.from(want, 'utf8');
    if (a.length !== b.length) return false;
    return timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

function setAuthCookie(res: Response): void {
  const token = signToken();
  const secure = process.env.NODE_ENV === 'production' || process.env.RENDER === 'true';
  res.setHeader(
    'Set-Cookie',
    [
      `${COOKIE_NAME}=${encodeURIComponent(token)}`,
      'Path=/',
      'HttpOnly',
      'SameSite=Lax',
      `Max-Age=${COOKIE_TTL_SEC}`,
      secure ? 'Secure' : '',
    ]
      .filter(Boolean)
      .join('; ')
  );
}

function clearAuthCookie(res: Response): void {
  res.setHeader(
    'Set-Cookie',
    `${COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`
  );
}

/** Matterya paper login gate. */
export function renderReportsLoginHtml(opts?: { error?: string; next?: string }): string {
  const err = opts?.error
    ? `<p class="err">${escapeHtml(opts.error)}</p>`
    : '';
  const next = escapeHtml(opts?.next || '/reports');
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Matterya · Reports</title>
  <style>
    :root {
      --paper: #f8f6f2;
      --ink: #2c2825;
      --muted: #7a736c;
      --accent: #7b6347;
      --border: #ddd6cc;
      --surface: #fffcf8;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; min-height: 100vh; display: grid; place-items: center;
      font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
      background: radial-gradient(1200px 600px at 20% 0%, #efe8dc 0%, var(--paper) 55%);
      color: var(--ink);
    }
    .card {
      width: min(400px, 92vw);
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 18px;
      padding: 28px 26px 24px;
      box-shadow: 0 18px 40px rgba(44,40,37,0.08);
    }
    .mark {
      font-size: 11px; font-weight: 700; letter-spacing: 0.22em; text-transform: uppercase;
      color: var(--accent); margin-bottom: 10px;
    }
    h1 {
      margin: 0 0 6px; font-size: 1.55rem; font-weight: 500;
      font-family: ui-serif, Georgia, "Times New Roman", serif;
    }
    .sub { margin: 0 0 22px; color: var(--muted); font-size: 0.95rem; line-height: 1.45; }
    label { display: block; font-size: 12px; font-weight: 600; color: var(--muted); margin-bottom: 6px; }
    input[type=password] {
      width: 100%; padding: 12px 14px; border-radius: 10px;
      border: 1px solid var(--border); background: #fff; font-size: 15px; color: var(--ink);
    }
    input:focus { outline: 2px solid rgba(123,99,71,0.25); border-color: var(--accent); }
    button {
      margin-top: 16px; width: 100%; border: 0; border-radius: 999px; padding: 12px 16px;
      background: var(--accent); color: #fff; font-weight: 650; font-size: 14px; cursor: pointer;
    }
    button:hover { filter: brightness(1.05); }
    .err { color: #b91c1c; font-size: 13px; margin: 0 0 12px; }
    .foot { margin-top: 18px; font-size: 12px; color: #a8a29e; text-align: center; }
  </style>
</head>
<body>
  <form class="card" method="post" action="/reports/login" autocomplete="current-password">
    <div class="mark">Matterya</div>
    <h1>Platform reports</h1>
    <p class="sub">Activity, uploads, and live stats. Enter the reports password to continue.</p>
    ${err}
    <label for="password">Password</label>
    <input id="password" name="password" type="password" required autofocus placeholder="••••••••"/>
    <input type="hidden" name="next" value="${next}"/>
    <button type="submit">Open reports</button>
    <p class="foot">matterya.com · private statistics</p>
  </form>
</body>
</html>`;
}

function escapeHtml(s: string): string {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function wrapReportHtml(reportHtml: string): string {
  // Inject logout + Matterya brand bar into the existing report document.
  const bar = `
  <div style="position:sticky;top:0;z-index:50;display:flex;align-items:center;justify-content:space-between;gap:12px;padding:10px 24px;background:#2c2825;color:#f8f6f2;font:600 12px/1.2 ui-sans-serif,system-ui,sans-serif;letter-spacing:.08em;text-transform:uppercase">
    <span>Matterya · Reports</span>
    <a href="/reports/logout" style="color:#f8f6f2;text-decoration:none;opacity:.85">Log out</a>
  </div>`;
  if (reportHtml.includes('<body>')) {
    return reportHtml.replace('<body>', `<body>${bar}`);
  }
  return bar + reportHtml;
}

/** GET /reports — login or full report HTML */
export async function handleReportsGet(req: Request, res: Response): Promise<void> {
  if (!hasReportsAccess(req)) {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.status(200).send(renderReportsLoginHtml({ next: '/reports' }));
    return;
  }
  try {
    const hours = Number(req.query.hours ?? 24);
    const report = await getEngagementReport(hours);
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.status(200).send(wrapReportHtml(renderEngagementReportHtml(report)));
  } catch (err: any) {
    res.status(500).type('html').send(
      renderReportsLoginHtml({
        error: err?.message ?? 'Could not load report',
      })
    );
  }
}

/** POST /reports/login */
export function handleReportsLogin(req: Request, res: Response): void {
  const body = (req.body ?? {}) as { password?: string; next?: string };
  if (!passwordOk(body.password)) {
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.status(401).send(
      renderReportsLoginHtml({
        error: 'Incorrect password. Try again.',
        next: body.next || '/reports',
      })
    );
    return;
  }
  setAuthCookie(res);
  const next = String(body.next || '/reports').startsWith('/reports')
    ? String(body.next || '/reports')
    : '/reports';
  res.redirect(303, next);
}

/** GET /reports/logout */
export function handleReportsLogout(_req: Request, res: Response): void {
  clearAuthCookie(res);
  res.redirect(303, '/reports');
}
