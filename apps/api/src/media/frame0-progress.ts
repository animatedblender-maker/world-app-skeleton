/**
 * Frame 0 backfill progress — ops page + JSON status.
 *
 *   https://api.matterya.com/frame0
 *   Local: npm run media:frame0-progress   → http://127.0.0.1:4091/frame0
 *
 * Same password as /pipeline /reports by default.
 */
import { createHmac, timingSafeEqual } from 'node:crypto';
import { watch } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import type { Request, Response } from 'express';
import { pool } from '../db.js';
import { r2Configured } from '../content-pipeline/r2.js';
import { supabaseAdminConfigured, supabaseUrl } from '../supabase-admin.js';

/** Stable path (not os.tmpdir() — macOS gives per-process folders). */
export const FRAME0_PROGRESS_DIR =
  process.env.FRAME0_PROGRESS_DIR?.trim() || '/tmp/matterya-frame0';
export const FRAME0_PROGRESS_FILE = join(FRAME0_PROGRESS_DIR, 'progress.json');
export const FRAME0_LOG_FILE = join(FRAME0_PROGRESS_DIR, 'backfill.log');

const COOKIE_NAME = 'matterya_pipeline_auth';
const COOKIE_TTL_SEC = 60 * 60 * 24 * 14;

export type Frame0RunProgress = {
  updatedAt: string;
  running: boolean;
  mode: 'inline' | 'kafka-enqueue' | 'idle';
  dryRun: boolean;
  force: boolean;
  limit: number;
  concurrency: number;
  candidates: number;
  ok: number;
  skipped: number;
  failed: number;
  processed: number;
  startedAt?: string;
  finishedAt?: string | null;
  lastPostId?: string | null;
  lastThumbPath?: string | null;
  lastError?: string | null;
  pid?: number | null;
  logPath?: string;
};

export type Frame0CatalogStats = {
  catalog: number;
  withFrame0: number;
  needing: number;
  pctDone: number;
};

const PASSWORD =
  process.env.CONTENT_PIPELINE_PASSWORD?.trim() ||
  process.env.REPORTS_PAGE_PASSWORD?.trim() ||
  '54isamr!';

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

export function hasFrame0PageAccess(req: Request): boolean {
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
  const want = PASSWORD;
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

async function ensureProgressDir(): Promise<void> {
  await mkdir(FRAME0_PROGRESS_DIR, { recursive: true }).catch(() => undefined);
}

/** CLI / in-process backfill writes here for the live page. */
export async function writeFrame0Progress(
  patch: Partial<Frame0RunProgress> & { running: boolean }
): Promise<void> {
  await ensureProgressDir();
  const prev = await readFrame0ProgressFile();
  const next: Frame0RunProgress = {
    updatedAt: new Date().toISOString(),
    running: patch.running,
    mode: patch.mode ?? prev?.mode ?? 'idle',
    dryRun: patch.dryRun ?? prev?.dryRun ?? false,
    force: patch.force ?? prev?.force ?? false,
    limit: patch.limit ?? prev?.limit ?? 0,
    concurrency: patch.concurrency ?? prev?.concurrency ?? 1,
    candidates: patch.candidates ?? prev?.candidates ?? 0,
    ok: patch.ok ?? prev?.ok ?? 0,
    skipped: patch.skipped ?? prev?.skipped ?? 0,
    failed: patch.failed ?? prev?.failed ?? 0,
    processed: patch.processed ?? prev?.processed ?? 0,
    startedAt: patch.startedAt ?? prev?.startedAt,
    finishedAt: patch.finishedAt !== undefined ? patch.finishedAt : prev?.finishedAt ?? null,
    lastPostId: patch.lastPostId !== undefined ? patch.lastPostId : prev?.lastPostId ?? null,
    lastThumbPath:
      patch.lastThumbPath !== undefined ? patch.lastThumbPath : prev?.lastThumbPath ?? null,
    lastError: patch.lastError !== undefined ? patch.lastError : prev?.lastError ?? null,
    pid: patch.pid !== undefined ? patch.pid : prev?.pid ?? process.pid,
    logPath: patch.logPath ?? prev?.logPath ?? FRAME0_LOG_FILE,
  };
  next.processed = next.ok + next.skipped + next.failed;
  await writeFile(FRAME0_PROGRESS_FILE, JSON.stringify(next, null, 2), 'utf8');
}

async function readFrame0ProgressFile(): Promise<Frame0RunProgress | null> {
  try {
    const raw = await readFile(FRAME0_PROGRESS_FILE, 'utf8');
    return JSON.parse(raw) as Frame0RunProgress;
  } catch {
    return null;
  }
}

/** Parse CLI log lines when progress.json is stale / missing. */
async function parseLogFallback(): Promise<Partial<Frame0RunProgress>> {
  const logCandidates = [
    FRAME0_LOG_FILE,
    join(FRAME0_PROGRESS_DIR, 'backfill-200.log'),
    join(homedir(), '.matterya-frame0', 'backfill.log'),
  ];
  let text = '';
  let logPath = FRAME0_LOG_FILE;
  for (const p of logCandidates) {
    try {
      text = await readFile(p, 'utf8');
      logPath = p;
      break;
    } catch {
      /* try next */
    }
  }
  if (!text) return {};
  const lines = text.split('\n');
  let ok = 0;
  let skipped = 0;
  let failed = 0;
  let candidates = 0;
  let lastPostId: string | null = null;
  let lastThumbPath: string | null = null;
  let lastError: string | null = null;
  let running = true;
  for (const line of lines) {
    const cand = line.match(/candidates=(\d+)/);
    if (cand) candidates = Number(cand[1]) || candidates;
    if (/\b(ready|refreshed)\b/.test(line)) {
      ok += 1;
      const m = line.match(/post=([0-9a-f-]{36})/i);
      if (m) lastPostId = m[1]!;
      const t = line.match(/thumb=(\S+)/);
      if (t) lastThumbPath = t[1]!;
    } else if (/\bwould\b/.test(line) && /post=/.test(line)) {
      skipped += 1;
    } else if (/FAILED/.test(line)) {
      failed += 1;
      lastError = line.trim().slice(0, 240);
    }
    if (/^\s*\{\s*$/.test(line) || line.includes('"ok":')) {
      // summary JSON starting — treat as finished once we see processedOrEnqueued
    }
    if (/"processedOrEnqueued"\s*:/.test(line) || /"failed"\s*:/.test(text.slice(-400))) {
      running = !/"ok"\s*:\s*true/.test(text.slice(-800)) ? running : false;
    }
  }
  // If summary block present at end, prefer it
  const summaryMatch = text.match(/\{\s*"ok"\s*:[\s\S]*\}\s*$/);
  if (summaryMatch) {
    try {
      const s = JSON.parse(summaryMatch[0]) as {
        processedOrEnqueued?: number;
        skippedExisting?: number;
        failed?: number;
        candidates?: number;
        ok?: boolean;
      };
      ok = s.processedOrEnqueued ?? ok;
      skipped = s.skippedExisting ?? skipped;
      failed = s.failed ?? failed;
      candidates = s.candidates ?? candidates;
      running = false;
    } catch {
      /* ignore */
    }
  }
  return {
    ok,
    skipped,
    failed,
    candidates,
    processed: ok + skipped + failed,
    lastPostId,
    lastThumbPath,
    lastError,
    running,
    logPath,
    mode: 'inline',
  };
}

export async function getFrame0CatalogStats(): Promise<Frame0CatalogStats> {
  try {
    const { rows } = await pool.query<{
      catalog: string;
      with_frame0: string;
      needing: string;
    }>(
      `
      select
        count(*) filter (
          where media_type = 'video'
            and media_path like 'r2:%'
            and media_path not like 'r2-share:%'
            and media_path not like 'r2-hubshare:%'
        )::text as catalog,
        count(*) filter (
          where media_type = 'video'
            and media_path like 'r2:%'
            and media_path not like 'r2-share:%'
            and media_path not like 'r2-hubshare:%'
            and thumb_path like '%/frame0_512.webp'
        )::text as with_frame0,
        count(*) filter (
          where media_type = 'video'
            and media_path like 'r2:%'
            and media_path not like 'r2-share:%'
            and media_path not like 'r2-hubshare:%'
            and (
              thumb_url is null or thumb_url = ''
              or thumb_path is null or thumb_path = ''
              or thumb_path not like '%/frame0_512.webp'
            )
        )::text as needing
      from public.posts
      `
    );
    const catalog = Number(rows[0]?.catalog || 0);
    const withFrame0 = Number(rows[0]?.with_frame0 || 0);
    const needing = Number(rows[0]?.needing || 0);
    const pctDone = catalog > 0 ? Math.round((withFrame0 / catalog) * 1000) / 10 : 0;
    return { catalog, withFrame0, needing, pctDone };
  } catch (err) {
    // REST fallback when pg is circuit-broken
    if (!supabaseAdminConfigured()) throw err;
    return getFrame0CatalogStatsRest();
  }
}

async function getFrame0CatalogStatsRest(): Promise<Frame0CatalogStats> {
  const base = supabaseUrl().replace(/\/$/, '');
  const key = (process.env.SUPABASE_SERVICE_ROLE_KEY ?? '').trim();
  const headers = {
    apikey: key,
    Authorization: `Bearer ${key}`,
    Prefer: 'count=exact',
  };
  async function count(filter: string): Promise<number> {
    const res = await fetch(`${base}/rest/v1/posts?select=id&${filter}&limit=1`, {
      headers: { ...headers, Prefer: 'count=exact' },
    });
    const cr = res.headers.get('content-range') || '';
    const m = cr.match(/\/(\d+)/);
    return m ? Number(m[1]) : 0;
  }
  const catalog = await count(
    'media_type=eq.video&media_path=like.r2:*&media_path=not.like.r2-share:*&media_path=not.like.r2-hubshare:*'
  );
  const withFrame0 = await count(
    'media_type=eq.video&media_path=like.r2:*&thumb_path=like.*/frame0_512.webp'
  );
  const needing = Math.max(0, catalog - withFrame0);
  const pctDone = catalog > 0 ? Math.round((withFrame0 / catalog) * 1000) / 10 : 0;
  return { catalog, withFrame0, needing, pctDone };
}

export async function getFrame0StatusPayload(): Promise<{
  catalog: Frame0CatalogStats;
  run: Frame0RunProgress;
  logTail: string;
  r2Configured: boolean;
  progressDir: string;
}> {
  const catalog = await getFrame0CatalogStats();
  let run = await readFrame0ProgressFile();
  if (!run) {
    const fromLog = await parseLogFallback();
    run = {
      updatedAt: new Date().toISOString(),
      running: fromLog.running ?? false,
      mode: (fromLog.mode as Frame0RunProgress['mode']) || 'idle',
      dryRun: false,
      force: false,
      limit: fromLog.candidates ?? 0,
      concurrency: 4,
      candidates: fromLog.candidates ?? 0,
      ok: fromLog.ok ?? 0,
      skipped: fromLog.skipped ?? 0,
      failed: fromLog.failed ?? 0,
      processed: fromLog.processed ?? 0,
      lastPostId: fromLog.lastPostId ?? null,
      lastThumbPath: fromLog.lastThumbPath ?? null,
      lastError: fromLog.lastError ?? null,
      logPath: fromLog.logPath ?? FRAME0_LOG_FILE,
      pid: null,
      finishedAt: fromLog.running === false ? new Date().toISOString() : null,
    };
  } else {
    // Merge log counts if file is older than log activity
    const fromLog = await parseLogFallback();
    if ((fromLog.ok ?? 0) > run.ok || (fromLog.failed ?? 0) > run.failed) {
      run = {
        ...run,
        ok: Math.max(run.ok, fromLog.ok ?? 0),
        skipped: Math.max(run.skipped, fromLog.skipped ?? 0),
        failed: Math.max(run.failed, fromLog.failed ?? 0),
        processed: 0,
        lastPostId: fromLog.lastPostId ?? run.lastPostId,
        lastThumbPath: fromLog.lastThumbPath ?? run.lastThumbPath,
        lastError: fromLog.lastError ?? run.lastError,
        running: fromLog.running ?? run.running,
      };
      run.processed = run.ok + run.skipped + run.failed;
    }
  }

  let logTail = '';
  const logPath = run.logPath || FRAME0_LOG_FILE;
  try {
    const raw = await readFile(logPath, 'utf8');
    const lines = raw.split('\n');
    logTail = lines.slice(-80).join('\n');
  } catch {
    try {
      const raw = await readFile(join(FRAME0_PROGRESS_DIR, 'backfill-200.log'), 'utf8');
      logTail = raw.split('\n').slice(-80).join('\n');
    } catch {
      logTail = '(no log yet — start a backfill)';
    }
  }

  return {
    catalog,
    run,
    logTail,
    r2Configured: r2Configured(),
    progressDir: FRAME0_PROGRESS_DIR,
  };
}

function loginHtml(err?: string): string {
  const error = err ? `<p class="err">${escapeHtml(err)}</p>` : '';
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Matterya · Frame 0</title>
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
  <form class="card" method="post" action="/frame0/login">
    <div class="mark">Matterya</div>
    <h1>Frame 0 progress</h1>
    <p class="sub">Live backfill of first-frame WebP posters on R2 + <code>posts.thumb_url</code>. Same password as Pipeline / Reports.</p>
    ${error}
    <label for="password">Password</label>
    <input id="password" name="password" type="password" required autofocus/>
    <button type="submit">Open progress</button>
  </form>
</body>
</html>`;
}

function dashboardHtml(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Matterya · Frame 0</title>
  <style>
    :root { --paper:#f8f6f2; --ink:#2c2825; --muted:#7a736c; --accent:#7b6347; --border:#ddd6cc; --surface:#fffcf8; --ok:#166534; --bad:#991b1b; }
    * { box-sizing: border-box; }
    body { margin:0; font-family: system-ui, -apple-system, sans-serif; background:var(--paper); color:var(--ink); }
    header { padding:20px 24px; border-bottom:1px solid var(--border); background:var(--surface);
      display:flex; flex-wrap:wrap; gap:12px; align-items:center; justify-content:space-between; }
    .mark { font-size:11px; font-weight:700; letter-spacing:0.2em; text-transform:uppercase; color:var(--accent); }
    h1 { margin:4px 0 0; font-size:1.35rem; font-weight:500; font-family: ui-serif, Georgia, serif; }
    main { max-width:960px; margin:0 auto; padding:24px 16px 48px; }
    .card { background:var(--surface); border:1px solid var(--border); border-radius:16px; padding:20px; margin-bottom:16px; }
    .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(140px,1fr)); gap:12px; }
    .stat { background:#f3efe8; border-radius:12px; padding:14px 16px; }
    .stat .n { font-size:1.75rem; font-weight:700; font-variant-numeric:tabular-nums; }
    .stat .l { font-size:12px; color:var(--muted); margin-top:4px; font-weight:600; letter-spacing:0.04em; text-transform:uppercase; }
    .bar { height:14px; background:#e8e2d8; border-radius:999px; overflow:hidden; margin-top:14px; }
    .bar > i { display:block; height:100%; background:linear-gradient(90deg,#7b6347,#a78b66); border-radius:999px; width:0%; transition:width .4s ease; }
    .pill { display:inline-block; padding:4px 10px; border-radius:999px; font-size:12px; font-weight:600;
      background:#e8e2d8; color:var(--ink); margin-right:6px; }
    .pill.ok { background:#dcfce7; color:var(--ok); }
    .pill.bad { background:#fee2e2; color:var(--bad); }
    .pill.run { background:#fef3c7; color:#92400e; }
    .muted { color:var(--muted); font-size:14px; line-height:1.5; }
    #log {
      background:#0c0a09; color:#e7e5e4; padding:14px 16px; border-radius:12px;
      min-height:240px; max-height:50vh; overflow:auto; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size:12px; line-height:1.55; white-space:pre-wrap; word-break:break-word;
    }
    a.out { color:var(--accent); font-size:13px; }
    .meta { font-size:13px; color:var(--muted); margin-top:10px; word-break:break-all; }
    .eta { font-size:15px; font-weight:650; margin-top:8px; }
  </style>
</head>
<body>
  <header>
    <div>
      <div class="mark">Matterya ops</div>
      <h1>Frame 0 progress</h1>
    </div>
    <div>
      <a class="out" href="/pipeline">Pipeline</a>
      ·
      <a class="out" href="/reports">Reports</a>
      ·
      <a class="out" href="/frame0/logout">Log out</a>
    </div>
  </header>
  <main>
    <div class="card">
      <span id="pillRun" class="pill">…</span>
      <span id="pillR2" class="pill">R2</span>
      <span id="pillPct" class="pill">0%</span>
      <div class="bar"><i id="barFill"></i></div>
      <p class="eta" id="etaLine">Loading…</p>
      <p class="muted" id="batchLine"></p>
    </div>

    <div class="card">
      <div class="grid">
        <div class="stat"><div class="n" id="nWith">—</div><div class="l">With Frame 0</div></div>
        <div class="stat"><div class="n" id="nNeed">—</div><div class="l">Still needing</div></div>
        <div class="stat"><div class="n" id="nCatalog">—</div><div class="l">Catalog videos</div></div>
        <div class="stat"><div class="n" id="nOk">—</div><div class="l">This run OK</div></div>
        <div class="stat"><div class="n" id="nFail">—</div><div class="l">This run fail</div></div>
        <div class="stat"><div class="n" id="nSkip">—</div><div class="l">Skipped</div></div>
      </div>
      <p class="meta" id="lastLine"></p>
    </div>

    <div class="card">
      <strong>Live log</strong>
      <div id="log">Loading…</div>
    </div>
  </main>
  <script>
    const $ = (id) => document.getElementById(id);
    function fmt(n) { return Number(n||0).toLocaleString(); }
    async function tick() {
      try {
        const res = await fetch('/frame0/status', { credentials: 'same-origin' });
        if (res.status === 401) { location.reload(); return; }
        const d = await res.json();
        const c = d.catalog || {};
        const r = d.run || {};
        $('nWith').textContent = fmt(c.withFrame0);
        $('nNeed').textContent = fmt(c.needing);
        $('nCatalog').textContent = fmt(c.catalog);
        $('nOk').textContent = fmt(r.ok);
        $('nFail').textContent = fmt(r.failed);
        $('nSkip').textContent = fmt(r.skipped);
        const pct = c.pctDone || 0;
        $('barFill').style.width = Math.min(100, pct) + '%';
        $('pillPct').textContent = pct + '% catalog';
        $('pillPct').className = 'pill ' + (pct >= 99 ? 'ok' : '');
        const runPill = $('pillRun');
        if (r.running) {
          runPill.textContent = 'batch running…';
          runPill.className = 'pill run';
        } else {
          runPill.textContent = 'batch idle';
          runPill.className = 'pill ok';
        }
        $('pillR2').textContent = d.r2Configured ? 'R2 ready' : 'R2 missing';
        $('pillR2').className = 'pill ' + (d.r2Configured ? 'ok' : 'bad');
        const processed = (r.ok||0)+(r.skipped||0)+(r.failed||0);
        const cand = r.candidates || 0;
        let eta = '';
        if (r.running && r.startedAt && processed > 0 && cand > processed) {
          const elapsed = (Date.now() - new Date(r.startedAt).getTime()) / 1000;
          const rate = processed / Math.max(1, elapsed);
          const left = (cand - processed) / Math.max(0.01, rate);
          eta = ' · ~' + Math.ceil(left/60) + ' min left this batch @ ' + rate.toFixed(2) + '/s';
        }
        $('etaLine').textContent = (c.withFrame0||0) + ' / ' + (c.catalog||0) + ' catalog have Frame 0 (' + pct + '%)' + eta;
        $('batchLine').textContent = r.running
          ? ('Batch ' + processed + ' / ' + cand + ' · concurrency ' + (r.concurrency||'?') + ' · limit ' + (r.limit||'?'))
          : (cand ? ('Last batch ' + processed + ' / ' + cand + (r.finishedAt ? ' · finished ' + r.finishedAt : '')) : 'No batch progress file yet — CLI log is parsed if present.');
        $('lastLine').textContent = [
          r.lastPostId ? ('last post ' + r.lastPostId) : '',
          r.lastThumbPath || '',
          r.lastError ? ('err: ' + r.lastError) : '',
          d.progressDir ? ('dir ' + d.progressDir) : '',
        ].filter(Boolean).join(' · ');
        $('log').textContent = d.logTail || '(empty)';
        if (r.running) {
          const el = $('log');
          el.scrollTop = el.scrollHeight;
        }
      } catch (e) {
        $('etaLine').textContent = 'Status fetch failed: ' + e;
      }
    }
    tick();
    setInterval(tick, 2000);
  </script>
</body>
</html>`;
}

export async function handleFrame0Get(req: Request, res: Response): Promise<void> {
  if (!hasFrame0PageAccess(req)) {
    res.status(200).type('html').send(loginHtml());
    return;
  }
  res.status(200).type('html').send(dashboardHtml());
}

export function handleFrame0Login(req: Request, res: Response): void {
  if (!passwordOk(req.body?.password)) {
    res.status(401).type('html').send(loginHtml('Wrong password'));
    return;
  }
  setAuthCookie(res);
  res.redirect(302, '/frame0');
}

export function handleFrame0Logout(_req: Request, res: Response): void {
  clearAuthCookie(res);
  res.redirect(302, '/frame0');
}

export async function handleFrame0Status(req: Request, res: Response): Promise<void> {
  if (!hasFrame0PageAccess(req)) {
    res.status(401).json({ error: 'unauthorized' });
    return;
  }
  try {
    const payload = await getFrame0StatusPayload();
    // Lazy import avoids circular deps with frame0-runner at module load.
    const { isFrame0BackfillRunning } = await import('./frame0-runner.js');
    res.json({ ...payload, runnerBusy: isFrame0BackfillRunning() });
  } catch (err: any) {
    res.status(500).json({ error: err?.message ?? 'status_failed' });
  }
}

/** Optional: watch progress file (for SSE later). */
export function watchFrame0Progress(cb: () => void): () => void {
  try {
    const w = watch(FRAME0_PROGRESS_DIR, () => cb());
    return () => w.close();
  } catch {
    return () => undefined;
  }
}
