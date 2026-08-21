/**
 * Unified Matterya Ops home — Pipeline + Frame 0 in one friendly UI.
 *
 *   https://api.matterya.com/pipeline
 *   https://api.matterya.com/frame0   → same shell, Frame 0 tab
 *   Local: http://127.0.0.1:4091/frame0
 */
import { createHmac, timingSafeEqual } from 'node:crypto';
import type { Request, Response } from 'express';
import { getPipelineStatus, requestPipelineRun, runPipelineNow } from '../content-pipeline/jobs.js';
import {
  clearPipelineLog,
  getPipelineLogBuffer,
  subscribePipelineLog,
  type PipelineLogLine,
} from '../content-pipeline/log.js';
import { r2Configured } from '../content-pipeline/r2.js';
import { kafkaEnabled } from '../kafka/config.js';
import {
  handleFrame0Status,
  hasFrame0PageAccess,
} from '../media/frame0-progress.js';
import {
  frame0OpsSnapshot,
  isFrame0BackfillRunning,
  startFrame0Backfill,
} from '../media/frame0-runner.js';

export const OPS_PAGE_PASSWORD =
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

export function hasOpsAccess(req: Request): boolean {
  return hasFrame0PageAccess(req) || hasPipelineAccessLegacy(req);
}

function hasPipelineAccessLegacy(req: Request): boolean {
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
  return Boolean(adminKey && key === adminKey);
}

function passwordOk(input: unknown): boolean {
  const got = String(input ?? '');
  const want = OPS_PAGE_PASSWORD;
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

function loginHtml(err?: string, nextPath = '/pipeline'): string {
  const error = err ? `<p class="err">${escapeHtml(err)}</p>` : '';
  const action = nextPath.startsWith('/frame0') ? '/frame0/login' : '/pipeline/login';
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Matterya · Ops</title>
  <style>
    :root { --paper:#f8f6f2; --ink:#2c2825; --muted:#7a736c; --accent:#7b6347; --border:#ddd6cc; --surface:#fffcf8; }
    * { box-sizing: border-box; }
    body { margin:0; min-height:100vh; display:grid; place-items:center;
      font-family: system-ui, -apple-system, sans-serif;
      background: radial-gradient(1200px 600px at 20% 0%, #efe8dc 0%, var(--paper) 55%); color:var(--ink); }
    .card { width:min(440px,92vw); background:var(--surface); border:1px solid var(--border);
      border-radius:18px; padding:28px 26px; box-shadow:0 18px 40px rgba(44,40,37,0.08); }
    .mark { font-size:11px; font-weight:700; letter-spacing:0.22em; text-transform:uppercase; color:var(--accent); }
    h1 { margin:10px 0 6px; font-size:1.55rem; font-weight:500; font-family: ui-serif, Georgia, serif; }
    .sub { color:var(--muted); font-size:0.95rem; line-height:1.45; margin:0 0 20px; }
    label { display:block; font-size:12px; font-weight:600; color:var(--muted); margin-bottom:6px; }
    input { width:100%; padding:12px 14px; border-radius:10px; border:1px solid var(--border); font-size:15px; }
    button { margin-top:16px; width:100%; border:0; border-radius:999px; padding:12px 16px;
      background:var(--accent); color:#fff; font-weight:650; cursor:pointer; }
    .err { color:#b91c1c; font-size:13px; }
  </style>
</head>
<body>
  <form class="card" method="post" action="${action}">
    <div class="mark">Matterya</div>
    <h1>Ops</h1>
    <p class="sub">Content pipeline (R2 → posts) and Frame 0 posters in one place. Same password as Reports.</p>
    ${error}
    <label for="password">Password</label>
    <input id="password" name="password" type="password" required autofocus/>
    <input type="hidden" name="next" value="${escapeHtml(nextPath)}"/>
    <button type="submit">Open Ops</button>
  </form>
</body>
</html>`;
}

function opsHtml(activeTab: 'overview' | 'pipeline' | 'frame0'): string {
  const st = getPipelineStatus();
  const buffered = getPipelineLogBuffer();
  const seedLog = buffered.map((l) => formatLogLineHtml(l)).join('');
  const last = st.lastRun
    ? `<pre class="stats">${escapeHtml(JSON.stringify(st.lastRun, null, 2))}</pre>`
    : `<p class="muted">No pipeline run in this process yet.</p>`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Matterya · Ops</title>
  <style>
    :root {
      --paper:#f8f6f2; --ink:#2c2825; --muted:#7a736c; --accent:#7b6347;
      --border:#ddd6cc; --surface:#fffcf8; --ok:#166534; --bad:#991b1b;
    }
    * { box-sizing: border-box; }
    body { margin:0; font-family: system-ui, -apple-system, sans-serif; background:var(--paper); color:var(--ink); }
    header { padding:18px 22px; border-bottom:1px solid var(--border); background:var(--surface);
      display:flex; flex-wrap:wrap; gap:12px; align-items:center; justify-content:space-between; }
    .mark { font-size:11px; font-weight:700; letter-spacing:0.2em; text-transform:uppercase; color:var(--accent); }
    h1 { margin:4px 0 0; font-size:1.4rem; font-weight:500; font-family: ui-serif, Georgia, serif; }
    .tabs { display:flex; gap:6px; flex-wrap:wrap; margin:0; padding:12px 16px 0; max-width:1100px; margin-inline:auto; }
    .tab {
      border:1px solid var(--border); background:#efe8dc; color:var(--ink);
      border-radius:999px; padding:8px 14px; font-size:13px; font-weight:650; cursor:pointer;
      text-decoration:none; display:inline-block;
    }
    .tab.active { background:var(--accent); color:#fff; border-color:var(--accent); }
    main { max-width:1100px; margin:0 auto; padding:16px 16px 56px; }
    .panel { display:none; }
    .panel.active { display:block; }
    .card { background:var(--surface); border:1px solid var(--border); border-radius:16px; padding:18px 20px; margin-bottom:14px; }
    .row { display:flex; flex-wrap:wrap; gap:10px; margin-top:12px; align-items:center; }
    .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(140px,1fr)); gap:12px; }
    .stat { background:#f3efe8; border-radius:12px; padding:14px 16px; }
    .stat .n { font-size:1.7rem; font-weight:700; font-variant-numeric:tabular-nums; }
    .stat .l { font-size:11px; color:var(--muted); margin-top:4px; font-weight:700; letter-spacing:0.04em; text-transform:uppercase; }
    .bar { height:14px; background:#e8e2d8; border-radius:999px; overflow:hidden; margin-top:12px; }
    .bar > i { display:block; height:100%; width:0%; background:linear-gradient(90deg,#7b6347,#a78b66); border-radius:999px; transition:width .35s ease; }
    button, .btn {
      border:0; border-radius:999px; padding:11px 16px; font-weight:650; font-size:13px; cursor:pointer;
      background:var(--accent); color:#fff; text-decoration:none; display:inline-block;
    }
    button.secondary, .btn.secondary { background:#e8e2d8; color:var(--ink); }
    button:disabled { opacity:0.55; cursor:wait; }
    .pill { display:inline-block; padding:4px 10px; border-radius:999px; font-size:12px; font-weight:600;
      background:#e8e2d8; color:var(--ink); margin-right:6px; margin-bottom:4px; }
    .pill.ok { background:#dcfce7; color:var(--ok); }
    .pill.bad { background:#fee2e2; color:var(--bad); }
    .pill.run { background:#fef3c7; color:#92400e; }
    .muted { color:var(--muted); font-size:14px; line-height:1.5; }
    .eta { font-size:15px; font-weight:650; margin-top:8px; }
    .meta { font-size:12px; color:var(--muted); margin-top:8px; word-break:break-all; }
    label.field { font-size:12px; font-weight:650; color:var(--muted); display:flex; flex-direction:column; gap:4px; }
    input[type=number], select {
      border:1px solid var(--border); border-radius:10px; padding:8px 10px; font-size:14px; min-width:88px; background:#fff;
    }
    pre.stats, #pipeLog, #f0Log {
      background:#0c0a09; color:#e7e5e4; padding:14px 16px; border-radius:12px;
      min-height:200px; max-height:48vh; overflow:auto; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size:12px; line-height:1.55; white-space:pre-wrap; word-break:break-word;
    }
    #pipeLog .t { color:#78716c; margin-right:8px; }
    #pipeLog .ok { color:#4ade80; } #pipeLog .warn { color:#fbbf24; }
    #pipeLog .error { color:#f87171; } #pipeLog .info { color:#d6d3d1; }
    a.out { color:var(--accent); font-size:13px; }
    .help { margin:0; padding-left:18px; color:var(--muted); font-size:13px; line-height:1.55; }
    .help li { margin:4px 0; }
    .two { display:grid; grid-template-columns:1.2fr 1fr; gap:14px; }
    @media (max-width:860px) { .two { grid-template-columns:1fr; } }
  </style>
</head>
<body>
  <header>
    <div>
      <div class="mark">Matterya ops</div>
      <h1>Content &amp; posters</h1>
    </div>
    <div>
      <a class="out" href="/reports">Reports</a>
      ·
      <a class="out" href="/pipeline/logout">Log out</a>
    </div>
  </header>

  <nav class="tabs" role="tablist">
    <button type="button" class="tab ${activeTab === 'overview' ? 'active' : ''}" data-tab="overview">Overview</button>
    <button type="button" class="tab ${activeTab === 'pipeline' ? 'active' : ''}" data-tab="pipeline">Pipeline</button>
    <button type="button" class="tab ${activeTab === 'frame0' ? 'active' : ''}" data-tab="frame0">Frame 0</button>
  </nav>

  <main>
    <!-- OVERVIEW -->
    <section class="panel ${activeTab === 'overview' ? 'active' : ''}" id="panel-overview">
      <div class="card">
        <span class="pill ${st.r2Configured ? 'ok' : 'bad'}" id="ovR2">R2 ${st.r2Configured ? 'ready' : 'missing'}</span>
        <span class="pill ${st.kafkaEnabled ? 'ok' : ''}" id="ovKafka">Kafka ${st.kafkaEnabled ? 'on' : 'off'}</span>
        <span class="pill ${st.running ? 'run' : 'ok'}" id="ovPipe">Pipeline ${st.running ? 'running…' : 'idle'}</span>
        <span class="pill" id="ovF0">Frame 0 …</span>
        <p class="muted" style="margin-top:12px">
          <strong>Pipeline</strong> discovers R2 packs → owned posts + feed/hub shares.<br/>
          <strong>Frame 0</strong> extracts the first video frame → WebP posters on R2 + <code>thumb_url</code> (no black cold-start).
        </p>
      </div>
      <div class="two">
        <div class="card">
          <strong>Frame 0 catalog</strong>
          <div class="bar"><i id="ovBar"></i></div>
          <p class="eta" id="ovEta">Loading…</p>
          <div class="grid" style="margin-top:12px">
            <div class="stat"><div class="n" id="ovWith">—</div><div class="l">With Frame 0</div></div>
            <div class="stat"><div class="n" id="ovNeed">—</div><div class="l">Still needing</div></div>
            <div class="stat"><div class="n" id="ovCatalog">—</div><div class="l">Catalog videos</div></div>
          </div>
          <div class="row">
            <button type="button" id="ovGoF0">Open Frame 0</button>
            <button type="button" class="secondary" id="ovQuick50">Backfill 50 Sparks</button>
          </div>
        </div>
        <div class="card">
          <strong>What to do</strong>
          <ul class="help">
            <li>New videos on R2? → <em>Pipeline → Run now</em></li>
            <li>Black screens / missing posters? → <em>Frame 0 → Start backfill</em></li>
            <li>Expired play links? → <em>Pipeline → Re-sign URLs</em></li>
            <li>Progress page auto-refreshes every 2s while a batch runs</li>
          </ul>
          <p class="meta" id="ovMeta"></p>
        </div>
      </div>
    </section>

    <!-- PIPELINE -->
    <section class="panel ${activeTab === 'pipeline' ? 'active' : ''}" id="panel-pipeline">
      <div class="card">
        <span class="pill ${st.r2Configured ? 'ok' : 'bad'}">R2 ${st.r2Configured ? 'ready' : 'missing env'}</span>
        <span class="pill ${st.kafkaEnabled ? 'ok' : ''}">Kafka ${st.kafkaEnabled ? 'on' : 'off (inline)'}</span>
        <span class="pill ${st.running ? 'run' : 'ok'}" id="pipePill">Pipeline ${st.running ? 'running…' : 'idle'}</span>
        <p class="muted" style="margin-top:10px">Pulls Sparks (TikTok + ShortForm) and LongForm (Hubs) from R2 into Supabase as owned posts + shares.</p>
      </div>
      <div class="card">
        <strong>Run pipeline</strong>
        <div class="row">
          <button type="button" id="btnRun">Run now</button>
          <button type="button" class="secondary" id="btnDry">Dry run</button>
          <button type="button" class="secondary" id="btnResign">Re-sign URLs only</button>
          <button type="button" class="secondary" id="btnKafka" ${!st.kafkaEnabled ? 'disabled' : ''}>Queue via Kafka</button>
          <button type="button" class="secondary" id="btnClear">Clear log</button>
        </div>
        <p id="pipeStatus" class="muted" style="margin-top:10px;font-weight:650;min-height:1.2em"></p>
      </div>
      <div class="card">
        <strong>Live log</strong>
        <div id="pipeLog">${seedLog || '<span class="muted">Waiting — click Run now…</span>'}</div>
      </div>
      <div class="card">
        <strong>Last run summary</strong>
        <div id="lastRun">${last}</div>
      </div>
    </section>

    <!-- FRAME 0 -->
    <section class="panel ${activeTab === 'frame0' ? 'active' : ''}" id="panel-frame0">
      <div class="card">
        <span class="pill" id="f0PillRun">…</span>
        <span class="pill" id="f0PillR2">R2</span>
        <span class="pill" id="f0PillPct">0%</span>
        <div class="bar"><i id="f0Bar"></i></div>
        <p class="eta" id="f0Eta">Loading…</p>
        <p class="muted" id="f0Batch"></p>
      </div>
      <div class="card">
        <div class="grid">
          <div class="stat"><div class="n" id="f0With">—</div><div class="l">With Frame 0</div></div>
          <div class="stat"><div class="n" id="f0Need">—</div><div class="l">Still needing</div></div>
          <div class="stat"><div class="n" id="f0Catalog">—</div><div class="l">Catalog</div></div>
          <div class="stat"><div class="n" id="f0Ok">—</div><div class="l">This run OK</div></div>
          <div class="stat"><div class="n" id="f0Fail">—</div><div class="l">Failed</div></div>
          <div class="stat"><div class="n" id="f0Skip">—</div><div class="l">Skipped</div></div>
        </div>
        <p class="meta" id="f0Last"></p>
      </div>
      <div class="card">
        <strong>Start backfill</strong>
        <p class="muted">Sparks (ShortForm) are prioritized. Safe to re-run — existing WebPs are skipped unless Force.</p>
        <div class="row">
          <label class="field">Limit
            <select id="f0Limit">
              <option value="20">20</option>
              <option value="50" selected>50</option>
              <option value="100">100</option>
              <option value="200">200</option>
            </select>
          </label>
          <label class="field">Concurrency
            <select id="f0Conc">
              <option value="2">2</option>
              <option value="4" selected>4</option>
              <option value="6">6</option>
            </select>
          </label>
          <label class="field" style="flex-direction:row;align-items:center;gap:8px;margin-top:18px">
            <input type="checkbox" id="f0Force"/> Force re-extract
          </label>
          <button type="button" id="f0Start" style="margin-top:14px">Start backfill</button>
          <button type="button" class="secondary" id="f0Dry" style="margin-top:14px">Dry run</button>
        </div>
        <p id="f0Action" class="muted" style="margin-top:10px;font-weight:650;min-height:1.2em"></p>
      </div>
      <div class="card">
        <strong>Live log</strong>
        <div id="f0Log">Loading…</div>
      </div>
    </section>
  </main>

  <script>
    const $ = (id) => document.getElementById(id);
    const fmt = (n) => Number(n || 0).toLocaleString();
    let activeTab = ${JSON.stringify(activeTab)};

    function showTab(name) {
      activeTab = name;
      document.querySelectorAll('.tab').forEach((t) => {
        t.classList.toggle('active', t.getAttribute('data-tab') === name);
      });
      document.querySelectorAll('.panel').forEach((p) => {
        p.classList.toggle('active', p.id === 'panel-' + name);
      });
      const url = new URL(location.href);
      if (name === 'overview') url.searchParams.delete('tab');
      else url.searchParams.set('tab', name);
      history.replaceState(null, '', url.pathname + url.search);
    }
    document.querySelectorAll('.tab').forEach((t) => {
      t.addEventListener('click', () => showTab(t.getAttribute('data-tab')));
    });
    $('ovGoF0')?.addEventListener('click', () => showTab('frame0'));

    // ── Frame 0 status poll ──────────────────────────────────────────
    async function tickFrame0() {
      try {
        const res = await fetch('/frame0/status', { credentials: 'same-origin' });
        if (res.status === 401) { location.reload(); return; }
        const d = await res.json();
        const c = d.catalog || {};
        const r = d.run || {};
        const pct = c.pctDone || 0;
        const busy = !!d.runnerBusy || !!r.running;

        for (const [id, val] of Object.entries({
          ovWith: c.withFrame0, ovNeed: c.needing, ovCatalog: c.catalog,
          f0With: c.withFrame0, f0Need: c.needing, f0Catalog: c.catalog,
          f0Ok: r.ok, f0Fail: r.failed, f0Skip: r.skipped,
        })) {
          const el = $(id); if (el) el.textContent = fmt(val);
        }
        $('ovBar').style.width = Math.min(100, pct) + '%';
        $('f0Bar').style.width = Math.min(100, pct) + '%';
        $('ovEta').textContent = fmt(c.withFrame0) + ' / ' + fmt(c.catalog) + ' have Frame 0 (' + pct + '%)';
        $('f0Eta').textContent = $('ovEta').textContent;
        $('f0PillPct').textContent = pct + '% catalog';
        $('f0PillPct').className = 'pill ' + (pct >= 99 ? 'ok' : '');
        $('f0PillR2').textContent = d.r2Configured ? 'R2 ready' : 'R2 missing';
        $('f0PillR2').className = 'pill ' + (d.r2Configured ? 'ok' : 'bad');
        $('ovR2').textContent = d.r2Configured ? 'R2 ready' : 'R2 missing';
        $('ovR2').className = 'pill ' + (d.r2Configured ? 'ok' : 'bad');

        const runLabel = busy ? 'batch running…' : 'batch idle';
        $('f0PillRun').textContent = runLabel;
        $('f0PillRun').className = 'pill ' + (busy ? 'run' : 'ok');
        $('ovF0').textContent = 'Frame 0 ' + (busy ? 'running…' : pct + '%');
        $('ovF0').className = 'pill ' + (busy ? 'run' : pct >= 99 ? 'ok' : '');

        const processed = (r.ok||0)+(r.skipped||0)+(r.failed||0);
        const cand = r.candidates || 0;
        let eta = '';
        if (busy && r.startedAt && processed > 0 && cand > processed) {
          const elapsed = (Date.now() - new Date(r.startedAt).getTime()) / 1000;
          const rate = processed / Math.max(1, elapsed);
          const left = (cand - processed) / Math.max(0.01, rate);
          eta = ' · ~' + Math.ceil(left/60) + ' min left @ ' + rate.toFixed(2) + '/s';
        }
        if (eta) $('f0Eta').textContent += eta;
        $('f0Batch').textContent = busy
          ? ('Batch ' + processed + ' / ' + cand + ' · concurrency ' + (r.concurrency||'?'))
          : (cand ? ('Last batch ' + processed + ' / ' + cand) : 'No batch yet — start one below.');
        $('f0Last').textContent = [r.lastPostId, r.lastThumbPath, r.lastError ? ('err: '+r.lastError) : ''].filter(Boolean).join(' · ');
        $('ovMeta').textContent = r.lastThumbPath || '';
        $('f0Log').textContent = d.logTail || '(empty)';
        if (busy) $('f0Log').scrollTop = $('f0Log').scrollHeight;

        $('f0Start').disabled = busy;
        $('f0Dry').disabled = busy;
        $('ovQuick50').disabled = busy;
      } catch (e) {
        $('f0Eta').textContent = 'Status error: ' + e;
      }
    }
    tickFrame0();
    setInterval(tickFrame0, 2000);

    async function startFrame0(dry) {
      const limit = Number($('f0Limit').value || 50);
      const concurrency = Number($('f0Conc').value || 4);
      const force = $('f0Force').checked;
      $('f0Action').textContent = dry ? 'Starting dry run…' : 'Starting backfill…';
      $('f0Action').style.color = '';
      try {
        const res = await fetch('/frame0/run', {
          method: 'POST',
          credentials: 'same-origin',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ limit, concurrency, force, dryRun: !!dry }),
        });
        const d = await res.json();
        if (!res.ok || !d.started) {
          $('f0Action').textContent = 'Could not start: ' + (d.reason || d.error || res.status);
          $('f0Action').style.color = '#b91c1c';
          return;
        }
        $('f0Action').textContent = dry ? 'Dry run started' : 'Backfill started — watch the log';
        $('f0Action').style.color = '#166534';
        showTab('frame0');
        tickFrame0();
      } catch (e) {
        $('f0Action').textContent = String(e);
        $('f0Action').style.color = '#b91c1c';
      }
    }
    $('f0Start')?.addEventListener('click', () => startFrame0(false));
    $('f0Dry')?.addEventListener('click', () => startFrame0(true));
    $('ovQuick50')?.addEventListener('click', () => {
      $('f0Limit').value = '50';
      startFrame0(false);
    });

    // ── Pipeline stream (existing behavior) ─────────────────────────
    const pipeButtons = ['btnRun','btnDry','btnResign','btnKafka'].map((id) => $(id));
    function setPipeRunning(on) {
      pipeButtons.forEach((b) => {
        if (!b) return;
        b.disabled = on || (b.id === 'btnKafka' && ${!st.kafkaEnabled});
      });
      if ($('pipePill')) {
        $('pipePill').textContent = on ? 'Pipeline running…' : 'Pipeline idle';
        $('pipePill').className = 'pill ' + (on ? 'run' : 'ok');
      }
      if ($('ovPipe')) {
        $('ovPipe').textContent = on ? 'Pipeline running…' : 'Pipeline idle';
        $('ovPipe').className = 'pill ' + (on ? 'run' : 'ok');
      }
    }
    function escapeHtml(s) {
      return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    }
    function appendPipe(line) {
      const logEl = $('pipeLog');
      if (!logEl) return;
      if (logEl.querySelector('.muted') && logEl.textContent.includes('Waiting')) logEl.innerHTML = '';
      const div = document.createElement('div');
      const level = line.level || 'info';
      const t = (line.t || '').slice(11, 19);
      div.innerHTML = '<span class="t">' + t + '</span><span class="' + level + '">' + escapeHtml(line.msg || '') + '</span>';
      logEl.appendChild(div);
      logEl.scrollTop = logEl.scrollHeight;
    }
    async function runStream(mode) {
      setPipeRunning(true);
      $('pipeStatus').textContent = 'Starting…';
      $('pipeStatus').style.color = '';
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
          appendPipe({ t: new Date().toISOString(), level: 'error', msg: 'HTTP ' + res.status + ' ' + t.slice(0, 200) });
          $('pipeStatus').textContent = 'Failed to start';
          $('pipeStatus').style.color = '#b91c1c';
          setPipeRunning(false);
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
            for (const ln of chunk.split('\\n')) {
              if (!ln.startsWith('data: ')) continue;
              try {
                const data = JSON.parse(ln.slice(6));
                if (data.msg) appendPipe(data);
                if (data.done) {
                  $('pipeStatus').textContent = data.ok ? 'Done — pull-to-refresh the app' : 'Finished with errors';
                  $('pipeStatus').style.color = data.ok ? '#166534' : '#b91c1c';
                  if (data.stats) {
                    $('lastRun').innerHTML = '<pre class="stats">' + escapeHtml(JSON.stringify({ at: new Date().toISOString(), stats: data.stats }, null, 2)) + '</pre>';
                  }
                }
              } catch (_) {}
            }
          }
        }
      } catch (e) {
        appendPipe({ t: new Date().toISOString(), level: 'error', msg: String(e && e.message || e) });
        $('pipeStatus').textContent = 'Connection error';
        $('pipeStatus').style.color = '#b91c1c';
      }
      setPipeRunning(false);
    }
    $('btnRun')?.addEventListener('click', () => runStream('run'));
    $('btnDry')?.addEventListener('click', () => runStream('dry'));
    $('btnResign')?.addEventListener('click', () => runStream('resign'));
    $('btnKafka')?.addEventListener('click', () => runStream('kafka'));
    $('btnClear')?.addEventListener('click', () => {
      if ($('pipeLog')) $('pipeLog').innerHTML = '<span class="muted">Log cleared.</span>';
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

function tabFromReq(req: Request): 'overview' | 'pipeline' | 'frame0' {
  const q = String(req.query.tab || '').toLowerCase();
  if (q === 'pipeline' || q === 'frame0' || q === 'overview') return q;
  if (req.path.startsWith('/frame0')) return 'frame0';
  return 'overview';
}

export async function handleOpsGet(req: Request, res: Response): Promise<void> {
  if (!hasOpsAccess(req)) {
    res.status(200).type('html').send(loginHtml(undefined, req.path.startsWith('/frame0') ? '/frame0' : '/pipeline'));
    return;
  }
  res.status(200).type('html').send(opsHtml(tabFromReq(req)));
}

export function handleOpsLogin(req: Request, res: Response): void {
  if (!passwordOk(req.body?.password)) {
    const next = String(req.body?.next || '/pipeline');
    res.status(401).type('html').send(loginHtml('Wrong password', next));
    return;
  }
  setAuthCookie(res);
  const next = String(req.body?.next || '/pipeline');
  res.redirect(302, next.startsWith('/') ? next : '/pipeline');
}

export function handleOpsLogout(_req: Request, res: Response): void {
  clearAuthCookie(res);
  res.redirect(302, '/pipeline');
}

/** Prefer unified ops shell for legacy pipeline handlers. */
export async function handlePipelineGet(req: Request, res: Response): Promise<void> {
  return handleOpsGet(req, res);
}
export const handlePipelineLogin = handleOpsLogin;
export const handlePipelineLogout = handleOpsLogout;

export async function handleFrame0Get(req: Request, res: Response): Promise<void> {
  // Same shell, Frame 0 tab selected.
  if (!hasOpsAccess(req)) {
    res.status(200).type('html').send(loginHtml(undefined, '/frame0'));
    return;
  }
  res.status(200).type('html').send(opsHtml('frame0'));
}
export const handleFrame0Login = handleOpsLogin;
export function handleFrame0Logout(_req: Request, res: Response): void {
  clearAuthCookie(res);
  res.redirect(302, '/frame0');
}

export async function handleFrame0Run(req: Request, res: Response): Promise<void> {
  if (!hasOpsAccess(req)) {
    res.status(401).json({ started: false, error: 'unauthorized' });
    return;
  }
  const body = (req.body || {}) as Record<string, unknown>;
  const result = await startFrame0Backfill({
    limit: Number(body.limit ?? req.query.limit) || 50,
    concurrency: Number(body.concurrency ?? req.query.concurrency) || 4,
    force: body.force === true || body.force === '1' || String(req.query.force) === '1',
    dryRun: body.dryRun === true || body.dryRun === '1' || String(req.query.dryRun) === '1',
    requestedBy: 'ops-ui',
  });
  res.status(result.started ? 202 : 409).json(result);
}

// Re-export status handler + pipeline stream helpers used by main.ts
export { handleFrame0Status };

export async function handlePipelineRun(req: Request, res: Response): Promise<void> {
  if (!hasOpsAccess(req)) {
    res.redirect(302, '/pipeline');
    return;
  }
  res.redirect(302, '/pipeline?tab=pipeline');
}

export function handlePipelineClearLog(req: Request, res: Response): void {
  if (!hasOpsAccess(req)) {
    res.status(401).json({ ok: false });
    return;
  }
  clearPipelineLog();
  res.json({ ok: true });
}

export async function handlePipelineRunStream(req: Request, res: Response): Promise<void> {
  if (!hasOpsAccess(req)) {
    res.status(401).end();
    return;
  }
  res.setHeader('Content-Type', 'text/event-stream; charset=utf-8');
  res.setHeader('Cache-Control', 'no-cache, no-transform');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders?.();

  const send = (obj: Record<string, unknown>) => {
    res.write(`data: ${JSON.stringify(obj)}\n\n`);
  };

  const unsub = subscribePipelineLog((line) => {
    send({ t: line.t, level: line.level, msg: line.msg });
  });

  const mode = String(req.body?.mode || req.query.mode || 'inline');
  const dryRun =
    String(req.body?.dryRun ?? req.query.dryRun ?? '') === '1' ||
    String(req.body?.dryRun ?? req.query.dryRun ?? '') === 'true';
  const resignOnly =
    String(req.body?.resignOnly ?? req.query.resignOnly ?? '') === '1' ||
    String(req.body?.resignOnly ?? req.query.resignOnly ?? '') === 'true';

  try {
    send({ t: new Date().toISOString(), level: 'info', msg: `Pipeline starting (mode=${mode})…` });
    if (!r2Configured()) {
      send({
        t: new Date().toISOString(),
        level: 'error',
        msg: 'R2 not configured. Set R2_* env vars and redeploy.',
      });
      send({ done: true, ok: false });
      return;
    }
    if (mode === 'kafka' && kafkaEnabled()) {
      send({
        t: new Date().toISOString(),
        level: 'step',
        msg: 'Enqueueing R2IngestRequested on Kafka…',
      });
      const result = await requestPipelineRun({
        dryRun,
        resignOnly,
        requestedBy: 'ops-ui',
        forceInline: false,
        source: 'ops-ui-kafka',
      });
      if (result.mode === 'kafka') {
        send({
          t: new Date().toISOString(),
          level: 'ok',
          msg: `Queued event ${result.eventId ?? '?'} — consumer will process it`,
        });
        send({ done: true, ok: true, stats: result });
        return;
      }
      send({
        t: new Date().toISOString(),
        level: 'warn',
        msg: 'Kafka enqueue failed — falling back to inline run',
      });
    }
    const stats = await runPipelineNow({
      dryRun,
      resignOnly,
      maxResign: 2000,
      maxMs: 0,
      requestedBy: 'ops-ui',
      source: 'ops-ui-stream',
      forceInline: true,
    });
    send({ done: true, ok: !!stats.ok, stats });
  } catch (err: any) {
    send({
      t: new Date().toISOString(),
      level: 'error',
      msg: err?.message ?? String(err),
    });
    send({ done: true, ok: false });
  } finally {
    unsub();
    res.end();
  }
}

// Keep pipeline-page password export for reports cross-link compatibility.
export { OPS_PAGE_PASSWORD as PIPELINE_PAGE_PASSWORD };
export { hasOpsAccess as hasPipelineAccess };
export { r2Configured, kafkaEnabled, getPipelineStatus, isFrame0BackfillRunning, frame0OpsSnapshot };
