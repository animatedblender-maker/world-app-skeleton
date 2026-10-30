/**
 * Account strike queue — Claim-next for queue=account tickets.
 * https://api.matterya.com/reports/accounts
 */
import type { Request, Response } from 'express';
import {
  hasReportsAccess,
  renderReportsLoginHtml,
} from './reports-page.js';
import { labelForCategory } from '../moderation/categories.js';
import {
  claimNextTicket,
  claimTicketById,
  ensureTicketsSchema,
  getClaimedTicketForActor,
  openTicketCount,
  releaseTicket,
  resolveTicket,
  type TicketRow,
} from '../moderation/tickets.js';
import {
  clearOpenStrikes,
  listOpenStrikes,
  type StrikeSubjectKind,
} from '../moderation/enforcement.js';
import { pool } from '../db.js';
import { createAnonymousNotification } from '../anonymous/notifications.js';
import { NotificationsService } from '../graphql/modules/notifications/notifications.service.js';

const feedNotify = new NotificationsService();

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

function dicebearAvatar(seed: string): string {
  const s = seed.trim() || 'anonymous';
  return `https://api.dicebear.com/7.x/shapes/svg?seed=${encodeURIComponent(s)}`;
}

type AccountDisplay = TicketRow & {
  subject_kind: StrikeSubjectKind;
  username: string | null;
  display_name: string | null;
  avatar_url: string | null;
  avatar_seed: string | null;
  account_status: string | null;
  strikes: Array<{
    id: string;
    leaf_id: string;
    root_category: string;
    severity: string;
    source_ticket_id: string | null;
    created_at: string;
  }>;
};

async function hydrateAccountTicket(ticket: TicketRow): Promise<AccountDisplay> {
  const subjectKind: StrikeSubjectKind =
    ticket.platform === 'masquerade' ? 'anonymous_profile' : 'user';
  const base: AccountDisplay = {
    ...ticket,
    subject_kind: subjectKind,
    username: null,
    display_name: null,
    avatar_url: null,
    avatar_seed: null,
    account_status: null,
    strikes: [],
  };

  try {
    if (subjectKind === 'anonymous_profile') {
      const { rows } = await pool.query<{
        username: string | null;
        avatar_seed: string | null;
      }>(
        `
        select username, avatar_seed
        from anonymous.profiles
        where id = $1::uuid
        limit 1
        `,
        [ticket.target_id]
      );
      if (rows[0]) {
        base.username = rows[0].username;
        base.display_name = rows[0].username;
        base.avatar_seed = rows[0].avatar_seed || rows[0].username;
      }
    } else {
      const { rows } = await pool.query<{
        username: string | null;
        display_name: string | null;
        avatar_url: string | null;
        account_status: string | null;
      }>(
        `
        select username, display_name, avatar_url, account_status
        from public.profiles
        where user_id = $1::uuid
        limit 1
        `,
        [ticket.target_id]
      );
      if (rows[0]) {
        base.username = rows[0].username;
        base.display_name = rows[0].display_name;
        base.avatar_url = rows[0].avatar_url;
        base.avatar_seed = rows[0].username || rows[0].display_name;
        base.account_status = rows[0].account_status;
      }
    }
  } catch (err: any) {
    console.warn('[account-queue] hydrate profile', err?.message ?? err);
  }

  try {
    base.strikes = await listOpenStrikes(subjectKind, ticket.target_id, 5);
  } catch (err: any) {
    console.warn('[account-queue] list strikes', err?.message ?? err);
  }

  return base;
}

async function ensureClaimedAccountTicket(
  actor: string,
  opts?: { excludeTicketId?: string | null; preferTicketId?: string | null }
): Promise<TicketRow | null> {
  await ensureTicketsSchema();
  const prefer = opts?.preferTicketId?.trim() || null;
  if (prefer && /^[0-9a-f-]{36}$/i.test(prefer)) {
    const result = await claimTicketById(prefer, actor);
    if (result.ok && result.ticket && result.ticket.queue === 'account') {
      return result.ticket;
    }
  }
  const existing = await getClaimedTicketForActor(actor, { queue: 'account' });
  if (existing) {
    if (opts?.excludeTicketId && existing.id === opts.excludeTicketId) {
      // fall through
    } else {
      return existing;
    }
  }
  return claimNextTicket(actor, {
    excludeTicketId: opts?.excludeTicketId,
    queue: 'account',
  });
}

function renderShell(opts: {
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
<title>Matterya · Account review</title>
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
  h1 { margin: 0; font-size: 1.3rem; font-weight: 500; font-family: ui-serif, Georgia, serif; }
  .muted { color: var(--muted); font-size: .85rem; }
  .pill {
    display: inline-flex; align-items: center; gap: 6px;
    padding: .2rem .65rem; border-radius: 999px; font-size: .75rem; font-weight: 700;
    background: #f3e8d8; color: var(--accent); border: 1px solid #e8dcc8;
  }
  .pill.ok { color: var(--ok); border-color: #bbf7d0; background: #dcfce7; }
  .pill.danger { color: var(--danger); border-color: #fecaca; background: #fef2f2; }
  .pill.severe { color: #9a3412; border-color: #fdba74; background: #fff7ed; }
  a.nav { color: var(--accent); text-decoration: none; font-size: .85rem; margin-left: 10px; }
  a.nav:hover { text-decoration: underline; }
  main.layout {
    max-width: 980px; margin: 0 auto; padding: 20px 16px 64px;
    display: grid; grid-template-columns: minmax(0, 1.1fr) minmax(280px, 0.9fr);
    gap: 18px; align-items: start;
  }
  @media (max-width: 860px) { main.layout { grid-template-columns: 1fr; } }
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
  .author { display: flex; align-items: center; gap: 12px; }
  .author img {
    width: 52px; height: 52px; border-radius: 50%;
    background: #efe8dc; border: 1px solid var(--border); object-fit: cover;
  }
  .author .name { font-weight: 650; font-size: 1rem; }
  .strikes { display: grid; gap: 8px; }
  .strike {
    border: 1px solid var(--border); border-radius: 10px; padding: 10px 12px;
    background: var(--wash); display: grid; gap: 4px;
  }
  .strike .leaf { font-family: ui-monospace, Menlo, monospace; font-size: .78rem; }
  .decision {
    background: var(--surface); border: 1px solid var(--border); border-radius: 16px;
    padding: 16px; box-shadow: 0 10px 28px rgba(44,40,37,.06);
    display: grid; gap: 10px; position: sticky; top: 78px;
  }
  .decision h2 { margin: 0; font-family: ui-serif, Georgia, serif; font-weight: 500; font-size: 1.15rem; }
  .opt {
    display: flex; gap: 10px; align-items: flex-start; width: 100%;
    text-align: left; cursor: pointer; border: 1px solid var(--border);
    background: #fff; border-radius: 12px; padding: 10px 12px;
    font: inherit; color: var(--ink);
  }
  .opt:hover { border-color: var(--accent); }
  .opt .k {
    flex: 0 0 auto; min-width: 28px; height: 28px; border-radius: 8px;
    display: grid; place-items: center; font-weight: 800; font-size: .85rem;
    background: var(--key); color: var(--accent); border: 1px solid #e8dcc8;
  }
  .hint { font-size: .78rem; color: var(--muted); line-height: 1.4; }
  .empty { text-align: center; padding: 48px 16px; grid-column: 1 / -1; }
</style>
</head>
<body>
<header>
  <div>
    <div class="mark">Matterya</div>
    <h1>Account review</h1>
  </div>
  <span class="pill ok">${opts.openCount} open</span>
  <span class="muted">Strikes &amp; account actions</span>
  <span style="flex:1"></span>
  <a class="nav" href="/reports">Content queue</a>
  <a class="nav" href="/reports/analytics">Insights</a>
  <a class="nav" href="/reports/logout">Log out</a>
</header>
<main class="layout">
  ${flash}
  ${opts.body}
</main>
<script>
(function () {
  var form = document.getElementById('account-action-form');
  if (!form) return;
  var actionInput = document.getElementById('account-action-value');
  form.addEventListener('click', function (e) {
    var btn = e.target && e.target.closest ? e.target.closest('[data-action]') : null;
    if (!btn || !actionInput) return;
    actionInput.value = btn.getAttribute('data-action') || '';
  });
  document.addEventListener('keydown', function (e) {
    if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
    var map = { '1': 'clear', '2': 'warn', '3': 'restrict', '4': 'suspend', 'p': 'pass', 'P': 'pass' };
    var action = map[e.key];
    if (!action || !actionInput) return;
    e.preventDefault();
    actionInput.value = action;
    form.submit();
  });
})();
</script>
</body>
</html>`;
}

function renderAccountCard(d: AccountDisplay): string {
  const seed = d.avatar_seed || d.username || d.target_id;
  const avatar = d.avatar_url || dicebearAvatar(seed || 'account');
  const handle = d.username ? `@${d.username}` : d.target_id.slice(0, 8);
  const cat = labelForCategory(d.category);
  const strikeCount = d.strikes.length;
  const strikesHtml = d.strikes.length
    ? d.strikes
        .map(
          (s) => `
      <div class="strike">
        <div class="meta">
          <span class="pill ${s.severity === 'severe' ? 'severe' : ''}">${escapeHtml(s.severity)}</span>
          <span class="pill">${escapeHtml(labelForCategory(s.root_category))}</span>
          <span class="muted">${escapeHtml(String(s.created_at).slice(0, 19))}</span>
        </div>
        <div class="leaf">${escapeHtml(s.leaf_id)}</div>
        ${
          s.source_ticket_id
            ? `<div class="muted">content ticket ${escapeHtml(s.source_ticket_id.slice(0, 8))}…</div>`
            : ''
        }
      </div>`
        )
        .join('')
    : `<p class="muted">No open strikes listed (ticket may be from a prior escalation).</p>`;

  return `
  <article class="card">
    <div class="author">
      <img src="${escapeHtml(avatar)}" alt="" width="52" height="52" loading="lazy" referrerpolicy="no-referrer"
        onerror="this.onerror=null;this.src='${escapeHtml(dicebearAvatar(seed || 'account'))}'"/>
      <div>
        <div class="name">${escapeHtml(handle)}${
          d.display_name && d.display_name !== d.username
            ? ` <span class="muted">· ${escapeHtml(d.display_name)}</span>`
            : ''
        }</div>
        <div class="muted">${escapeHtml(d.platform)} · ${escapeHtml(d.subject_kind)}${
          d.account_status ? ` · ${escapeHtml(d.account_status)}` : ''
        }</div>
      </div>
    </div>
    <div class="meta" style="display:flex;flex-wrap:wrap;gap:8px">
      <span class="pill">${escapeHtml(cat)}</span>
      <span class="pill ${strikeCount >= 3 ? 'danger' : ''}">${strikeCount} open strike${strikeCount === 1 ? '' : 's'}</span>
    </div>
    <p class="body" style="margin:0;color:var(--muted);white-space:pre-wrap">${escapeHtml(
      d.preview_body || d.preview_title || ''
    )}</p>
    <div class="strikes">
      <div class="muted" style="font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--accent)">Recent strikes</div>
      ${strikesHtml}
    </div>
  </article>

  <aside class="decision">
    <div class="muted" style="font-size:11px;font-weight:700;letter-spacing:.12em;text-transform:uppercase;color:var(--accent)">Account action</div>
    <h2>What should happen to this account?</h2>
    <form id="account-action-form" method="post" action="/reports/accounts/action" class="options" style="display:grid;gap:8px">
      <input type="hidden" name="ticket_id" value="${escapeHtml(d.id)}"/>
      <input type="hidden" name="action" id="account-action-value" value=""/>
      <button type="submit" class="opt" data-action="clear">
        <span class="k">1</span><span>Clear strikes — no account action</span>
      </button>
      <button type="submit" class="opt" data-action="warn">
        <span class="k">2</span><span>Warn account (notify only)</span>
      </button>
      <button type="submit" class="opt" data-action="restrict">
        <span class="k">3</span><span>Temporary restrict (record + notify)</span>
      </button>
      <button type="submit" class="opt" data-action="suspend">
        <span class="k">4</span><span>Suspend / deactivate account</span>
      </button>
      <button type="submit" class="opt" data-action="pass">
        <span class="k">P</span><span>Pass to another moderator</span>
      </button>
    </form>
    <p class="hint">Keys <kbd>1</kbd>–<kbd>4</kbd> and <kbd>P</kbd>. Flash stays generic — policy outcomes stay hidden from the content queue.</p>
  </aside>`;
}

function renderEmpty(openCount: number): string {
  return `
  <div class="card empty">
    <h2>Account queue clear</h2>
    <p class="muted">${
      openCount > 0
        ? `${openCount} open, but none could be claimed right now.`
        : 'No account tickets. Severe removes and 3-strike escalations appear here.'
    }</p>
  </div>`;
}

async function applyAccountDecision(opts: {
  ticket: TicketRow;
  actor: string;
  action: 'clear' | 'warn' | 'restrict' | 'suspend';
}): Promise<void> {
  const subjectKind: StrikeSubjectKind =
    opts.ticket.platform === 'masquerade' ? 'anonymous_profile' : 'user';
  const subjectId = opts.ticket.target_id;

  if (opts.action === 'clear' || opts.action === 'warn' || opts.action === 'restrict') {
    await clearOpenStrikes({
      subjectKind,
      subjectId,
      clearedBy: opts.actor,
      note: `account_queue:${opts.action}`,
    });
  }

  if (opts.action === 'warn' || opts.action === 'restrict') {
    const body =
      opts.action === 'warn'
        ? 'Matterya reviewed your account. Please follow the community guidelines.'
        : 'Matterya placed a temporary restriction on your account after repeated removals.';
    if (subjectKind === 'user') {
      await feedNotify.notifyModerationRemoval(subjectId, {
        entityType: 'profile',
        entityId: subjectId,
        rootLabel: opts.action === 'warn' ? 'account warning' : 'account restriction',
      }).catch(() => undefined);
      // Prefer a clearer in-app type via direct insert fallback already covered.
      void body;
    } else {
      await createAnonymousNotification({
        recipientProfileId: subjectId,
        kind: 'moderation_account',
        title: opts.action === 'warn' ? 'Account warning' : 'Account restricted',
        body,
      });
    }
  }

  if (opts.action === 'suspend') {
    await clearOpenStrikes({
      subjectKind,
      subjectId,
      clearedBy: opts.actor,
      note: 'account_queue:suspend',
    });
    if (subjectKind === 'user') {
      try {
        await pool.query(
          `
          update public.profiles
          set account_status = 'deactivated',
              deactivated_at = coalesce(deactivated_at, now()),
              updated_at = now()
          where user_id = $1::uuid
          `,
          [subjectId]
        );
      } catch (err: any) {
        console.warn('[account-queue] deactivate', err?.message ?? err);
      }
      await feedNotify
        .notifyModerationRemoval(subjectId, {
          entityType: 'profile',
          entityId: subjectId,
          rootLabel: 'account suspension',
        })
        .catch(() => undefined);
    } else {
      await createAnonymousNotification({
        recipientProfileId: subjectId,
        kind: 'moderation_account',
        title: 'Account suspended',
        body: 'Your Masquerade profile was suspended after moderation review.',
      });
    }
  }

  // Resolve the account ticket as "mark" so status closes without content archive.
  await resolveTicket({
    ticketId: opts.ticket.id,
    actor: opts.actor,
    action: 'mark',
    category: opts.ticket.category || 'other',
    note: `account_action:${opts.action}`,
  });
}

export async function handleAccountQueueGet(req: Request, res: Response): Promise<void> {
  if (!hasReportsAccess(req)) {
    res.status(401).send(renderReportsLoginHtml({ next: '/reports/accounts' }));
    return;
  }
  await ensureTicketsSchema();
  const actor = actorFromReq(req);
  const ticketParam = String(req.query.ticket || '').trim();
  const excludeParam = String(req.query.exclude || '').trim();
  let flash = String(req.query.flash || '') || null;
  const prefer =
    ticketParam &&
    /^[0-9a-f-]{36}$/i.test(ticketParam) &&
    ticketParam !== excludeParam
      ? ticketParam
      : null;

  const claimed = await ensureClaimedAccountTicket(actor, {
    preferTicketId: prefer,
    excludeTicketId: excludeParam || null,
  });
  if (prefer && (!claimed || claimed.id !== prefer)) {
    flash = flash || 'Could not open that account ticket';
  }

  const openCount = await openTicketCount({ queue: 'account' });
  let body: string;
  if (claimed) {
    const display = await hydrateAccountTicket(claimed);
    body = renderAccountCard(display);
  } else {
    body = renderEmpty(openCount);
  }
  res.type('html').send(renderShell({ openCount, body, flash }));
}

export async function handleAccountQueueAction(req: Request, res: Response): Promise<void> {
  if (!hasReportsAccess(req)) {
    res.status(401).send(renderReportsLoginHtml({ next: '/reports/accounts' }));
    return;
  }
  const actor = actorFromReq(req);
  const ticketId = String(req.body?.ticket_id || '').trim();
  const action = String(req.body?.action || '').trim();
  if (!ticketId) {
    res.redirect(303, '/reports/accounts?flash=Missing+ticket');
    return;
  }

  if (action === 'pass') {
    await releaseTicket(ticketId, actor, { force: true, passToOther: true });
    const next = await claimNextTicket(actor, {
      excludeTicketId: ticketId,
      queue: 'account',
    });
    if (next && next.id !== ticketId) {
      res.redirect(
        303,
        `/reports/accounts?ticket=${encodeURIComponent(next.id)}&exclude=${encodeURIComponent(ticketId)}&flash=${encodeURIComponent('Decision recorded')}`
      );
      return;
    }
    res.redirect(
      303,
      `/reports/accounts?exclude=${encodeURIComponent(ticketId)}&flash=${encodeURIComponent('Decision recorded')}`
    );
    return;
  }

  if (!['clear', 'warn', 'restrict', 'suspend'].includes(action)) {
    res.redirect(303, '/reports/accounts?flash=Unknown+action');
    return;
  }

  const { rows } = await pool.query<TicketRow>(
    `
    select
      id, platform, target_kind, target_id, category, status, source,
      report_count, last_report_at::text, preview_title, preview_body,
      preview_media_url, assigned_to, claimed_at::text, mod_action, mod_category,
      created_at::text,
      reporter_user_id::text, reporter_profile_id::text,
      coalesce(queue, 'content') as queue
    from public.moderation_tickets
    where id = $1::uuid
    limit 1
    `,
    [ticketId]
  );
  const ticket = rows[0];
  if (!ticket || ticket.queue !== 'account') {
    res.redirect(303, '/reports/accounts?flash=Not+an+account+ticket');
    return;
  }

  try {
    await applyAccountDecision({
      ticket,
      actor,
      action: action as 'clear' | 'warn' | 'restrict' | 'suspend',
    });
  } catch (err: any) {
    console.error('[account-queue/action]', err?.message ?? err);
    res.redirect(303, `/reports/accounts?flash=${encodeURIComponent(err?.message || 'failed')}`);
    return;
  }

  const next = await claimNextTicket(actor, { queue: 'account' });
  const flash = 'Decision recorded';
  if (next) {
    res.redirect(
      303,
      `/reports/accounts?ticket=${encodeURIComponent(next.id)}&flash=${encodeURIComponent(flash)}`
    );
    return;
  }
  res.redirect(303, `/reports/accounts?flash=${encodeURIComponent(flash)}`);
}
