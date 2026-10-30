/**
 * Unified Matterya moderation queue — one ticket at a time (Claim next).
 * https://api.matterya.com/reports
 *
 * Remove as <category> → archive + delete live
 * Mark as <category>   → stay live + tagged
 * Skip                 → dismiss
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
  ensureAutoTicketsFromFlaggedPosts,
  getClaimedTicketForActor,
  hydrateTicketDisplay,
  openTicketCount,
  releaseTicket,
  resolveTicket,
  type TicketDisplay,
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

function categoryOptionsHtml(name: string): string {
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
    --bg: #070b10; --card: #121a24; --line: #243041; --text: #e8eef7;
    --muted: #8fa3b8; --accent: #5eead4; --danger: #f87171; --ok: #34d399;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
    background: radial-gradient(900px 500px at 10% -10%, #132033 0%, var(--bg) 55%);
    color: var(--text); min-height: 100vh;
  }
  header {
    position: sticky; top: 0; z-index: 5;
    backdrop-filter: blur(12px); background: rgba(7,11,16,.88);
    border-bottom: 1px solid var(--line);
    padding: 12px 18px; display: flex; flex-wrap: wrap; gap: 12px 18px; align-items: center;
  }
  h1 { font-size: 1.05rem; margin: 0; font-weight: 650; }
  .muted { color: var(--muted); font-size: .85rem; }
  .pill {
    display: inline-flex; align-items: center; gap: 6px;
    padding: .2rem .65rem; border-radius: 999px; font-size: .75rem; font-weight: 600;
    background: #1a2433; color: var(--muted); border: 1px solid var(--line);
  }
  .pill.ok { color: var(--ok); border-color: #14532d; background: #052e1a; }
  .pill.auto { color: #fbbf24; border-color: #78350f; background: #1c1408; }
  a.nav { color: var(--accent); text-decoration: none; font-size: .85rem; }
  main { max-width: 720px; margin: 0 auto; padding: 24px 16px 64px; }
  .card {
    background: var(--card); border: 1px solid var(--line); border-radius: 16px;
    padding: 18px; display: grid; gap: 14px;
  }
  .author {
    display: flex; align-items: center; gap: 12px;
  }
  .author img {
    width: 44px; height: 44px; border-radius: 50%;
    background: #0a1018; border: 1px solid var(--line); object-fit: cover;
  }
  .author .who { display: grid; gap: 2px; min-width: 0; }
  .author .name {
    font-weight: 650; font-size: .95rem; line-height: 1.2;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  }
  .author .sub { color: var(--muted); font-size: .78rem; }
  .meta { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
  h2 { margin: 0; font-size: 1.15rem; line-height: 1.35; }
  .body { margin: 0; color: var(--muted); white-space: pre-wrap; }
  .media {
    width: 100%; max-height: 480px; border-radius: 12px;
    background: #0a1018; object-fit: contain; display: block;
  }
  video.media { max-height: 520px; background: #000; }
  .media.empty { height: 120px; display: grid; place-items: center; color: var(--muted); }
  .actions { display: grid; gap: 10px; margin-top: 4px; }
  .row { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
  select, button {
    font: inherit; border-radius: 10px; border: 1px solid var(--line);
    padding: .55rem .85rem; background: #0e1620; color: var(--text);
  }
  button { cursor: pointer; font-weight: 600; }
  button.primary { background: var(--accent); color: #042f2e; border-color: transparent; }
  button.danger { background: #3f1d1d; color: var(--danger); border-color: #7f1d1d; }
  button.ghost { background: transparent; }
  .flash { background: #052e1a; border: 1px solid #14532d; color: var(--ok);
    padding: 10px 12px; border-radius: 10px; }
  .empty { text-align: center; padding: 48px 16px; }
  .empty button { margin-top: 16px; }
</style>
</head>
<body>
<header>
  <h1>Matterya moderation</h1>
  <span class="pill ok">${opts.openCount} open</span>
  <span class="muted">One ticket at a time · Claim next</span>
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
  // Poster must be an image — never reuse the video URL.
  const thumb = ticket.thumb_url || '';

  if (mediaType === 'video' && videoUrl) {
    const poster = thumb ? ` poster="${escapeHtml(thumb)}"` : '';
    return `<video class="media" src="${escapeHtml(videoUrl)}"${poster} controls playsinline preload="metadata"></video>`;
  }
  if (mediaType === 'video' && thumb) {
    return `<img class="media" src="${escapeHtml(thumb)}" alt="Video poster"/>`;
  }
  const img = ticket.thumb_url || (mediaType === 'video' ? null : ticket.media_url) || ticket.preview_media_url;
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
  const opts = categoryOptionsHtml('category');
  const media = renderMedia(ticket);

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
    <p class="muted">Ticket <code>${escapeHtml(ticket.id.slice(0, 8))}</code> · target <code>${escapeHtml(ticket.target_id.slice(0, 8))}</code></p>

    <form class="actions" method="post" action="/reports/ticket/action">
      <input type="hidden" name="ticket_id" value="${escapeHtml(ticket.id)}"/>
      <div class="row">
        <label class="muted">Category</label>
        <select name="category" required>${opts}</select>
      </div>
      <div class="row">
        <button class="danger" name="action" value="remove" type="submit">Remove as…</button>
        <button class="primary" name="action" value="mark" type="submit">Mark as…</button>
        <button class="ghost" name="action" value="skip" type="submit">Skip</button>
        <button class="ghost" name="action" value="release" type="submit">Release</button>
      </div>
    </form>
  </article>`;
}

function renderEmpty(openCount: number): string {
  return `
  <div class="card empty">
    <h2>No ticket claimed</h2>
    <p class="muted">${openCount} open in the pool. Claim one to review.</p>
    <form method="post" action="/reports/claim">
      <button class="primary" type="submit">Claim next</button>
    </form>
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

  // Heal historical flagged posts that never got Claim-next tickets.
  await ensureAutoTicketsFromFlaggedPosts();

  const actor = actorFromReq(req);
  const [claimed, openCount] = await Promise.all([
    getClaimedTicketForActor(actor),
    openTicketCount(),
  ]);
  const flash = String(req.query.flash || '') || null;
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
  await ensureAutoTicketsFromFlaggedPosts();
  const actor = actorFromReq(req);
  const existing = await getClaimedTicketForActor(actor);
  if (!existing) {
    await claimNextTicket(actor);
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
  const category = String(req.body?.category || '').trim();
  if (!ticketId) {
    res.redirect(303, '/reports?flash=Missing+ticket');
    return;
  }
  if (action === 'release') {
    await releaseTicket(ticketId, actor);
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
      ? 'Skipped'
      : action === 'remove'
        ? `Removed as ${labelForCategory(category)}`
        : `Marked as ${labelForCategory(category)}`;
  res.redirect(303, `/reports?flash=${encodeURIComponent(label)}`);
}

export { REPORTS_PAGE_PASSWORD };
