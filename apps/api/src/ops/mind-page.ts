/**
 * MIND admin console — illustrated handbook + live feedback.
 *   https://api.matterya.com/mind
 */
import type { Request, Response } from 'express';
import { hasOpsAccess, handleOpsLogin } from './ops-page.js';
import { getMindStatus, readMindDoc } from './mind-status.js';

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/** Minimal markdown → HTML for admin docs (headings, lists, code, tables-ish). */
export function mdToSafeHtml(md: string): string {
  const lines = md.replace(/\r\n/g, '\n').split('\n');
  const out: string[] = [];
  let inCode = false;
  let inUl = false;
  const flushUl = () => {
    if (inUl) {
      out.push('</ul>');
      inUl = false;
    }
  };
  for (const raw of lines) {
    if (raw.startsWith('```')) {
      flushUl();
      if (inCode) {
        out.push('</code></pre>');
        inCode = false;
      } else {
        out.push('<pre class="mdcode"><code>');
        inCode = true;
      }
      continue;
    }
    if (inCode) {
      out.push(escapeHtml(raw) + '\n');
      continue;
    }
    if (/^\s*\|/.test(raw) && raw.includes('|')) {
      flushUl();
      // Keep tables as preformatted for reliability
      out.push(`<pre class="mdtable">${escapeHtml(raw)}</pre>`);
      continue;
    }
    const h = raw.match(/^(#{1,3})\s+(.*)$/);
    if (h) {
      flushUl();
      const level = h[1]!.length;
      out.push(`<h${level}>${escapeHtml(h[2]!)}</h${level}>`);
      continue;
    }
    if (/^\s*[-*]\s+/.test(raw)) {
      if (!inUl) {
        out.push('<ul>');
        inUl = true;
      }
      out.push(`<li>${escapeHtml(raw.replace(/^\s*[-*]\s+/, ''))}</li>`);
      continue;
    }
    flushUl();
    if (!raw.trim()) {
      out.push('<br/>');
      continue;
    }
    let line = escapeHtml(raw);
    line = line.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    line = line.replace(/`([^`]+)`/g, '<code>$1</code>');
    out.push(`<p>${line}</p>`);
  }
  flushUl();
  if (inCode) out.push('</code></pre>');
  return out.join('\n');
}

function loginHtml(err?: string): string {
  const error = err ? `<p class="err">${escapeHtml(err)}</p>` : '';
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Matterya · MIND</title>
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
  <form class="card" method="post" action="/mind/login">
    <div class="mark">Matterya</div>
    <h1>MIND</h1>
    <p class="sub">Intelligence &amp; Discovery admin console. Same password as Pipeline / Reports.</p>
    ${error}
    <label for="password">Password</label>
    <input id="password" name="password" type="password" required autofocus/>
    <input type="hidden" name="next" value="/mind"/>
    <button type="submit">Open MIND</button>
  </form>
</body>
</html>`;
}

function mindHtml(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Matterya · MIND Admin</title>
  <style>
    :root {
      --paper:#f8f6f2; --ink:#2c2825; --muted:#7a736c; --accent:#7b6347;
      --border:#ddd6cc; --surface:#fffcf8; --ok:#166534; --bad:#991b1b; --warn:#92400e;
    }
    * { box-sizing: border-box; }
    body { margin:0; font-family: system-ui, -apple-system, sans-serif; background:var(--paper); color:var(--ink); }
    header { padding:18px 22px; border-bottom:1px solid var(--border); background:var(--surface);
      display:flex; flex-wrap:wrap; gap:12px; align-items:center; justify-content:space-between; }
    .mark { font-size:11px; font-weight:700; letter-spacing:0.2em; text-transform:uppercase; color:var(--accent); }
    h1 { margin:4px 0 0; font-size:1.45rem; font-weight:500; font-family: ui-serif, Georgia, serif; }
    .tabs { display:flex; gap:6px; flex-wrap:wrap; padding:12px 16px 0; max-width:1200px; margin:0 auto; }
    .tab {
      border:1px solid var(--border); background:#efe8dc; color:var(--ink);
      border-radius:999px; padding:8px 14px; font-size:13px; font-weight:650; cursor:pointer;
      text-decoration:none; display:inline-block;
    }
    .tab.active { background:var(--accent); color:#fff; border-color:var(--accent); }
    main { max-width:1200px; margin:0 auto; padding:16px 16px 64px; }
    .panel { display:none; }
    .panel.active { display:block; }
    .card { background:var(--surface); border:1px solid var(--border); border-radius:16px; padding:18px 20px; margin-bottom:14px; }
    .grid { display:grid; grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); gap:12px; }
    .stat { background:#f3efe8; border-radius:12px; padding:14px 16px; }
    .stat .n { font-size:1.55rem; font-weight:700; font-variant-numeric:tabular-nums; }
    .stat .l { font-size:11px; color:var(--muted); margin-top:4px; font-weight:700; letter-spacing:0.04em; text-transform:uppercase; }
    .pill { display:inline-block; padding:4px 10px; border-radius:999px; font-size:12px; font-weight:600;
      background:#e8e2d8; margin-right:6px; margin-bottom:4px; }
    .pill.ok { background:#dcfce7; color:var(--ok); }
    .pill.warn { background:#fef3c7; color:var(--warn); }
    .pill.bad { background:#fee2e2; color:var(--bad); }
    .muted { color:var(--muted); font-size:14px; line-height:1.55; }
    .bar { height:12px; background:#e8e2d8; border-radius:999px; overflow:hidden; margin-top:10px; }
    .bar > i { display:block; height:100%; width:0%; background:linear-gradient(90deg,#7b6347,#a78b66); transition:width .4s ease; }
    h2 { font-family: ui-serif, Georgia, serif; font-weight:500; font-size:1.25rem; margin:0 0 8px; }
    h3 { font-size:0.95rem; margin:16px 0 8px; }
    .arch {
      display:grid; grid-template-columns:repeat(auto-fit,minmax(120px,1fr)); gap:8px; align-items:stretch;
    }
    .arch .box {
      background:#0c0a09; color:#e7e5e4; border-radius:12px; padding:12px; font-size:12px; text-align:center;
      line-height:1.35;
    }
    .arch .box strong { display:block; color:#fbbf24; margin-bottom:4px; font-size:11px; letter-spacing:0.06em; text-transform:uppercase; }
    .arch .arrow { display:flex; align-items:center; justify-content:center; color:var(--muted); font-size:18px; }
    table.gap { width:100%; border-collapse:collapse; font-size:13px; }
    table.gap th, table.gap td { text-align:left; padding:8px 10px; border-bottom:1px solid var(--border); vertical-align:top; }
    table.gap th { font-size:11px; text-transform:uppercase; letter-spacing:0.04em; color:var(--muted); }
    .dot { width:10px; height:10px; border-radius:50%; display:inline-block; margin-right:6px; }
    .dot.g { background:#16a34a; } .dot.a { background:#d97706; } .dot.m { background:#a8a29e; }
    #liveLog, #docBody {
      background:#0c0a09; color:#e7e5e4; padding:14px 16px; border-radius:12px;
      min-height:180px; max-height:52vh; overflow:auto; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size:12px; line-height:1.55; white-space:pre-wrap; word-break:break-word;
    }
    #docBody { font-family: system-ui, sans-serif; white-space:normal; background:var(--surface); color:var(--ink); border:1px solid var(--border); }
    #docBody h1,#docBody h2,#docBody h3 { font-family: ui-serif, Georgia, serif; }
    #docBody .mdcode, #docBody .mdtable { background:#0c0a09; color:#e7e5e4; padding:10px; border-radius:8px; overflow:auto; font-size:12px; }
    #docBody code { background:#efe8dc; padding:1px 5px; border-radius:4px; font-size:0.9em; }
    #docBody .mdcode code { background:transparent; color:inherit; padding:0; }
    .docnav { display:flex; flex-wrap:wrap; gap:6px; margin-bottom:12px; }
    .docnav button { border:1px solid var(--border); background:#efe8dc; border-radius:999px; padding:7px 12px; font-weight:650; font-size:12px; cursor:pointer; }
    .docnav button.active { background:var(--accent); color:#fff; border-color:var(--accent); }
    a.out { color:var(--accent); font-size:13px; }
    .two { display:grid; grid-template-columns:1.2fr 1fr; gap:14px; }
    @media (max-width:900px) { .two { grid-template-columns:1fr; } }
    .room { display:flex; justify-content:space-between; gap:8px; padding:8px 0; border-bottom:1px solid var(--border); font-size:14px; }
    .help { margin:0; padding-left:18px; color:var(--muted); font-size:13px; line-height:1.55; }
  </style>
</head>
<body>
  <header>
    <div>
      <div class="mark">Matterya ops · MIND</div>
      <h1>Intelligence &amp; Discovery</h1>
    </div>
    <div style="display:flex;gap:14px;align-items:center;flex-wrap:wrap">
      <span class="pill" id="policyPill">policy…</span>
      <span class="pill" id="ledgerFlag">ledger…</span>
      <a class="out" href="/pipeline">Pipeline</a>
      <a class="out" href="/frame0">Frame 0</a>
      <a class="out" href="/reports">Reports</a>
      <a class="out" href="/mind/logout">Log out</a>
    </div>
  </header>

  <div class="tabs">
    <button type="button" class="tab active" data-tab="overview">Overview</button>
    <button type="button" class="tab" data-tab="live">Live system</button>
    <button type="button" class="tab" data-tab="arch">Architecture</button>
    <button type="button" class="tab" data-tab="gaps">Gap matrix</button>
    <button type="button" class="tab" data-tab="masq">Masquerade</button>
    <button type="button" class="tab" data-tab="docs">Docs &amp; handbook</button>
    <button type="button" class="tab" data-tab="roadmap">Roadmap</button>
  </div>

  <main>
    <section class="panel active" id="panel-overview">
      <div class="card">
        <h2>What is MIND?</h2>
        <p class="muted" id="purposeBlurb">Loading purpose…</p>
        <ul class="help">
          <li>This console documents what is <em>actually deployed</em>, not only the handbook ideal.</li>
          <li>Handbook name <code>mind_feed_exposure</code> maps to Matterya table <code>feed_video_delivery</code> (ADR 0001).</li>
          <li>Feeds stay on REST in Phase 1 (ADR 0002). GraphQL FeedItem is roadmap.</li>
          <li>Numbers below refresh every 5s from <code>/mind/api/status</code>.</li>
        </ul>
      </div>
      <div class="grid" id="overviewStats"></div>
      <div class="card">
        <h2>Product surfaces (§1)</h2>
        <p class="muted">Every surface MIND powers today — HTTP route, ledger key, client, namespace.</p>
        <div id="surfaceCatalog"></div>
      </div>
      <div class="card">
        <h2>Admin guide (plain language)</h2>
        <div class="two">
          <div>
            <h3>When something looks wrong</h3>
            <ul class="help">
              <li><strong>Same video repeating</strong> → Live system → Ledger. If policy is <code>cursor</code>, ledger is off or failing.</li>
              <li><strong>Masquerade empty</strong> → Masquerade tab → room post counts + seed bar.</li>
              <li><strong>Odd ranking</strong> → note policy version pill; check engagement/hour + interest featureHits.</li>
            </ul>
          </div>
          <div>
            <h3>Phase 1 + 2a</h3>
            <ul class="help">
              <li>Gap matrix §1–§6, §7 media (2a), §8–§11, §19 are <strong>shipped</strong>.</li>
              <li>§14 ads, §15 GraphQL, §18 ML eval remain roadmap; pgvector ANN is Phase 2b.</li>
            </ul>
          </div>
        </div>
      </div>
    </section>

    <section class="panel" id="panel-live">
      <div class="grid" id="liveStats"></div>
      <div class="card">
        <h2>Delivery ledger by surface</h2>
        <p class="muted">At-most-once reservations (handbook §11). Unique per user + surface + canonical media key.</p>
        <div id="surfaceTable"></div>
      </div>
      <div class="two">
        <div class="card">
          <h2>Engagement (last hour)</h2>
          <p class="muted">Allowlisted client events → <code>entity_engagement_events</code> + Kafka. Meta is scrubbed (no email/token/GPS).</p>
          <div id="eventTypes"></div>
        </div>
        <div class="card">
          <h2>Rank decisions (24h)</h2>
          <p class="muted">From <code>recommendation_decisions</code> — why a batch was served.</p>
          <div id="decisions"></div>
        </div>
      </div>
      <div class="card">
        <h2>Seed pipeline (local host)</h2>
        <p class="muted" id="seedMeta">…</p>
        <div class="bar"><i id="seedBar"></i></div>
        <p class="muted" id="seedLine" style="margin-top:8px;font-family:ui-monospace,monospace;font-size:12px"></p>
      </div>
      <div class="card">
        <h2>Live feedback</h2>
        <p class="muted">Recent sanitized delivery + decision lines (no emails / tokens).</p>
        <div id="liveLog">Waiting for status…</div>
      </div>
    </section>

    <section class="panel" id="panel-arch">
      <div class="card">
        <h2>Request path (Matterya modules)</h2>
        <p class="muted">Handbook §3 redrawn onto the code that actually runs.</p>
        <div class="arch" style="margin-top:12px">
          <div class="box"><strong>Client</strong>iOS / web</div>
          <div class="box"><strong>API</strong>Express REST auth</div>
          <div class="box"><strong>Shelf</strong>shelf.service</div>
          <div class="box"><strong>Rank</strong>rank.service MMR</div>
          <div class="box"><strong>Gate</strong>eligibility.ts</div>
          <div class="box"><strong>Ledger</strong>reserveDeliveryBatch</div>
          <div class="box"><strong>CDN</strong>R2 signed media</div>
        </div>
        <h3>Async path</h3>
        <div class="arch">
          <div class="box"><strong>Events</strong>engagement ingest + Kafka</div>
          <div class="box"><strong>Features</strong>personality / affinity</div>
          <div class="box"><strong>Media</strong>transcripts → mind_content_features</div>
          <div class="box"><strong>Ops</strong>this /mind console</div>
        </div>
        <p class="muted" style="margin-top:12px">
          Masquerade uses <code>anonymous/*</code> schemas and never feeds Public preference vectors.
        </p>
      </div>
      <div class="card">
        <h2>Candidate lanes (§9)</h2>
        <p class="muted">Phase 1 multi-lane retrieval. ANN / collaborative sources are Phase 2+.</p>
        <div id="candLanes"></div>
        <h3>Live inventory (approx)</h3>
        <div id="candInv"></div>
        <p class="muted" id="candBudgets"></p>
      </div>
      <div class="card">
        <h2>Interest features (§8)</h2>
        <p class="muted">Online preference memory used by rank. Session embeddings / trained models are Phase 2+.</p>
        <div class="grid" id="interestStats"></div>
        <div id="interestSources" style="margin-top:12px"></div>
        <p class="muted" id="interestHits"></p>
      </div>
      <div class="card">
        <h2>Media understanding (§7)</h2>
        <p class="muted">Phase 2a: Groq transcripts → <code>mind_content_features</code> (topics/language). pgvector embeddings = Phase 2b.</p>
        <div class="grid" id="mediaStats"></div>
        <div id="mediaCatalog" style="margin-top:12px"></div>
        <p class="muted" id="mediaNote"></p>
      </div>
    </section>

    <section class="panel" id="panel-gaps">
      <div class="card">
        <h2>Gap matrix vs handbook</h2>
        <p class="muted"><span class="dot g"></span>shipped · <span class="dot a"></span>partial · <span class="dot m"></span>missing / roadmap</p>
        <table class="gap" id="gapTable">
          <thead><tr><th>§</th><th>Topic</th><th>Status</th><th>Matterya</th></tr></thead>
          <tbody></tbody>
        </table>
      </div>
    </section>

    <section class="panel" id="panel-masq">
      <div class="card">
        <h2>Canonical rooms</h2>
        <p class="muted">Duplicates (High Strangeness, confession, …) are merged into these active rooms.</p>
        <div id="rooms"></div>
      </div>
      <div class="card">
        <h2>Isolation proofs (handbook §6)</h2>
        <p id="isoNote" class="muted"></p>
        <span class="pill ok" id="isoPill">…</span>
        <div id="isoChecks" style="margin-top:14px"></div>
      </div>
    </section>

    <section class="panel" id="panel-docs">
      <div class="card">
        <h2>Documentation</h2>
        <p class="muted">Same files as <code>docs/mind/</code> in the repo — rendered here so you never hunt Downloads.</p>
        <div class="docnav" id="docNav"></div>
        <div id="docBody">Select a document…</div>
      </div>
    </section>

    <section class="panel" id="panel-roadmap">
      <div class="card">
        <h2>Roadmap</h2>
        <div class="grid">
          <div class="stat"><div class="n" style="font-size:1rem">Phase 0+1</div><div class="l">Audit · ledger · admin · REST meta</div><span class="pill ok">shipped</span></div>
          <div class="stat"><div class="n" style="font-size:1rem">Phase 2a</div><div class="l">Transcript features live · embeddings next</div><span class="pill ok">phase2.v1</span></div>
          <div class="stat"><div class="n" style="font-size:1rem">Phase 2b</div><div class="l">pgvector ANN · content embeddings</div><span class="pill">not built</span></div>
          <div class="stat"><div class="n" style="font-size:1rem">Phase 3</div><div class="l">Trained ranker · experiments</div><span class="pill">not built</span></div>
          <div class="stat"><div class="n" style="font-size:1rem">Phase 4</div><div class="l">Search · world · Guardian depth</div><span class="pill">not built</span></div>
          <div class="stat"><div class="n" style="font-size:1rem">Phase 5</div><div class="l">Scale only after measured need</div><span class="pill">not built</span></div>
        </div>
      </div>
    </section>
  </main>

<script>
const GAPS = [
  ['1','Purpose / surfaces','shipped','Surface catalog + endpoints + ledger keys'],
  ['2','Invariants','shipped','At-most-once ledger; soft-recycle penalty; fail → cursor'],
  ['3','Architecture','shipped','This Architecture tab'],
  ['5','Events','shipped','Allowlist ingest + meta scrub + Kafka/PG'],
  ['6','Masquerade isolation','shipped','Live proofs + surface namespace guards'],
  ['7','Media understanding','shipped','Transcripts + mind_content_features (Phase 2a; pgvector later)'],
  ['8','Interest features','shipped','Personality + creator affinity + featureHits'],
  ['9','Candidates','shipped','Multi-lane retrieval + mix meta + inventory'],
  ['10','Rank + diversity','shipped','MMR + family caps (Home/Hubs/Masquerade)'],
  ['11','Exposure ledger','shipped','feed_video_delivery on all For You surfaces'],
  ['14','Ads / economy','missing','Phase 4+'],
  ['15','GraphQL FeedItem','missing','REST (ADR 0002)'],
  ['18','ML evaluation','missing','Phase 2–3'],
  ['19','Observability','shipped','Live events, decisions, ledger, seed'],
];

function $(id){ return document.getElementById(id); }
function fmt(n){ return (n??0).toLocaleString(); }

document.querySelectorAll('.tab').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
    btn.classList.add('active');
    $('panel-' + btn.dataset.tab).classList.add('active');
  });
});

const gapBody = document.querySelector('#gapTable tbody');
GAPS.forEach(([sec, topic, st, where]) => {
  const cls = st === 'shipped' ? 'g' : st === 'partial' ? 'a' : 'm';
  const tr = document.createElement('tr');
  tr.innerHTML = '<td>'+sec+'</td><td>'+topic+'</td><td><span class="dot '+cls+'"></span>'+st+'</td><td>'+where+'</td>';
  gapBody.appendChild(tr);
});

async function loadDoc(slug, btn){
  document.querySelectorAll('#docNav button').forEach(b => b.classList.remove('active'));
  if (btn) btn.classList.add('active');
  $('docBody').textContent = 'Loading…';
  const res = await fetch('/mind/api/docs/' + slug, { credentials:'same-origin' });
  const data = await res.json();
  if (!data.ok) { $('docBody').textContent = data.error || 'Failed'; return; }
  $('docBody').innerHTML = data.html;
}

async function refresh(){
  try {
    const res = await fetch('/mind/api/status', { credentials:'same-origin' });
    if (res.status === 401) { location.reload(); return; }
    const s = await res.json();
    if (!s.ok) return;

    $('policyPill').textContent = s.policyVersion;
    const led = s.flags.mindLedgerEnabled;
    $('ledgerFlag').textContent = led ? 'ledger ON' : 'ledger OFF';
    $('ledgerFlag').className = 'pill ' + (led ? 'ok' : 'warn');

    const purpose = s.purpose || {};
    if (purpose.blurb) $('purposeBlurb').textContent = purpose.blurb;
    $('surfaceCatalog').innerHTML = (purpose.surfaces||[]).map(surf =>
      '<div class="room" style="align-items:flex-start">'
      + '<span><strong>'+surf.label+'</strong> <span class="pill">'+surf.namespace+'</span><br/>'
      + '<span class="muted">'+surf.purpose+'</span><br/>'
      + '<span class="muted"><code>'+surf.http+'</code>'
      + (surf.ledgerSurface ? ' · ledger <code>'+surf.ledgerSurface+'</code>' : ' · no ledger')
      + ' · '+surf.client+'</span></span></div>'
    ).join('') || '<p class="muted">No surfaces.</p>';

    const eng = s.engagement || {};
    const dec = s.decisions || {};
    $('overviewStats').innerHTML = [
      ['Deliveries', s.ledger.deliveries],
      ['Deliveries 24h', s.ledger.deliveries24h],
      ['Events / hour', eng.events1h],
      ['Events 24h', eng.events24h],
      ['Positives / hour', eng.positives1h],
      ['Negatives / hour', eng.negatives1h],
      ['Decisions 24h', dec.count24h],
      ['Masquerade posts', s.masquerade.posts],
      ['R2 media posts', s.masquerade.r2media],
      ['Gap shipped', s.gapSummary.shipped],
    ].map(([l,n]) => '<div class="stat"><div class="n">'+fmt(n)+'</div><div class="l">'+l+'</div></div>').join('');

    $('liveStats').innerHTML = $('overviewStats').innerHTML;

    $('surfaceTable').innerHTML = (s.ledger.bySurface||[]).map(r =>
      '<div class="room"><span>'+r.surface+'</span><strong>'+fmt(r.n)+'</strong></div>'
    ).join('') || '<p class="muted">No ledger rows yet.</p>';

    const maxEv = Math.max(1, ...((eng.byType1h||[]).map(x => x.n)));
    $('eventTypes').innerHTML = (eng.byType1h||[]).length
      ? (eng.byType1h||[]).map(r => {
          const pct = Math.round(100 * r.n / maxEv);
          return '<div class="room"><span style="min-width:0;flex:1">'+r.type.replace('Engagement','')+'</span><strong>'+fmt(r.n)+'</strong></div>'
            + '<div class="bar" style="margin:2px 0 8px"><i style="width:'+pct+'%"></i></div>';
        }).join('')
        + '<p class="muted" style="margin-top:8px">Allowlist size: '+fmt(eng.allowlistSize||0)+' client types</p>'
      : '<p class="muted">No engagement in the last hour.</p>';

    $('decisions').innerHTML = (dec.recent||[]).length
      ? (dec.recent||[]).map(r =>
          '<div class="room"><span><strong>'+r.surface+'</strong> · '+r.policy+' · '+r.latencyMs+'ms</span><strong>'+fmt(r.served)+'</strong></div>'
        ).join('')
        + '<p class="muted" style="margin-top:8px">24h decisions: '+fmt(dec.count24h||0)+'</p>'
      : '<p class="muted">No rank decisions logged yet (ranker writes when candidates are scored).</p>';

    const seed = s.seed || {};
    if (!seed.available) {
      $('seedMeta').textContent = 'Local seed log not on this host (normal on Render).';
      $('seedBar').style.width = '0%';
      $('seedLine').textContent = '';
    } else {
      const pct = seed.total ? Math.min(100, Math.round(100 * (seed.done||0) / seed.total)) : 0;
      $('seedMeta').textContent = 'Phase: ' + (seed.phase||'?') + ' · pid ' + (seed.pidAlive ? 'alive' : 'stopped/unknown');
      $('seedBar').style.width = pct + '%';
      $('seedLine').textContent = seed.progressLine || '';
    }

    $('liveLog').textContent = (s.recent||[]).map(r => r.at + '  [' + r.kind + ']  ' + r.text).join('\\n') || 'No recent deliveries.';

    $('rooms').innerHTML = (s.masquerade.rooms||[]).map(r =>
      '<div class="room"><span><strong>'+r.title+'</strong> <span class="muted">'+r.slug+'</span></span><strong>'+fmt(r.posts)+'</strong></div>'
    ).join('') || '<p class="muted">No active rooms.</p>';

    const iso = s.masquerade.isolation || {};
    $('isoNote').textContent = iso.note || '';
    const overall = iso.overall || 'warn';
    $('isoPill').textContent = 'isolation ' + overall;
    $('isoPill').className = 'pill ' + (overall === 'pass' ? 'ok' : overall === 'fail' ? 'bad' : 'warn');
    $('isoChecks').innerHTML = (iso.checks || []).map(c => {
      const cls = c.status === 'pass' ? 'ok' : c.status === 'fail' ? 'bad' : 'warn';
      return '<div class="room"><span><span class="pill '+cls+'">'+c.status+'</span> <strong>'+c.label+'</strong><br/><span class="muted">'+c.detail+'</span></span></div>';
    }).join('') || '<p class="muted">No checks returned.</p>';

    const cand = s.candidates || {};
    $('candLanes').innerHTML = (cand.lanes||[]).map(l =>
      '<div class="room"><span><strong>'+l.label+'</strong><br/><span class="muted">'+l.description+'</span></span><span class="pill">'+l.surface+'</span></div>'
    ).join('') || '<p class="muted">No lanes.</p>';
    $('candInv').innerHTML = (cand.inventory||[]).map(r =>
      '<div class="room"><span>'+r.lane+'</span><strong>'+fmt(r.n)+'</strong></div>'
    ).join('') || '<p class="muted">Inventory probe unavailable.</p>';
    const b = cand.budgets || {};
    $('candBudgets').textContent = b.homeRawPool
      ? 'Budgets: home pool '+b.homeRawPool+' · hubs pool '+b.hubsRawPool+' · masquerade window '+b.masqueradeHotWindow+' · page ~'+b.servePage
      : '';

    const interest = s.interest || {};
    $('interestStats').innerHTML = [
      ['Personality rows', interest.personalityRows],
      ['Personality warm', interest.personalityWarm],
      ['Creator affinity rows', interest.creatorAffinityRows],
      ['Item stats rows', interest.itemStatsRows],
    ].map(([l,n]) => '<div class="stat"><div class="n">'+fmt(n)+'</div><div class="l">'+l+'</div></div>').join('');
    $('interestSources').innerHTML = (interest.sources||[]).map(src =>
      '<div class="room"><span><strong>'+src.label+'</strong><br/><span class="muted"><code>'+src.table+'</code> · '+src.usedBy+'</span></span></div>'
    ).join('');
    const rh = interest.recentHits || {};
    $('interestHits').textContent = rh.sample
      ? 'Last '+fmt(rh.sample)+' decisions: affinity hit '+fmt(rh.withAffinity)+' · personality hit '+fmt(rh.withPersonality)
      : 'No recent decision featureHits yet (fills as rank runs after deploy).';

    const media = s.mediaUnderstanding || {};
    const tBy = {};
    (media.transcripts||[]).forEach(r => { tBy[r.status] = r.n; });
    $('mediaStats').innerHTML = [
      ['Features', media.features],
      ['Ready+features', media.readyWithFeatures],
      ['Transcript ready', tBy.ready||0],
      ['Transcript pending', tBy.pending||0],
      ['Skipped', tBy.skipped||0],
      ['Failed', tBy.failed||0],
    ].map(([l,n]) => '<div class="stat"><div class="n">'+fmt(n)+'</div><div class="l">'+l+'</div></div>').join('');
    $('mediaCatalog').innerHTML = (media.catalog||[]).map(c =>
      '<div class="room"><span><strong>'+c.label+'</strong><br/><span class="muted">'+c.description+'</span></span><span class="pill">'+c.id+'</span></div>'
    ).join('') || '<p class="muted">No feature catalog.</p>';
    $('mediaNote').textContent =
      'pipeline '+ (media.pipelineVersion||'?')
      + ' · features ' + (media.enabled ? 'ON' : 'OFF')
      + ' · Groq ' + (media.groqConfigured ? 'configured' : 'missing key')
      + ' · missing transcript = UNKNOWN (never demoted)';

    if (!$('docNav').dataset.ready) {
      $('docNav').dataset.ready = '1';
      (s.docs||[]).forEach((d,i) => {
        const b = document.createElement('button');
        b.type = 'button';
        b.textContent = d.title;
        b.addEventListener('click', () => loadDoc(d.slug, b));
        $('docNav').appendChild(b);
        if (i === 0) loadDoc(d.slug, b);
      });
    }
  } catch (e) {
    console.warn(e);
  }
}

refresh();
// 15s — status API also caches ~20s; tighter polls burned Supabase Disk IO.
setInterval(refresh, 15000);
</script>
</body>
</html>`;
}

export async function handleMindGet(req: Request, res: Response): Promise<void> {
  if (!hasOpsAccess(req)) {
    res.status(200).type('html').send(loginHtml());
    return;
  }
  res.status(200).type('html').send(mindHtml());
}

export const handleMindLogin = handleOpsLogin;

export function handleMindLogout(_req: Request, res: Response): void {
  res.setHeader(
    'Set-Cookie',
    'matterya_pipeline_auth=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0'
  );
  res.redirect(302, '/mind');
}

export async function handleMindStatus(req: Request, res: Response): Promise<void> {
  if (!hasOpsAccess(req)) {
    res.status(401).json({ ok: false, error: 'unauthorized' });
    return;
  }
  try {
    const status = await getMindStatus();
    res.json(status);
  } catch (err: any) {
    res.status(500).json({ ok: false, error: err?.message ?? 'status_failed' });
  }
}

export async function handleMindDoc(req: Request, res: Response): Promise<void> {
  if (!hasOpsAccess(req)) {
    res.status(401).json({ ok: false, error: 'unauthorized' });
    return;
  }
  const slug = String(req.params.slug || '');
  const md = readMindDoc(slug);
  if (!md) {
    res.status(404).json({ ok: false, error: 'not_found' });
    return;
  }
  res.json({ ok: true, slug, html: mdToSafeHtml(md) });
}

export async function handleMindStream(req: Request, res: Response): Promise<void> {
  if (!hasOpsAccess(req)) {
    res.status(401).json({ ok: false, error: 'unauthorized' });
    return;
  }
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.flushHeaders?.();

  let alive = true;
  req.on('close', () => {
    alive = false;
  });

  const tick = async () => {
    if (!alive) return;
    try {
      const status = await getMindStatus();
      res.write(`data: ${JSON.stringify({ at: status.at, seed: status.seed, ledger: status.ledger.deliveries24h })}\n\n`);
    } catch {
      res.write(`data: ${JSON.stringify({ error: 'tick_failed' })}\n\n`);
    }
  };

  await tick();
  const iv = setInterval(() => {
    void tick();
  }, 8000);
  req.on('close', () => clearInterval(iv));
}
