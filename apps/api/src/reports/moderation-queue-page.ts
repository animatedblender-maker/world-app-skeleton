/**
 * Unified Matterya moderation queue — one ticket at a time (auto-claim).
 * https://api.matterya.com/reports
 *
 * Remove as <category> → archive + delete live
 * Mark as <category>   → stay live + tagged
 * Ignore               → dismiss (false positive)
 */
import type { Request, Response } from 'express';
import {
  hasReportsAccess,
  renderReportsLoginHtml,
  REPORTS_PAGE_PASSWORD,
} from './reports-page.js';
import { MODERATION_CATEGORIES, labelForCategory } from '../moderation/categories.js';
import {
  claimNextTicket,
  claimTicketById,
  ensureAutoTicketsFromFlaggedPosts,
  getClaimedTicketForActor,
  hydrateTicketDisplay,
  openTicketCount,
  releaseTicket,
  resolveTicket,
  type TicketDisplay,
  type TicketRow,
} from '../moderation/tickets.js';
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
  // Cookie session is shared; use a stable device hint until named mod accounts.
  const ua = String(req.headers['user-agent'] ?? 'mod').slice(0, 40);
  return `mod:${Buffer.from(ua).toString('base64url').slice(0, 24)}`;
}

function categoryOptionsHtml(): string {
  return MODERATION_CATEGORIES.map(
    (c) => `<option value="${escapeHtml(c.slug)}">${escapeHtml(c.label)}</option>`
  ).join('\n');
}

/** Prefer stored avatar URL; otherwise Dicebear from seed / username. */
function avatarUrlFor(ticket: TicketDisplay): string {
  const direct = String(ticket.author_avatar_url || '').trim();
  if (direct.startsWith('http')) return direct;
  const s =
    (ticket.author_avatar_seed || ticket.author_username || 'anonymous').trim() ||
    'anonymous';
  return `https://api.dicebear.com/7.x/shapes/svg?seed=${encodeURIComponent(s)}`;
}

async function ensureClaimedTicket(
  actor: string,
  opts?: { excludeTicketId?: string | null; preferTicketId?: string | null }
): Promise<TicketRow | null> {
  const prefer = opts?.preferTicketId?.trim() || null;
  if (prefer && /^[0-9a-f-]{36}$/i.test(prefer)) {
    const result = await claimTicketById(prefer, actor);
    if (result.ok && result.ticket) return result.ticket;
  }

  const existing = await getClaimedTicketForActor(actor);
  if (existing) {
    if (opts?.excludeTicketId && existing.id === opts.excludeTicketId) {
      // fall through to claim another
    } else {
      return existing;
    }
  }
  return claimNextTicket(actor, { excludeTicketId: opts?.excludeTicketId });
}

function renderShell(opts: {
  actor: string;
  openCount: number;
  body: string;
  flash?: string | null;
}): string {
  const flash = opts.flash
    ? `<p class="flash">${escapeHtml(opts.flash)}</p>`
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
    padding: 16px 20px; display: flex; flex-wrap: wrap; gap: 12px 18px; align-items: center;
  }
  .mark {
    font-size: 11px; font-weight: 700; letter-spacing: .2em;
    text-transform: uppercase; color: var(--accent);
  }
  h1 {
    margin: 0; font-size: 1.35rem; font-weight: 500;
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
  main { max-width: 720px; margin: 0 auto; padding: 24px 16px 64px; }
  .card {
    background: var(--surface); border: 1px solid var(--border); border-radius: 16px;
    padding: 18px; display: grid; gap: 14px;
    box-shadow: 0 10px 28px rgba(44,40,37,.06);
  }
  .author { display: flex; align-items: center; gap: 12px; }
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
  .meta { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
  h2 { margin: 0; font-size: 1.15rem; line-height: 1.35; font-weight: 600; }
  .body { margin: 0; color: var(--muted); white-space: pre-wrap; line-height: 1.45; }
  .media {
    width: 100%; max-height: 480px; border-radius: 12px;
    background: #111; object-fit: contain; display: block;
  }
  video.media { max-height: 520px; }
  .media.empty {
    height: 120px; display: grid; place-items: center; color: var(--muted);
    background: #f3efe8;
  }
  .actions { display: grid; gap: 10px; margin-top: 4px; }
  .row { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
  select, button {
    font: inherit; border-radius: 999px; border: 1px solid var(--border);
    padding: .55rem .95rem; background: #fff; color: var(--ink);
  }
  button { cursor: pointer; font-weight: 650; }
  button.primary { background: var(--accent); color: #fff; border-color: transparent; }
  button.danger { background: var(--danger); color: #fff; border-color: transparent; }
  button.ghost { background: #efe8dc; color: var(--ink); }
  .flash {
    background: #dcfce7; border: 1px solid #bbf7d0; color: var(--ok);
    padding: 10px 12px; border-radius: 10px;
  }
  .empty { text-align: center; padding: 48px 16px; }
  .ids {
    display: grid; gap: 6px; padding: 10px 12px; border-radius: 10px;
    background: #f3efe8; border: 1px solid var(--border); font-size: .78rem;
  }
  .ids .row-id {
    display: grid; grid-template-columns: 88px 1fr; gap: 8px; align-items: start;
  }
  .ids .lbl { color: var(--muted); }
  .ids code, .ids a {
    color: var(--accent); word-break: break-all; font-size: .76rem;
  }
  .ids a { text-decoration: none; }
  .ids a:hover { text-decoration: underline; }
</style>
</head>
<body>
<header>
  <div class="header-copy">
    <div class="mark">Matterya</div>
    <h1>Moderation</h1>
  </div>
  <span class="pill ok">${opts.openCount} open</span>
  <span class="muted">Auto queue · one ticket at a time</span>
  <span style="flex:1"></span>
  <a class="nav" href="/reports/analytics">Insights</a>
  <a class="nav" href="/reports/masquerade">Masquerade (legacy)</a>
  <a class="nav" href="/reports/logout">Log out</a>
</header>
<main>
  ${flash}
  ${opts.body}
  <p class="muted" style="margin-top:24px">Signed in as <code>${escapeHtml(opts.actor)}</code></p>
</main>
</body>
</html>`;
}

function renderMedia(ticket: TicketDisplay): string {
  const mediaType = String(ticket.media_type || '').toLowerCase();
  const videoUrl = ticket.media_url;
  const thumb = ticket.thumb_url || '';

  if (mediaType === 'video' && videoUrl) {
    const poster = thumb ? ` poster="${escapeHtml(thumb)}"` : '';
    return `<video class="media" src="${escapeHtml(videoUrl)}"${poster} controls playsinline preload="metadata"></video>`;
  }
  if (mediaType === 'video' && thumb) {
    return `<img class="media" src="${escapeHtml(thumb)}" alt="Video poster"/>`;
  }
  const img =
    ticket.thumb_url ||
    (mediaType === 'video' ? null : ticket.media_url) ||
    ticket.preview_media_url;
  if (img) {
    return `<img class="media" src="${escapeHtml(img)}" alt=""/>`;
  }
  return `<div class="media empty">No media preview</div>`;
}

function renderTicketCard(ticket: TicketDisplay): string {
  const cat = labelForCategory(ticket.category);
  const title = escapeHtml(ticket.preview_title || '(no title)');
  const body = escapeHtml((ticket.preview_body || '').slice(0, 600));
  const username = ticket.author_username || 'anonymous';
  const avatar = avatarUrlFor(ticket);
  const sourcePill =
    ticket.source === 'auto'
      ? `<span class="pill auto">auto-detected</span>`
      : `<span class="pill">${escapeHtml(ticket.source)}</span>`;
  const opts = categoryOptionsHtml();
  const media = renderMedia(ticket);
  const queuePath = `/reports?ticket=${encodeURIComponent(ticket.id)}`;
  const queueAbs = `https://api.matterya.com${queuePath}`;
  const spaceLine =
    ticket.space_slug || ticket.space_title
      ? `<div class="row-id"><span class="lbl">Space</span><code>${escapeHtml(
          ticket.space_title || ticket.space_slug || ''
        )}${ticket.space_slug ? ` (${escapeHtml(ticket.space_slug)})` : ''}</code></div>`
      : '';
  const authorIdLine = ticket.author_profile_id
    ? `<div class="row-id"><span class="lbl">Author id</span><code>${escapeHtml(ticket.author_profile_id)}</code></div>`
    : '';
  const flagLine = ticket.flag_reason
    ? `<div class="row-id"><span class="lbl">Flag</span><code>${escapeHtml(ticket.flag_reason)}</code></div>`
    : '';

  return `
  <article class="card">
    <div class="author">
      <img src="${escapeHtml(avatar)}" alt="" width="44" height="44"/>
      <div class="who">
        <div class="name">@${escapeHtml(username)}</div>
        <div class="sub">${escapeHtml(ticket.platform)} · ${escapeHtml(ticket.target_kind)}</div>
      </div>
    </div>
    <div class="meta">
      <span class="pill">${escapeHtml(cat)}</span>
      ${sourcePill}
      <span class="muted">×${ticket.report_count} reports</span>
    </div>
    <h2>${title}</h2>
    <p class="body">${body || '<span class="muted">No body</span>'}</p>
    ${media}
    <div class="ids">
      <div class="row-id"><span class="lbl">Queue link</span><a href="${escapeHtml(queuePath)}">${escapeHtml(queueAbs)}</a></div>
      <div class="row-id"><span class="lbl">Ticket id</span><code>${escapeHtml(ticket.id)}</code></div>
      <div class="row-id"><span class="lbl">Post id</span><code>${escapeHtml(ticket.target_id)}</code></div>
      ${authorIdLine}
      ${spaceLine}
      ${flagLine}
    </div>

    <form class="actions" method="post" action="/reports/ticket/action">
      <input type="hidden" name="ticket_id" value="${escapeHtml(ticket.id)}"/>
      <div class="row">
        <label class="muted">Category</label>
        <select name="category" required>${opts}</select>
      </div>
      <div class="row">
        <button class="danger" name="action" value="remove" type="submit">Remove as…</button>
        <button class="primary" name="action" value="mark" type="submit">Mark as…</button>
        <button class="ghost" name="action" value="ignore" type="submit">Ignore</button>
        <button class="ghost" name="action" value="release" type="submit">Release</button>
      </div>
    </form>
  </article>`;
}

function renderEmpty(openCount: number): string {
  return `
  <div class="card empty">
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
  let flash = String(req.query.flash || '') || null;

  const claimed = await ensureClaimedTicket(actor, {
    preferTicketId: ticketParam || null,
  });

  if (ticketParam && /^[0-9a-f-]{36}$/i.test(ticketParam) && (!claimed || claimed.id !== ticketParam)) {
    flash = flash || 'Could not open that ticket (claimed, resolved, or missing)';
  }

  const openCount = await openTicketCount();
  let body: string;
  if (claimed) {
    const display = await hydrateTicketDisplay(claimed);
    body = renderTicketCard(display);
  } else {
    body = renderEmpty(openCount);
  }
  res.type('html').send(renderShell({ actor, openCount, body, flash }));
}

export async function handleModerationClaim(req: Request, res: Response): Promise<void> {
  if (!hasReportsAccess(req)) {
    res.status(401).send(renderReportsLoginHtml({ next: '/reports' }));
    return;
  }
  // Claim-next is automatic on GET /reports — keep POST as a redirect for old forms.
  res.redirect(303, '/reports');
}

export async function handleModerationTicketAction(req: Request, res: Response): Promise<void> {
  if (!hasReportsAccess(req)) {
    res.status(401).send(renderReportsLoginHtml({ next: '/reports' }));
    return;
  }
  const actor = actorFromReq(req);
  const ticketId = String(req.body?.ticket_id || '').trim();
  let action = String(req.body?.action || '').trim();
  const category = String(req.body?.category || '').trim();
  if (action === 'ignore') action = 'skip';
  if (!ticketId) {
    res.redirect(303, '/reports?flash=Missing+ticket');
    return;
  }
  if (action === 'release') {
    await releaseTicket(ticketId, actor);
    const next = await claimNextTicket(actor, { excludeTicketId: ticketId });
    if (next) {
      res.redirect(
        303,
        `/reports?ticket=${encodeURIComponent(next.id)}&flash=${encodeURIComponent('Released · next ticket loaded')}`
      );
      return;
    }
    res.redirect(303, '/reports?flash=Released');
    return;
  }
  if (action !== 'remove' && action !== 'mark' && action !== 'skip') {
    res.redirect(303, '/reports?flash=Unknown+action');
    return;
  }
  const result = await resolveTicket({
    ticketId,
    actor,
    action,
    category: action === 'skip' ? null : category,
  });
  if (!result.ok) {
    res.redirect(303, `/reports?flash=${encodeURIComponent(result.error || 'failed')}`);
    return;
  }
  const label =
    action === 'skip'
      ? 'Ignored'
      : action === 'remove'
        ? `Removed as ${labelForCategory(category)}`
        : `Marked as ${labelForCategory(category)}`;
  // Auto-load the next ticket.
  const next = await claimNextTicket(actor);
  if (next) {
    res.redirect(
      303,
      `/reports?ticket=${encodeURIComponent(next.id)}&flash=${encodeURIComponent(label)}`
    );
    return;
  }
  res.redirect(303, `/reports?flash=${encodeURIComponent(label)}`);
}

export { REPORTS_PAGE_PASSWORD };
