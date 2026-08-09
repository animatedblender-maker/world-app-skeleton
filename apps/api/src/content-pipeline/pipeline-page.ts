import { createHmac, timingSafeEqual } from 'node:crypto';
import type { Request, Response } from 'express';
import { getPipelineStatus, requestPipelineRun, runPipelineNow } from './jobs.js';
import { r2Configured } from './r2.js';
import { kafkaEnabled } from '../kafka/config.js';

/**
 * Password for /pipeline ops page.
 * Defaults to same as reports so one password runs the platform.
 */
export const PIPELINE_PAGE_PASSWORD =
  process.env.CONTENT_PIPELINE_PASSWORD?.trim() ||
  process.env.REPORTS_PAGE_PASSWORD?.trim() ||
  '54isamr!';

const COOKIE_NAME = 'matterya_pipeline_auth';
const COOKIE_TTL_SEC = 60 * 60 * 24 * 14;

function cookieSecret(): string {
  return (
    process.env.REPORTS_COOKIE_SECRET?.trim() ||
    process.env.ADMIN_PORTAL_KEY?.trim() ||
    process.env.CONTENT_CRON_SECRET?.trim() ||
    'matterya-pipeline-cookie-v1'
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

export function hasPipelineAccess(req: Request): boolean {
  const cookies = parseCookies(req);
  if (verifyToken(cookies[COOKIE_NAME])) return true;
  const cron =
    process.env.CONTENT_CRON_SECRET?.trim() ||
    process.env.INSIGHTS_CRON_SECRET?.trim() ||
    '';
  const header = String(req.headers['x-cron-secret'] ?? req.query.secret ?? '').trim();
  if (cron && header === cron) return true;
  const adminKey = process.env.ADMIN_PORTAL_KEY || 'worldapp-admin-2026';
  const key = String(req.headers['x-admin-key'] ?? req.query.key ?? '').trim();
  if (adminKey && key === adminKey) return true;
  return false;
}

function passwordOk(input: unknown): boolean {
  const got = String(input ?? '');
  const want = PIPELINE_PAGE_PASSWORD;
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

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function loginHtml(err?: string): string {
  const error = err ? `<p class="err">${escapeHtml(err)}</p>` : '';
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Matterya · Content pipeline</title>
  <style>
    :root { --paper:#f8f6f2; --ink:#2c2825; --muted:#7a736c; --accent:#7b6347; --border:#ddd6cc; --surface:#fffcf8; }
    * { box-sizing: border-box; }
    body { margin:0; min-height:100vh; display:grid; place-items:center;
      font-family: system-ui, -apple-system, sans-serif;
      background: radial-gradient(1200px 600px at 20% 0%, #efe8dc 0%, var(--paper) 55%); color:var(--ink); }
    .card { width:min(420px,92vw); background:var(--surface); border:1px solid var(--border);
      border-radius:18px; padding:28px 26px; box-shadow:0 18px 40px rgba(44,40,37,0.08); }
    .mark { font-size:11px; font-weight:700; letter-spacing:0.22em; text-transform:uppercase; color:var(--accent); }
    h1 { margin:10px 0 6px; font-size:1.5rem; font-weight:500; font-family: ui-serif, Georgia, serif; }
    .sub { color:var(--muted); font-size:0.95rem; line-height:1.45; margin:0 0 20px; }
    label { display:block; font-size:12px; font-weight:600; color:var(--muted); margin-bottom:6px; }
    input { width:100%; padding:12px 14px; border-radius:10px; border:1px solid var(--border); font-size:15px; }
    button { margin-top:16px; width:100%; border:0; border-radius:999px; padding:12px 16px;
      background:var(--accent); color:#fff; font-weight:650; cursor:pointer; }
    .err { color:#b91c1c; font-size:13px; }
  </style>
</head>
<body>
  <form class="card" method="post" action="/pipeline/login">
    <div class="mark">Matterya</div>
    <h1>Content pipeline</h1>
    <p class="sub">Pull new R2 Sparks into Supabase as owned posts + feed shares. Same password as Reports unless you set CONTENT_PIPELINE_PASSWORD.</p>
    ${error}
    <label for="password">Password</label>
    <input id="password" name="password" type="password" required autofocus/>
    <button type="submit">Open pipeline</button>
  </form>
</body>
</html>`;
}

function dashboardHtml(flash?: { ok?: boolean; text?: string }): string {
  const st = getPipelineStatus();
  const last = st.lastRun
    ? `<pre class="stats">${escapeHtml(JSON.stringify(st.lastRun, null, 2))}</pre>`
    : `<p class="muted">No run in this process yet.</p>`;
  const flashHtml = flash?.text
    ? `<div class="flash ${flash.ok ? 'ok' : 'bad'}">${escapeHtml(flash.text)}</div>`
    : '';
  const r2 = st.r2Configured ? 'ready' : 'missing env';
  const kafka = st.kafkaEnabled ? 'on (jobs → matterya.r2.ingest)' : 'off (runs inline)';

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Matterya · Content pipeline</title>
  <style>
    :root { --paper:#f8f6f2; --ink:#2c2825; --muted:#7a736c; --accent:#7b6347; --border:#ddd6cc; --surface:#fffcf8; }
    * { box-sizing: border-box; }
    body { margin:0; font-family: system-ui, -apple-system, sans-serif; background:var(--paper); color:var(--ink); }
    header { padding:20px 24px; border-bottom:1px solid var(--border); background:var(--surface);
      display:flex; flex-wrap:wrap; gap:12px; align-items:center; justify-content:space-between; }
    .mark { font-size:11px; font-weight:700; letter-spacing:0.2em; text-transform:uppercase; color:var(--accent); }
    h1 { margin:4px 0 0; font-size:1.35rem; font-weight:500; font-family: ui-serif, Georgia, serif; }
    main { max-width:720px; margin:0 auto; padding:24px 16px 48px; }
    .card { background:var(--surface); border:1px solid var(--border); border-radius:16px; padding:20px; margin-bottom:16px; }
    .row { display:flex; flex-wrap:wrap; gap:10px; margin-top:12px; }
    button, .btn {
      border:0; border-radius:999px; padding:11px 18px; font-weight:650; font-size:13px; cursor:pointer;
      background:var(--accent); color:#fff; text-decoration:none; display:inline-block;
    }
    button.secondary { background:#e8e2d8; color:var(--ink); }
    button:disabled { opacity:0.55; cursor:wait; }
    .pill { display:inline-block; padding:4px 10px; border-radius:999px; font-size:12px; font-weight:600;
      background:#e8e2d8; color:var(--ink); margin-right:6px; }
    .pill.ok { background:#dcfce7; color:#166534; }
    .pill.bad { background:#fee2e2; color:#991b1b; }
    .muted { color:var(--muted); font-size:14px; line-height:1.5; }
    pre.stats { background:#1c1917; color:#f5f5f4; padding:14px; border-radius:12px; overflow:auto; font-size:12px; }
    .flash { padding:12px 14px; border-radius:12px; margin-bottom:16px; font-size:14px; }
    .flash.ok { background:#dcfce7; color:#166534; }
    .flash.bad { background:#fee2e2; color:#991b1b; }
    ul { margin:8px 0 0; padding-left:18px; color:var(--muted); font-size:14px; line-height:1.55; }
    a.out { color:var(--accent); font-size:13px; }
  </style>
</head>
<body>
  <header>
    <div>
      <div class="mark">Matterya ops</div>
      <h1>Content pipeline</h1>
    </div>
    <div>
      <a class="out" href="/reports">Reports</a>
      ·
      <a class="out" href="/pipeline/logout">Log out</a>
    </div>
  </header>
  <main>
    ${flashHtml}
    <div class="card">
      <span class="pill ${st.r2Configured ? 'ok' : 'bad'}">R2 ${r2}</span>
      <span class="pill ${st.kafkaEnabled ? 'ok' : ''}">Kafka ${kafka}</span>
      <span class="pill ${st.running ? 'bad' : 'ok'}">${st.running ? 'running…' : 'idle'}</span>
      <p class="muted" style="margin-top:14px">
        Discovers new packs in the R2 bucket, creates <strong>owned</strong> Sparks (real profiles),
        creates home-feed <strong>spark shares</strong>, re-signs media URLs, and emits
        <code>ContentPosted</code> through the Kafka outbox when Kafka is on.
      </p>
      <ul>
        <li>Originals → Sparks player</li>
        <li>Shares → home feed (newest first after pull-to-refresh)</li>
        <li>Never invents users — skips countries with no profiles</li>
      </ul>
    </div>

    <div class="card">
      <strong>Run</strong>
      <p class="muted">“Run now” executes in this API process. “Queue via Kafka” enqueues <code>R2IngestRequested</code> (needs Kafka consumer).</p>
      <form class="row" method="post" action="/pipeline/run">
        <input type="hidden" name="mode" value="inline"/>
        <button type="submit" ${st.running ? 'disabled' : ''}>Run now</button>
      </form>
      <form class="row" method="post" action="/pipeline/run" style="margin-top:8px">
        <input type="hidden" name="mode" value="inline"/>
        <input type="hidden" name="dryRun" value="1"/>
        <button class="secondary" type="submit" ${st.running ? 'disabled' : ''}>Dry run</button>
      </form>
      <form class="row" method="post" action="/pipeline/run" style="margin-top:8px">
        <input type="hidden" name="mode" value="inline"/>
        <input type="hidden" name="resignOnly" value="1"/>
        <button class="secondary" type="submit" ${st.running ? 'disabled' : ''}>Re-sign URLs only</button>
      </form>
      <form class="row" method="post" action="/pipeline/run" style="margin-top:8px">
        <input type="hidden" name="mode" value="kafka"/>
        <button class="secondary" type="submit" ${st.running || !st.kafkaEnabled ? 'disabled' : ''}>
          Queue via Kafka
        </button>
      </form>
    </div>

    <div class="card">
      <strong>Last run</strong>
      ${last}
    </div>

    <div class="card">
      <strong>Render env checklist</strong>
      <ul>
        <li><code>R2_ACCESS_KEY_ID</code> · <code>R2_SECRET_ACCESS_KEY</code> · <code>R2_ACCOUNT_ID</code> (or <code>R2_ENDPOINT</code>) · <code>R2_BUCKET</code></li>
        <li><code>CONTENT_CRON_SECRET</code> (any long random string you choose — for curl cron)</li>
        <li><code>CONTENT_PIPELINE_PASSWORD</code> optional (defaults to reports password)</li>
        <li>Kafka optional: <code>KAFKA_ENABLED=true</code> + brokers — then cron can enqueue instead of blocking HTTP</li>
      </ul>
      <p class="muted">Cron example:<br/>
      <code>curl -X POST https://api.matterya.com/cron/content-pipeline -H "x-cron-secret: YOUR_SECRET"</code></p>
    </div>
  </main>
</body>
</html>`;
}

export async function handlePipelineGet(req: Request, res: Response): Promise<void> {
  if (!hasPipelineAccess(req)) {
    res.status(200).type('html').send(loginHtml());
    return;
  }
  res.status(200).type('html').send(dashboardHtml());
}

export function handlePipelineLogin(req: Request, res: Response): void {
  if (!passwordOk(req.body?.password)) {
    res.status(401).type('html').send(loginHtml('Wrong password'));
    return;
  }
  setAuthCookie(res);
  res.redirect(302, '/pipeline');
}

export function handlePipelineLogout(_req: Request, res: Response): void {
  clearAuthCookie(res);
  res.redirect(302, '/pipeline');
}

export async function handlePipelineRun(req: Request, res: Response): Promise<void> {
  if (!hasPipelineAccess(req)) {
    res.redirect(302, '/pipeline');
    return;
  }
  if (!r2Configured()) {
    res
      .status(200)
      .type('html')
      .send(
        dashboardHtml({
          ok: false,
          text: 'R2 not configured on this server. Set R2_* env vars on Render and redeploy.',
        })
      );
    return;
  }

  const mode = String(req.body?.mode ?? 'inline');
  const dryRun = String(req.body?.dryRun ?? '') === '1';
  const resignOnly = String(req.body?.resignOnly ?? '') === '1';

  try {
    if (mode === 'kafka' && kafkaEnabled()) {
      const result = await requestPipelineRun({
        dryRun,
        resignOnly,
        requestedBy: 'ops-page',
        forceInline: false,
        source: 'ops-page-kafka',
      });
      if (result.mode === 'kafka') {
        res.status(200).type('html').send(
          dashboardHtml({
            ok: true,
            text: `Queued on Kafka (event ${result.eventId ?? '?'}). Consumer will run the pipeline shortly.`,
          })
        );
        return;
      }
    }

    const stats = await runPipelineNow({
      dryRun,
      resignOnly,
      maxOriginals: 40,
      maxShares: 80,
      maxResign: 200,
      maxMs: 90_000,
      source: 'ops-page',
    });
    res.status(200).type('html').send(
      dashboardHtml({
        ok: stats.ok,
        text: stats.ok
          ? `Done: +${stats.insertedOriginals} originals, +${stats.insertedShares} shares, ${stats.resigned} resigned (${stats.ms}ms)`
          : `Finished with errors: ${(stats.errors || []).join('; ') || 'unknown'}`,
      })
    );
  } catch (err: any) {
    res.status(200).type('html').send(
      dashboardHtml({ ok: false, text: err?.message ?? 'Pipeline failed' })
    );
  }
}
