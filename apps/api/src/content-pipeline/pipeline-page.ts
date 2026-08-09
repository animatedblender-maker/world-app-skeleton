import { createHmac, timingSafeEqual } from 'node:crypto';
import type { Request, Response } from 'express';
import { getPipelineStatus, requestPipelineRun, runPipelineNow } from './jobs.js';
import {
  clearPipelineLog,
  getPipelineLogBuffer,
  subscribePipelineLog,
  type PipelineLogLine,
} from './log.js';
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
  const buffered = getPipelineLogBuffer();
  const seedLog = buffered
    .map((l) => formatLogLineHtml(l))
    .join('');

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
    main { max-width:900px; margin:0 auto; padding:24px 16px 48px; }
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
    .pill.run { background:#fef3c7; color:#92400e; }
    .muted { color:var(--muted); font-size:14px; line-height:1.5; }
    pre.stats { background:#1c1917; color:#f5f5f4; padding:14px; border-radius:12px; overflow:auto; font-size:12px; }
    #log {
      background:#0c0a09; color:#e7e5e4; padding:14px 16px; border-radius:12px;
      min-height:280px; max-height:55vh; overflow:auto; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size:12px; line-height:1.55; white-space:pre-wrap; word-break:break-word;
    }
    #log .t { color:#78716c; margin-right:8px; }
    #log .step { color:#fbbf24; font-weight:600; }
    #log .ok { color:#4ade80; }
    #log .warn { color:#fbbf24; }
    #log .error { color:#f87171; }
    #log .info { color:#d6d3d1; }
    .flash { padding:12px 14px; border-radius:12px; margin-bottom:16px; font-size:14px; }
    .flash.ok { background:#dcfce7; color:#166534; }
    .flash.bad { background:#fee2e2; color:#991b1b; }
    ul { margin:8px 0 0; padding-left:18px; color:var(--muted); font-size:14px; line-height:1.55; }
    a.out { color:var(--accent); font-size:13px; }
    #statusLine { font-weight:650; margin-top:10px; min-height:1.2em; }
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
      <span id="pillR2" class="pill ${st.r2Configured ? 'ok' : 'bad'}">R2 ${r2}</span>
      <span id="pillKafka" class="pill ${st.kafkaEnabled ? 'ok' : ''}">Kafka ${kafka}</span>
      <span id="pillRun" class="pill ${st.running ? 'run' : 'ok'}">${st.running ? 'running…' : 'idle'}</span>
      <p class="muted" style="margin-top:14px">
        Use <strong>Run now</strong> for a full sync. The live log below shows every step.
      </p>
    </div>

    <div class="card">
      <strong>Run</strong>
      <p class="muted">Click a button — progress streams live (no blank “waiting” page).</p>
      <div class="row">
        <button type="button" id="btnRun" data-mode="run">Run now</button>
        <button type="button" class="secondary" id="btnDry" data-mode="dry">Dry run</button>
        <button type="button" class="secondary" id="btnResign" data-mode="resign">Re-sign URLs only</button>
        <button type="button" class="secondary" id="btnKafka" data-mode="kafka" ${!st.kafkaEnabled ? 'disabled' : ''}>
          Queue via Kafka
        </button>
        <button type="button" class="secondary" id="btnClear">Clear log</button>
      </div>
      <p id="statusLine" class="muted"></p>
    </div>

    <div class="card">
      <strong>Live log</strong>
      <div id="log">${seedLog || '<span class="muted">Waiting — click Run now…</span>'}</div>
    </div>

    <div class="card">
      <strong>Last run summary</strong>
      <div id="lastRun">${last}</div>
    </div>
  </main>
  <script>
    const logEl = document.getElementById('log');
    const statusLine = document.getElementById('statusLine');
    const pillRun = document.getElementById('pillRun');
    const buttons = ['btnRun','btnDry','btnResign','btnKafka'].map(id => document.getElementById(id));

    function setRunning(on) {
      buttons.forEach(b => { if (b) b.disabled = on || (b.id === 'btnKafka' && ${!st.kafkaEnabled}); });
      if (pillRun) {
        pillRun.textContent = on ? 'running…' : 'idle';
        pillRun.className = 'pill ' + (on ? 'run' : 'ok');
      }
    }

    function appendLine(line) {
      if (!logEl) return;
      if (logEl.querySelector('.muted') && logEl.textContent.includes('Waiting')) logEl.innerHTML = '';
      const div = document.createElement('div');
      const level = line.level || 'info';
      const t = (line.t || '').slice(11, 19);
      div.innerHTML = '<span class="t">' + t + '</span><span class="' + level + '">' +
        escapeHtml(line.msg || '') + '</span>';
      logEl.appendChild(div);
      logEl.scrollTop = logEl.scrollHeight;
    }

    function escapeHtml(s) {
      return String(s)
        .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    }

    async function runStream(mode) {
      setRunning(true);
      statusLine.textContent = 'Starting…';
      statusLine.style.color = '';
      try {
        const body = new URLSearchParams();
        body.set('mode', mode === 'kafka' ? 'kafka' : 'inline');
        if (mode === 'dry') body.set('dryRun', '1');
        if (mode === 'resign') body.set('resignOnly', '1');

        const res = await fetch('/pipeline/run-stream', {
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'Accept': 'text/event-stream' },
          body: body.toString(),
          credentials: 'same-origin',
        });
        if (!res.ok || !res.body) {
          const t = await res.text();
          appendLine({ t: new Date().toISOString(), level: 'error', msg: 'HTTP ' + res.status + ' ' + t.slice(0, 200) });
          statusLine.textContent = 'Failed to start';
          statusLine.style.color = '#b91c1c';
          setRunning(false);
          return;
        }
        const reader = res.body.getReader();
        const decoder = new TextDecoder();
        let buf = '';
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          buf += decoder.decode(value, { stream: true });
          const parts = buf.split('\\n\\n');
          buf = parts.pop() || '';
          for (const chunk of parts) {
            const lines = chunk.split('\\n');
            for (const ln of lines) {
              if (!ln.startsWith('data: ')) continue;
              try {
                const data = JSON.parse(ln.slice(6));
                if (data.msg) appendLine(data);
                if (data.done) {
                  statusLine.textContent = data.ok
                    ? 'Done — pull-to-refresh the app feed'
                    : 'Finished with errors (see log)';
                  statusLine.style.color = data.ok ? '#166534' : '#b91c1c';
                  if (data.stats) {
                    document.getElementById('lastRun').innerHTML =
                      '<pre class="stats">' + escapeHtml(JSON.stringify({ at: new Date().toISOString(), stats: data.stats }, null, 2)) + '</pre>';
                  }
                }
              } catch (e) { /* ignore parse */ }
            }
          }
        }
      } catch (e) {
        appendLine({ t: new Date().toISOString(), level: 'error', msg: String(e && e.message || e) });
        statusLine.textContent = 'Connection error';
        statusLine.style.color = '#b91c1c';
      }
      setRunning(false);
    }

    document.getElementById('btnRun')?.addEventListener('click', () => runStream('run'));
    document.getElementById('btnDry')?.addEventListener('click', () => runStream('dry'));
    document.getElementById('btnResign')?.addEventListener('click', () => runStream('resign'));
    document.getElementById('btnKafka')?.addEventListener('click', () => runStream('kafka'));
    document.getElementById('btnClear')?.addEventListener('click', () => {
      if (logEl) logEl.innerHTML = '<span class="muted">Log cleared.</span>';
      fetch('/pipeline/clear-log', { method: 'POST', credentials: 'same-origin' });
    });
  </script>
</body>
</html>`;
}

function formatLogLineHtml(l: PipelineLogLine): string {
  const t = (l.t || '').slice(11, 19);
  const level = l.level || 'info';
  return `<div><span class="t">${escapeHtml(t)}</span><span class="${escapeHtml(level)}">${escapeHtml(l.msg)}</span></div>`;
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
  // Legacy form POST — redirect to page; use /pipeline/run-stream for live logs.
  if (!hasPipelineAccess(req)) {
    res.redirect(302, '/pipeline');
    return;
  }
  res.redirect(302, '/pipeline');
}

export function handlePipelineClearLog(req: Request, res: Response): void {
  if (!hasPipelineAccess(req)) {
    res.status(401).json({ ok: false });
    return;
  }
  clearPipelineLog();
  res.json({ ok: true });
}

/**
 * Live log stream (SSE). Body: mode=inline|kafka, dryRun=1, resignOnly=1
 */
export async function handlePipelineRunStream(req: Request, res: Response): Promise<void> {
  if (!hasPipelineAccess(req)) {
    res.status(401).type('text').send('unauthorized');
    return;
  }

  res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('X-Accel-Buffering', 'no');
  if (typeof (res as any).flushHeaders === 'function') {
    (res as any).flushHeaders();
  }

  const write = (obj: Record<string, unknown>) => {
    res.write(`data: ${JSON.stringify(obj)}\n\n`);
  };

  const unsub = subscribePipelineLog((line) => {
    write({ t: line.t, level: line.level, msg: line.msg });
  });

  const mode = String(req.body?.mode ?? req.query.mode ?? 'inline');
  const dryRun =
    String(req.body?.dryRun ?? req.query.dryRun ?? '') === '1' ||
    String(req.body?.dryRun ?? '') === 'true';
  const resignOnly =
    String(req.body?.resignOnly ?? req.query.resignOnly ?? '') === '1' ||
    String(req.body?.resignOnly ?? '') === 'true';

  write({ t: new Date().toISOString(), level: 'step', msg: 'Stream connected — starting pipeline…' });

  try {
    if (!r2Configured()) {
      write({
        t: new Date().toISOString(),
        level: 'error',
        msg: 'R2 not configured. Set R2_* env vars on Render and redeploy.',
      });
      write({ done: true, ok: false });
      unsub();
      res.end();
      return;
    }

    if (mode === 'kafka' && kafkaEnabled()) {
      write({
        t: new Date().toISOString(),
        level: 'step',
        msg: 'Enqueueing R2IngestRequested on Kafka…',
      });
      const result = await requestPipelineRun({
        dryRun,
        resignOnly,
        requestedBy: 'ops-page',
        forceInline: false,
        source: 'ops-page-kafka',
      });
      if (result.mode === 'kafka') {
        write({
          t: new Date().toISOString(),
          level: 'ok',
          msg: `Queued event ${result.eventId ?? '?'} — consumer will process it`,
        });
        write({ done: true, ok: true });
        unsub();
        res.end();
        return;
      }
      write({
        t: new Date().toISOString(),
        level: 'warn',
        msg: 'Kafka enqueue failed — falling back to inline run',
      });
    }

    const stats = await runPipelineNow({
      dryRun,
      resignOnly,
      maxOriginals: 40,
      maxShares: 80,
      maxResign: 200,
      maxMs: 120_000,
      source: 'ops-page-stream',
    });
    write({
      done: true,
      ok: stats.ok,
      stats,
    });
  } catch (err: any) {
    write({
      t: new Date().toISOString(),
      level: 'error',
      msg: err?.message ?? String(err),
    });
    write({ done: true, ok: false });
  } finally {
    unsub();
    res.end();
  }
}
