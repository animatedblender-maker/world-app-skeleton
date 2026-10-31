/**
 * Unified Matterya moderation queue — auto-claim + policy decision tree.
 * https://api.matterya.com/reports
 *
 * Moderators answer questions with keyboard shortcuts.
 * Remove / Mark / Dismiss is applied by policy from the chosen leaf —
 * mods are not shown that outcome.
 */
import type { Request, Response } from 'express';
import {
  hasReportsAccess,
  renderReportsLoginHtml,
  REPORTS_PAGE_PASSWORD,
} from './reports-page.js';
import { labelForCategory } from '../moderation/categories.js';
import {
  claimNextTicket,
  claimTicketById,
  ensureAutoTicketsFromFlaggedPosts,
  getClaimedTicketForActor,
  hydrateTicketDisplay,
  openTicketCount,
  releaseTicket,
  resolveTicket,
  type TicketCommentSnippet,
  type TicketDisplay,
  type TicketParentPost,
  type TicketRow,
} from '../moderation/tickets.js';
import {
  getPolicyLeaf,
  outcomeToResolveAction,
  policyTreeForClient,
} from '../moderation/policy-tree.js';
import { handleReportsGet } from './reports-page.js';

function escapeHtml(s: string): string {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function actorFromReq(req: Request): string {
  const q = String(req.query.actor ?? req.body?.actor ?? '').trim();
  if (q) return q.slice(0, 80);
  const ua = String(req.headers['user-agent'] ?? 'mod').slice(0, 40);
  return `mod:${Buffer.from(ua).toString('base64url').slice(0, 24)}`;
}

/** Dicebear fallback avatar. */
function dicebearAvatar(seed: string): string {
  const s = seed.trim() || 'anonymous';
  return `https://api.dicebear.com/7.x/shapes/svg?seed=${encodeURIComponent(s)}`;
}

/**
 * Prefer a durable avatar URL. Supabase `/object/sign/...` tokens expire and
 * 400 in the browser — rewrite to `/object/public/...` when possible.
 */
function durableAvatarUrl(
  direct: string | null | undefined,
  seed: string
): string {
  const raw = String(direct || '').trim();
  if (!raw.startsWith('http')) return dicebearAvatar(seed);
  try {
    const u = new URL(raw);
    if (
      u.hostname.includes('supabase') &&
      u.pathname.includes('/storage/v1/object/sign/')
    ) {
      u.pathname = u.pathname.replace(
        '/storage/v1/object/sign/',
        '/storage/v1/object/public/'
      );
      u.search = '';
      u.hash = '';
      return u.toString();
    }
    return raw;
  } catch {
    return dicebearAvatar(seed);
  }
}

function avatarUrlFor(ticket: TicketDisplay): string {
  const s =
    (ticket.author_avatar_seed || ticket.author_username || 'anonymous').trim() ||
    'anonymous';
  return durableAvatarUrl(ticket.author_avatar_url, s);
}

async function ensureClaimedTicket(
  actor: string,
  opts?: { excludeTicketId?: string | null; preferTicketId?: string | null }
): Promise<TicketRow | null> {
  const prefer = opts?.preferTicketId?.trim() || null;
  if (prefer && /^[0-9a-f-]{36}$/i.test(prefer)) {
    const result = await claimTicketById(prefer, actor);
    if (result.ok && result.ticket && (result.ticket.queue || 'content') !== 'account') {
      return result.ticket;
    }
  }

  const existing = await getClaimedTicketForActor(actor, { queue: 'content' });
  if (existing) {
    if (opts?.excludeTicketId && existing.id === opts.excludeTicketId) {
      // fall through
    } else {
      return existing;
    }
  }
  return claimNextTicket(actor, {
    excludeTicketId: opts?.excludeTicketId,
    queue: 'content',
  });
}

function renderShell(opts: {
  actor: string;
  openCount: number;
  body: string;
  flash?: string | null;
  treeJson?: string;
}): string {
  const flash = opts.flash
    ? `<p class="flash">${escapeHtml(opts.flash)}</p>`
    : '';
  const treeScript = opts.treeJson
    ? `<script type="application/json" id="policy-tree-data">${opts.treeJson}</script>`
    : '';
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>Matterya · Moderation</title>
<style>
  :root {
    --paper: #f8f6f2; --ink: #2c2825; --muted: #7a736c; --accent: #7b6347;
    --border: #ddd6cc; --surface: #fffcf8; --danger: #b91c1c; --ok: #166534;
    --wash: #f3efe8; --key: #efe8dc;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
    background: radial-gradient(1200px 600px at 20% 0%, #efe8dc 0%, var(--paper) 55%);
    color: var(--ink); min-height: 100vh;
  }
  header {
    position: sticky; top: 0; z-index: 5;
    background: rgba(255,252,248,.92); backdrop-filter: blur(10px);
    border-bottom: 1px solid var(--border);
    padding: 14px 20px; display: flex; flex-wrap: wrap; gap: 12px 18px; align-items: center;
  }
  .mark {
    font-size: 11px; font-weight: 700; letter-spacing: .2em;
    text-transform: uppercase; color: var(--accent);
  }
  h1 {
    margin: 0; font-size: 1.3rem; font-weight: 500;
    font-family: ui-serif, Georgia, serif;
  }
  .header-copy { display: grid; gap: 2px; }
  .muted { color: var(--muted); font-size: .85rem; }
  .pill {
    display: inline-flex; align-items: center; gap: 6px;
    padding: .2rem .65rem; border-radius: 999px; font-size: .75rem; font-weight: 700;
    background: #f3e8d8; color: var(--accent); border: 1px solid #e8dcc8;
  }
  .pill.ok { color: var(--ok); border-color: #bbf7d0; background: #dcfce7; }
  .pill.auto { color: #92400e; border-color: #fde68a; background: #fff7ed; }
  a.nav { color: var(--accent); text-decoration: none; font-size: .85rem; margin-left: 10px; }
  a.nav:hover { text-decoration: underline; }
  main.layout {
    max-width: 1180px; margin: 0 auto; padding: 20px 16px 64px;
    display: grid; grid-template-columns: minmax(0, 1.15fr) minmax(300px, 0.85fr);
    gap: 18px; align-items: start;
  }
  @media (max-width: 900px) {
    main.layout { grid-template-columns: 1fr; }
    .decision { position: static !important; }
  }
  .flash {
    grid-column: 1 / -1;
    background: #dcfce7; border: 1px solid #bbf7d0; color: var(--ok);
    padding: 10px 12px; border-radius: 10px;
  }
  .card {
    background: var(--surface); border: 1px solid var(--border); border-radius: 16px;
    padding: 18px; display: grid; gap: 14px;
    box-shadow: 0 10px 28px rgba(44,40,37,.06);
  }
  .card-stack { display: grid; gap: 12px; }
  .reported {
    background: #fffbeb;
    border: 2px solid #fbbf24;
    border-radius: 14px;
    padding: 14px;
    display: grid;
    gap: 12px;
    box-shadow: inset 0 0 0 1px #fde68a;
  }
  .reported-label {
    font-size: 11px; font-weight: 800; letter-spacing: .12em;
    text-transform: uppercase; color: #92400e;
  }
  .context-block {
    background: var(--wash); border: 1px solid var(--border);
    border-radius: 14px; padding: 14px; display: grid; gap: 10px;
  }
  .context-block .eyebrow {
    font-size: 11px; font-weight: 700; letter-spacing: .12em;
    text-transform: uppercase; color: var(--accent);
  }
  .thread-list { display: grid; gap: 8px; }
  .thread-item {
    display: grid; grid-template-columns: 32px 1fr; gap: 10px;
    padding: 10px 12px; border-radius: 12px;
    background: #fff; border: 1px solid var(--border);
  }
  .thread-item img {
    width: 32px; height: 32px; border-radius: 50%;
    background: #efe8dc; border: 1px solid var(--border); object-fit: cover;
  }
  .thread-item .who {
    font-weight: 650; font-size: .82rem; margin-bottom: 2px;
  }
  .thread-item .txt {
    color: var(--ink); font-size: .9rem; line-height: 1.4;
    white-space: pre-wrap; word-break: break-word;
  }
  .thread-empty { color: var(--muted); font-size: .85rem; padding: 4px 2px; }
  .card-top {
    display: flex; align-items: flex-start; justify-content: space-between; gap: 12px;
  }
  .author { display: flex; align-items: center; gap: 12px; min-width: 0; }
  .author img {
    width: 44px; height: 44px; border-radius: 50%;
    background: #efe8dc; border: 1px solid var(--border); object-fit: cover;
  }
  .author .who { display: grid; gap: 2px; min-width: 0; }
  .author .name {
    font-weight: 650; font-size: .95rem; line-height: 1.2;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }
  .author .sub { color: var(--muted); font-size: .78rem; }
  .copy-link {
    flex: 0 0 auto; cursor: pointer; font: inherit; font-size: .78rem; font-weight: 650;
    border-radius: 999px; border: 1px solid var(--border); background: var(--key);
    color: var(--accent); padding: .4rem .75rem; white-space: nowrap;
  }
  .copy-link:hover { border-color: var(--accent); }
  .copy-link.copied { background: #dcfce7; border-color: #bbf7d0; color: var(--ok); }
  .meta { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
  h2 { margin: 0; font-size: 1.15rem; line-height: 1.35; font-weight: 600; }
  .body { margin: 0; color: var(--muted); white-space: pre-wrap; line-height: 1.45; }
  .body mark.name-hit, .text-post mark.name-hit {
    background: #fde68a; color: #78350f; padding: 0 .15em; border-radius: 3px;
    font-weight: 700;
  }
  .media {
    width: 100%; max-height: 480px; border-radius: 12px;
    background: #111; object-fit: contain; display: block;
  }
  video.media { max-height: 520px; }
  .media.empty {
    height: 120px; display: grid; place-items: center; color: var(--muted);
    background: var(--wash);
  }
  .text-post {
    border-radius: 14px; border: 1px solid var(--border); background: linear-gradient(180deg, #fffcf8, #f3efe8);
    padding: 22px 20px; min-height: 140px; display: grid; gap: 10px; align-content: center;
  }
  .text-post .eyebrow {
    font-size: 11px; font-weight: 700; letter-spacing: .14em; text-transform: uppercase; color: var(--accent);
  }
  .text-post .quote {
    margin: 0; font-family: ui-serif, Georgia, serif; font-size: 1.15rem; line-height: 1.45; color: var(--ink);
    white-space: pre-wrap;
  }
  .reporter {
    display: grid; gap: 10px; padding: 12px; border-radius: 12px;
    background: var(--wash); border: 1px solid var(--border);
  }
  .reporter.hit {
    background: #fff7ed; border-color: #fde68a;
  }
  .reporter .label {
    font-size: 11px; font-weight: 700; letter-spacing: .12em; text-transform: uppercase; color: var(--accent);
  }
  .reporter .row {
    display: flex; align-items: center; gap: 10px;
  }
  .reporter img {
    width: 36px; height: 36px; border-radius: 50%;
    background: #efe8dc; border: 1px solid var(--border); object-fit: cover;
  }
  .reporter .name { font-weight: 650; font-size: .9rem; }
  .reporter .sub { color: var(--muted); font-size: .75rem; }
  .match-banner {
    font-size: .8rem; color: #92400e; background: #fef3c7; border: 1px solid #fde68a;
    border-radius: 10px; padding: 8px 10px; line-height: 1.35;
  }
  .decision {
    position: sticky; top: 78px;
    background: var(--surface); border: 1px solid var(--border); border-radius: 16px;
    padding: 16px; box-shadow: 0 10px 28px rgba(44,40,37,.06);
    display: grid; gap: 12px;
  }
  .decision .step {
    font-size: 11px; font-weight: 700; letter-spacing: .12em;
    text-transform: uppercase; color: var(--accent);
  }
  .decision h2 {
    font-family: ui-serif, Georgia, serif; font-weight: 500; font-size: 1.2rem;
  }
  .crumb {
    display: flex; flex-wrap: wrap; gap: 6px; font-size: .78rem; color: var(--muted);
  }
  .crumb span {
    background: var(--wash); border: 1px solid var(--border);
    border-radius: 999px; padding: 2px 8px;
  }
  .options { display: grid; gap: 8px; }
  .opt {
    display: flex; gap: 10px; align-items: flex-start; width: 100%;
    text-align: left; cursor: pointer; border: 1px solid var(--border);
    background: #fff; border-radius: 12px; padding: 10px 12px;
    font: inherit; color: var(--ink);
  }
  .opt:hover, .opt:focus {
    border-color: var(--accent); outline: none;
    box-shadow: 0 0 0 3px rgba(123,99,71,.15);
  }
  .opt .k {
    flex: 0 0 auto; min-width: 28px; height: 28px; border-radius: 8px;
    display: grid; place-items: center; font-weight: 800; font-size: .85rem;
    background: var(--key); color: var(--accent); border: 1px solid #e8dcc8;
  }
  .opt .lbl { flex: 1; padding-top: 3px; line-height: 1.35; }
  .hint {
    font-size: .78rem; color: var(--muted); line-height: 1.4;
    border-top: 1px solid var(--border); padding-top: 10px;
  }
  .hint kbd {
    display: inline-block; padding: 1px 6px; border-radius: 6px;
    background: var(--key); border: 1px solid #e8dcc8; font-size: .72rem;
  }
  .empty { text-align: center; padding: 48px 16px; }
</style>
</head>
<body>
<header>
  <div class="header-copy">
    <div class="mark">Matterya</div>
    <h1>Moderation</h1>
  </div>
  <span class="pill ok">${opts.openCount} open</span>
  <span style="flex:1"></span>
  <a class="nav" href="/management">Management</a>
  <a class="nav" href="/reports/logout">Log out</a>
</header>
<main class="layout">
  ${flash}
  ${opts.body}
</main>
${treeScript}
<script>
(function () {
  var dataEl = document.getElementById('policy-tree-data');
  var panel = document.getElementById('decision-panel');
  if (!dataEl || !panel) return;
  var tree = JSON.parse(dataEl.textContent || '{}');
  var ticketId = panel.getAttribute('data-ticket-id') || '';
  var stack = [tree];
  var crumbs = [];

  function render() {
    var node = stack[stack.length - 1];
    var step = document.getElementById('decision-step');
    var q = document.getElementById('decision-question');
    var crumbEl = document.getElementById('decision-crumbs');
    var optsEl = document.getElementById('decision-options');
    if (!node || !optsEl) return;

    if (node.kind === 'leaf') {
      step.textContent = 'Confirm';
      q.textContent = 'Record this decision?';
      crumbEl.innerHTML = crumbs.concat(node.label).map(function (c) {
        return '<span>' + escapeHtml(c) + '</span>';
      }).join('');
      optsEl.innerHTML =
        '<button type="button" class="opt" data-confirm="1"><span class="k">Enter</span><span class="lbl">Yes — record &amp; continue</span></button>' +
        '<button type="button" class="opt" data-back="1"><span class="k">⌫</span><span class="lbl">No — go back</span></button>';
      return;
    }

    step.textContent = 'Step ' + stack.length;
    q.textContent = node.question || 'Choose an option';
    crumbEl.innerHTML = crumbs.map(function (c) {
      return '<span>' + escapeHtml(c) + '</span>';
    }).join('') || '<span class="muted">Start</span>';
    optsEl.innerHTML = (node.options || []).map(function (o) {
      return (
        '<button type="button" class="opt" data-key="' + escapeAttr(o.key) + '">' +
          '<span class="k">' + escapeHtml(String(o.key).toUpperCase()) + '</span>' +
          '<span class="lbl">' + escapeHtml(o.label) + '</span>' +
        '</button>'
      );
    }).join('');
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }
  function escapeAttr(s) { return escapeHtml(s); }

  function chooseKey(key) {
    var node = stack[stack.length - 1];
    if (!node || node.kind === 'leaf') return;
    var hit = (node.options || []).find(function (o) {
      return String(o.key).toLowerCase() === String(key).toLowerCase();
    });
    if (!hit) return;
    crumbs.push(hit.label);
    stack.push(hit.node);
    render();
  }

  function goBack() {
    if (stack.length <= 1) return;
    stack.pop();
    crumbs.pop();
    render();
  }

  function submitLeaf(leafId) {
    var form = document.createElement('form');
    form.method = 'POST';
    form.action = '/reports/ticket/action';
    function add(name, value) {
      var i = document.createElement('input');
      i.type = 'hidden'; i.name = name; i.value = value;
      form.appendChild(i);
    }
    add('ticket_id', ticketId);
    add('action', 'decide');
    add('leaf_id', leafId);
    document.body.appendChild(form);
    form.submit();
  }

  function passTicket() {
    var form = document.createElement('form');
    form.method = 'POST';
    form.action = '/reports/ticket/action';
    function add(name, value) {
      var i = document.createElement('input');
      i.type = 'hidden'; i.name = name; i.value = value;
      form.appendChild(i);
    }
    add('ticket_id', ticketId);
    add('action', 'release');
    document.body.appendChild(form);
    form.submit();
  }

  panel.addEventListener('click', function (e) {
    var btn = e.target.closest('.opt');
    if (!btn) return;
    if (btn.getAttribute('data-back')) { goBack(); return; }
    if (btn.getAttribute('data-confirm')) {
      var leaf = stack[stack.length - 1];
      if (leaf && leaf.kind === 'leaf') submitLeaf(leaf.id);
      return;
    }
    var key = btn.getAttribute('data-key');
    if (key) chooseKey(key);
  });

  window.addEventListener('keydown', function (e) {
    if (e.target && /INPUT|TEXTAREA|SELECT/.test(e.target.tagName)) return;
    if (e.key === 'Backspace' || e.key === 'Escape') {
      e.preventDefault();
      goBack();
      return;
    }
    if (e.key === 'Enter') {
      var node = stack[stack.length - 1];
      if (node && node.kind === 'leaf') {
        e.preventDefault();
        submitLeaf(node.id);
      }
      return;
    }
    if (e.key === 'p' || e.key === 'P') {
      e.preventDefault();
      passTicket();
      return;
    }
    if (e.key && e.key.length === 1) {
      chooseKey(e.key);
    }
  });

  var copyBtn = document.getElementById('copy-ticket-link');
  if (copyBtn) {
    copyBtn.addEventListener('click', function () {
      var link = copyBtn.getAttribute('data-link') || '';
      function done() {
        copyBtn.textContent = 'Copied';
        copyBtn.classList.add('copied');
        setTimeout(function () {
          copyBtn.textContent = 'Copy link';
          copyBtn.classList.remove('copied');
        }, 1400);
      }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(link).then(done).catch(function () {
          window.prompt('Copy ticket link', link);
        });
      } else {
        window.prompt('Copy ticket link', link);
      }
    });
  }

  render();
})();
</script>
</body>
</html>`;
}

function highlightNames(text: string, matches: string[]): string {
  const escaped = escapeHtml(text);
  if (!matches.length) return escaped;
  let out = escaped;
  for (const m of matches) {
    const token = escapeHtml(m);
    if (!token) continue;
    const re = new RegExp(`(${token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')})`, 'gi');
    out = out.replace(re, '<mark class="name-hit">$1</mark>');
  }
  return out;
}

function reporterAvatarUrl(ticket: TicketDisplay): string {
  const s =
    (ticket.reporter_avatar_seed ||
      ticket.reporter_username ||
      ticket.reporter_display_name ||
      'reporter').trim() || 'reporter';
  return durableAvatarUrl(ticket.reporter_avatar_url, s);
}

function renderReporter(ticket: TicketDisplay): string {
  if (ticket.source !== 'user') return '';
  const hasReporter =
    ticket.reporter_username ||
    ticket.reporter_display_name ||
    ticket.reporter_user_id ||
    ticket.reporter_profile_id;
  if (!hasReporter) {
    return `
    <div class="reporter">
      <div class="label">Reporter</div>
      <div class="sub">User report · reporter profile unavailable</div>
    </div>`;
  }
  const display =
    ticket.reporter_display_name || ticket.reporter_username || 'reporter';
  const handle = ticket.reporter_username
    ? `@${ticket.reporter_username}`
    : ticket.reporter_user_id
      ? ticket.reporter_user_id.slice(0, 8)
      : '';
  const hit = ticket.name_matches.length > 0;
  const matchBanner = hit
    ? `<div class="match-banner">Name match in post: ${ticket.name_matches
        .map((m) => `<mark class="name-hit">${escapeHtml(m)}</mark>`)
        .join(', ')} — check bullying / targeted harassment</div>`
    : '';
  return `
  <div class="reporter${hit ? ' hit' : ''}">
    <div class="label">Reported by</div>
    <div class="row">
      <img src="${escapeHtml(reporterAvatarUrl(ticket))}" alt="" width="36" height="36" loading="lazy" referrerpolicy="no-referrer" onerror="this.onerror=null;this.src='${escapeHtml(
        dicebearAvatar(ticket.reporter_username || display)
      )}'"/>
      <div>
        <div class="name">${escapeHtml(display)}</div>
        <div class="sub">${escapeHtml(handle)}${
          ticket.reporter_display_name && ticket.reporter_username
            ? ` · @${escapeHtml(ticket.reporter_username)}`
            : ''
        }</div>
      </div>
    </div>
    ${matchBanner}
  </div>`;
}

type MediaSource = {
  media_type: string | null;
  media_url: string | null;
  thumb_url: string | null;
  preview_media_url?: string | null;
  preview_body: string | null;
  preview_title: string | null;
  is_text_post: boolean;
  name_matches: string[];
};

function renderMedia(src: MediaSource): string {
  const mediaType = String(src.media_type || '').toLowerCase();
  const videoUrl = src.media_url;
  const thumb = src.thumb_url || '';
  const bodyText = String(src.preview_body || '').trim();
  const titleText = String(src.preview_title || '').trim();

  if (src.is_text_post || ((!videoUrl && !thumb) && (bodyText || titleText))) {
    if (mediaType === 'video' && !videoUrl && thumb) {
      return `<img class="media" src="${escapeHtml(thumb)}" alt="Video poster"/>`;
    }
    if (mediaType === 'image' && (videoUrl || thumb)) {
      // fall through to image
    } else if (!videoUrl && mediaType !== 'image') {
      const quote = highlightNames(
        bodyText || titleText || 'Empty text post',
        src.name_matches
      );
      return `
      <div class="text-post">
        <div class="eyebrow">Text post</div>
        <p class="quote">${quote}</p>
      </div>`;
    }
  }

  if ((mediaType === 'video' || (!mediaType && videoUrl)) && videoUrl && !String(videoUrl).trim().startsWith('{')) {
    const poster = thumb ? ` poster="${escapeHtml(thumb)}"` : '';
    return `<video class="media" src="${escapeHtml(videoUrl)}"${poster} controls playsinline preload="metadata"></video>`;
  }
  if (mediaType === 'video' && thumb) {
    return `<img class="media" src="${escapeHtml(thumb)}" alt="Video poster"/>`;
  }
  const img =
    src.thumb_url ||
    (mediaType === 'video' ? null : src.media_url) ||
    src.preview_media_url;
  if (img && !String(img).trim().startsWith('{')) {
    return `<img class="media" src="${escapeHtml(img)}" alt=""/>`;
  }
  if (bodyText || titleText) {
    const quote = highlightNames(
      bodyText || titleText || 'Empty text post',
      src.name_matches
    );
    return `
    <div class="text-post">
      <div class="eyebrow">Text post</div>
      <p class="quote">${quote}</p>
    </div>`;
  }
  return `<div class="media empty">No media preview</div>`;
}

function commentAvatarUrl(c: TicketCommentSnippet): string {
  const s =
    (c.author_avatar_seed || c.author_username || 'anonymous').trim() ||
    'anonymous';
  return durableAvatarUrl(c.author_avatar_url, s);
}

function renderThreadList(
  comments: TicketCommentSnippet[],
  emptyLabel: string
): string {
  if (!comments.length) {
    return `<div class="thread-empty">${escapeHtml(emptyLabel)}</div>`;
  }
  return `<div class="thread-list">${comments
    .map((c) => {
      const username = c.author_username || 'anonymous';
      const body = escapeHtml((c.body || '').slice(0, 600)) || '<span class="muted">Empty</span>';
      const avatar = commentAvatarUrl(c);
      return `
      <div class="thread-item">
        <img src="${escapeHtml(avatar)}" alt="" width="32" height="32" loading="lazy" referrerpolicy="no-referrer" onerror="this.onerror=null;this.src='${escapeHtml(
          dicebearAvatar(username)
        )}'"/>
        <div>
          <div class="who">@${escapeHtml(username)}</div>
          <div class="txt">${body}</div>
        </div>
      </div>`;
    })
    .join('')}</div>`;
}

function renderParentPost(parent: TicketParentPost, nameMatches: string[]): string {
  const username = parent.author_username || 'anonymous';
  const displayName = parent.author_display_name;
  const avatar = durableAvatarUrl(
    parent.author_avatar_url,
    (parent.author_avatar_seed || username).trim() || 'anonymous'
  );
  const titleRaw = parent.title || '';
  const bodyRaw = (parent.body || '').slice(0, 800);
  const showTitle = !parent.is_text_post || !!titleRaw;
  const showBody = !parent.is_text_post;
  const media = renderMedia({
    media_type: parent.media_type,
    media_url: parent.media_url,
    thumb_url: parent.thumb_url,
    preview_body: parent.body,
    preview_title: parent.title,
    is_text_post: parent.is_text_post,
    name_matches: nameMatches,
  });
  return `
  <div class="context-block">
    <div class="eyebrow">Parent post</div>
    <div class="author">
      <img src="${escapeHtml(avatar)}" alt="" width="44" height="44" loading="lazy" referrerpolicy="no-referrer" onerror="this.onerror=null;this.src='${escapeHtml(
        dicebearAvatar(username)
      )}'"/>
      <div class="who">
        <div class="name">@${escapeHtml(username)}${
          displayName && displayName !== username
            ? ` <span class="muted">· ${escapeHtml(displayName)}</span>`
            : ''
        }</div>
      </div>
    </div>
    ${showTitle && titleRaw ? `<h2>${highlightNames(titleRaw, nameMatches)}</h2>` : ''}
    ${showBody && bodyRaw ? `<p class="body">${highlightNames(bodyRaw, nameMatches)}</p>` : ''}
    ${media}
  </div>`;
}

function renderReportedPostBody(ticket: TicketDisplay): string {
  const titleRaw = ticket.preview_title || '';
  const bodyRaw = (ticket.preview_body || '').slice(0, 800);
  const title = highlightNames(
    titleRaw || (ticket.is_text_post ? '' : '(no title)'),
    ticket.name_matches
  );
  const body = bodyRaw
    ? highlightNames(bodyRaw, ticket.name_matches)
    : '<span class="muted">No body</span>';
  const showTitle = !ticket.is_text_post || !!titleRaw;
  const showBody = !ticket.is_text_post;
  const media = renderMedia({
    media_type: ticket.media_type,
    media_url: ticket.media_url,
    thumb_url: ticket.thumb_url,
    preview_media_url: ticket.preview_media_url,
    preview_body: ticket.preview_body,
    preview_title: ticket.preview_title,
    is_text_post: ticket.is_text_post,
    name_matches: ticket.name_matches,
  });
  return `
    ${showTitle && titleRaw ? `<h2>${title}</h2>` : ''}
    ${showBody ? `<p class="body">${body}</p>` : ''}
    ${media}`;
}

function renderReportedCommentBody(ticket: TicketDisplay): string {
  const bodyRaw = (ticket.preview_body || '').slice(0, 1200);
  const body = bodyRaw
    ? highlightNames(bodyRaw, ticket.name_matches)
    : '<span class="muted">Empty comment</span>';
  return `<p class="body">${body}</p>`;
}

function renderTicketCard(ticket: TicketDisplay): string {
  const cat = labelForCategory(ticket.category);
  const username = ticket.author_username || 'anonymous';
  const displayName = ticket.author_display_name;
  const avatar = avatarUrlFor(ticket);
  const sourcePill =
    ticket.source === 'auto'
      ? `<span class="pill auto">auto-detected</span>`
      : ticket.source === 'user'
        ? `<span class="pill">user report</span>`
        : `<span class="pill">${escapeHtml(ticket.source)}</span>`;
  const matchPill = ticket.name_matches.length
    ? `<span class="pill auto">name match</span>`
    : '';
  const reporter = renderReporter(ticket);
  const queueAbs = `https://api.matterya.com/reports?ticket=${encodeURIComponent(ticket.id)}`;
  const isComment = ticket.target_kind === 'comment';
  const reportedLabel = isComment ? 'Reported comment' : 'Reported post';
  const reportedInner = isComment
    ? renderReportedCommentBody(ticket)
    : renderReportedPostBody(ticket);

  const parentBlock =
    isComment && ticket.parent_post
      ? renderParentPost(ticket.parent_post, ticket.name_matches)
      : '';

  const commentsUnderPost =
    !isComment && ticket.context_comments
      ? `
    <div class="context-block">
      <div class="eyebrow">Comments on this post</div>
      ${renderThreadList(ticket.context_comments, 'No comments yet')}
    </div>`
      : '';

  const repliesUnderComment = isComment
    ? `
    <div class="context-block">
      <div class="eyebrow">Direct replies</div>
      ${renderThreadList(ticket.comment_replies || [], 'No replies')}
    </div>`
    : '';

  const authorBlock = `
    <div class="author">
      <img src="${escapeHtml(avatar)}" alt="" width="44" height="44" loading="lazy" referrerpolicy="no-referrer" onerror="this.onerror=null;this.src='${escapeHtml(
        dicebearAvatar(username)
      )}'"/>
      <div class="who">
        <div class="name">@${escapeHtml(username)}${
          displayName && displayName !== username
            ? ` <span class="muted">· ${escapeHtml(displayName)}</span>`
            : ''
        }</div>
        <div class="sub">${
          isComment ? 'comment author' : `${escapeHtml(ticket.platform)} · ${escapeHtml(ticket.target_kind)}`
        }</div>
      </div>
    </div>`;

  return `
  <article class="card">
    <div class="card-top">
      <div class="meta" style="margin:0">
        <span class="pill">${escapeHtml(cat)}</span>
        ${sourcePill}
        ${matchPill}
        <span class="muted">×${ticket.report_count} reports</span>
        <span class="muted">${escapeHtml(ticket.platform)} · ${escapeHtml(ticket.target_kind)}</span>
      </div>
      <button type="button" class="copy-link" id="copy-ticket-link" data-link="${escapeHtml(queueAbs)}" title="Copy ticket link">Copy link</button>
    </div>
    ${reporter}
    <div class="card-stack">
      ${parentBlock}
      <div class="reported">
        <div class="reported-label">${reportedLabel}</div>
        ${authorBlock}
        ${reportedInner}
      </div>
      ${commentsUnderPost}
      ${repliesUnderComment}
    </div>
  </article>

  <aside class="decision" id="decision-panel" data-ticket-id="${escapeHtml(ticket.id)}">
    <div class="step" id="decision-step">Step 1</div>
    <h2 id="decision-question">Loading…</h2>
    <div class="crumb" id="decision-crumbs"></div>
    <div class="options" id="decision-options"></div>
  </aside>`;
}

function renderEmpty(openCount: number, opts?: { waitingForOther?: boolean }): string {
  if (opts?.waitingForOther && openCount > 0) {
    return `
  <div class="card empty" style="grid-column:1/-1">
    <h2>Passed to another moderator</h2>
    <p class="muted">${openCount} still open for others. Your queue has nothing left you haven’t passed.</p>
  </div>`;
  }
  return `
  <div class="card empty" style="grid-column:1/-1">
    <h2>Queue clear</h2>
    <p class="muted">${
      openCount > 0
        ? `${openCount} open, but none could be claimed right now. Refresh shortly.`
        : 'No open tickets. Auto-detected and user reports will appear here.'
    }</p>
  </div>`;
}

export async function handleModerationQueueGet(req: Request, res: Response): Promise<void> {
  if (!hasReportsAccess(req)) {
    res.status(401).send(renderReportsLoginHtml({ next: '/reports' }));
    return;
  }
  if (String(req.query.tab || '') === 'analytics') {
    return handleReportsGet(req, res);
  }

  await ensureAutoTicketsFromFlaggedPosts();

  const actor = actorFromReq(req);
  const ticketParam = String(req.query.ticket || '').trim();
  const excludeParam = String(req.query.exclude || '').trim();
  let flash = String(req.query.flash || '') || null;
  // Keep "Passed to another moderator" when the queue has nothing else for this mod.
  if (flash && /^passed ·/i.test(flash)) flash = null;

  // Prefer deep-link only when it is not the ticket we just passed.
  const prefer =
    ticketParam &&
    /^[0-9a-f-]{36}$/i.test(ticketParam) &&
    ticketParam !== excludeParam
      ? ticketParam
      : null;

  const claimed = await ensureClaimedTicket(actor, {
    preferTicketId: prefer,
    excludeTicketId: excludeParam || null,
  });

  if (
    prefer &&
    (!claimed || claimed.id !== prefer)
  ) {
    flash = flash || 'Could not open that ticket (claimed, resolved, or missing)';
  }

  const openCount = await openTicketCount({ queue: 'content' });
  const waitingForOther = String(req.query.waiting || '') === '1';
  let body: string;
  let treeJson: string | undefined;
  if (claimed) {
    const display = await hydrateTicketDisplay(claimed);
    body = renderTicketCard(display);
    treeJson = JSON.stringify(policyTreeForClient()).replace(/</g, '\\u003c');
  } else {
    body = renderEmpty(openCount, { waitingForOther });
  }
  res.type('html').send(renderShell({ actor, openCount, body, flash, treeJson }));
}

export async function handleModerationClaim(req: Request, res: Response): Promise<void> {
  if (!hasReportsAccess(req)) {
    res.status(401).send(renderReportsLoginHtml({ next: '/reports' }));
    return;
  }
  res.redirect(303, '/reports');
}

export async function handleModerationTicketAction(req: Request, res: Response): Promise<void> {
  if (!hasReportsAccess(req)) {
    res.status(401).send(renderReportsLoginHtml({ next: '/reports' }));
    return;
  }
  const actor = actorFromReq(req);
  const ticketId = String(req.body?.ticket_id || '').trim();
  const action = String(req.body?.action || '').trim();
  if (!ticketId) {
    res.redirect(303, '/reports?flash=Missing+ticket');
    return;
  }

  if (action === 'release') {
    const released = await releaseTicket(ticketId, actor, {
      force: true,
      passToOther: true,
    });
    // Passed ticket is marked for another moderator; claim a different one.
    const next = await claimNextTicket(actor, {
      excludeTicketId: ticketId,
      queue: 'content',
    });
    if (next && next.id !== ticketId) {
      res.redirect(
        303,
        `/reports?ticket=${encodeURIComponent(next.id)}&exclude=${encodeURIComponent(ticketId)}`
      );
      return;
    }
    // Nothing else for this moderator (remaining items were passed by them).
    res.redirect(
      303,
      released
        ? `/reports?exclude=${encodeURIComponent(ticketId)}&waiting=1`
        : '/reports'
    );
    return;
  }

  // Policy decision: leaf id → automatic remove/mark/dismiss (hidden from mod).
  if (action === 'decide') {
    const leafId = String(req.body?.leaf_id || '').trim();
    const leaf = getPolicyLeaf(leafId);
    if (!leaf) {
      res.redirect(303, '/reports?flash=Unknown+decision');
      return;
    }
    const resolveAction = outcomeToResolveAction(leaf.outcome);
    const result = await resolveTicket({
      ticketId,
      actor,
      action: resolveAction,
      category: resolveAction === 'skip' ? null : leaf.root,
      // Leaf path for audit; outcome is applied by policy (not shown in UI flash).
      note: `policy:${leaf.id}|outcome:${leaf.outcome}|${leaf.label}`,
      leafId: leaf.id,
    });
    if (!result.ok) {
      res.redirect(303, `/reports?flash=${encodeURIComponent(result.error || 'failed')}`);
      return;
    }
    // Never tell the moderator whether content was removed or marked.
    const next = await claimNextTicket(actor, { queue: 'content' });
    const flash = 'Decision recorded';
    if (next) {
      res.redirect(
        303,
        `/reports?ticket=${encodeURIComponent(next.id)}&flash=${encodeURIComponent(flash)}`
      );
      return;
    }
    res.redirect(303, `/reports?flash=${encodeURIComponent(flash)}`);
    return;
  }

  res.redirect(303, '/reports?flash=Unknown+action');
}

export { REPORTS_PAGE_PASSWORD };
