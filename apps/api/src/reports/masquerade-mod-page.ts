/**
 * Masquerade video / content review queue.
 * https://api.matterya.com/reports/masquerade
 *
 * Same cookie gate as /reports. Actions:
 *   remove — take post down (state=removed)
 *   flag   — keep platform Flagged badge; close report
 *   ignore — dismiss report + clear flag (allowed by policy / false positive)
 */
import type { Request, Response } from 'express';
import { pool } from '../db.js';
import { resolveAnonymousMediaUrl } from '../anonymous/media.js';
import {
  hasReportsAccess,
  renderReportsLoginHtml,
  REPORTS_PAGE_PASSWORD,
} from './reports-page.js';

function escapeHtml(s: string): string {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

type QueueRow = {
  report_id: string;
  reason: string;
  report_created_at: Date | string;
  post_id: string;
  title: string | null;
  body: string;
  media_type: string | null;
  media_url: string | null;
  thumb_url: string | null;
  flagged_at: Date | string | null;
  flag_reason: string | null;
  space_slug: string;
  space_title: string;
  author_username: string | null;
};

async function loadQueue(limit = 40): Promise<QueueRow[]> {
  const { rows } = await pool.query<QueueRow>(
    `
    select r.id as report_id, r.reason, r.created_at as report_created_at,
           p.id as post_id, p.title, p.body, p.media_type, p.media_url, p.thumb_url,
           p.flagged_at, p.flag_reason,
           s.slug as space_slug, s.title as space_title,
           a.username as author_username
    from anonymous.reports r
    join anonymous.posts p on p.id = r.target_id
    join anonymous.spaces s on s.id = p.space_id
    left join anonymous.profiles a on a.id = p.author_profile_id
    where r.state = 'open'
      and r.target_type = 'post'
      and p.state = 'active'
    order by r.created_at desc
    limit $1
    `,
    [limit]
  );
  const out: QueueRow[] = [];
  for (const row of rows) {
    const [media_url, thumb_url] = await Promise.all([
      resolveAnonymousMediaUrl(row.media_url),
      resolveAnonymousMediaUrl(row.thumb_url),
    ]);
    out.push({ ...row, media_url, thumb_url });
  }
  return out;
}

function renderQueueHtml(items: QueueRow[]): string {
  const cards = items
    .map((it) => {
      const title = escapeHtml(it.title || it.body.slice(0, 80) || '(no title)');
      const body = escapeHtml((it.body || '').slice(0, 280));
      const reason = escapeHtml(it.reason);
      const space = escapeHtml(it.space_title || it.space_slug);
      const author = escapeHtml(it.author_username || 'anonymous');
      const media =
        it.media_type === 'video' && it.media_url
          ? `<video class="media" src="${escapeHtml(it.media_url)}" poster="${escapeHtml(it.thumb_url || '')}" controls playsinline preload="metadata"></video>`
          : it.thumb_url || it.media_url
            ? `<img class="media" src="${escapeHtml(it.thumb_url || it.media_url || '')}" alt=""/>`
            : `<div class="media empty">No media</div>`;
      return `
      <article class="card" data-report="${escapeHtml(it.report_id)}" data-post="${escapeHtml(it.post_id)}">
        <div class="meta">
          <span class="pill">Flagged</span>
          <span class="space">${space}</span>
          <span class="muted">@${author}</span>
        </div>
        <h2>${title}</h2>
        <p class="body">${body}</p>
        <p class="reason">${reason}</p>
        ${media}
        <form class="actions" method="post" action="/reports/masquerade/action">
          <input type="hidden" name="report_id" value="${escapeHtml(it.report_id)}"/>
          <input type="hidden" name="post_id" value="${escapeHtml(it.post_id)}"/>
          <button name="decision" value="remove" class="danger">Remove</button>
          <button name="decision" value="flag" class="accent">Flag</button>
          <button name="decision" value="ignore" class="ghost">Ignore</button>
        </form>
      </article>`;
    })
    .join('\n');

  const empty = !items.length
    ? `<p class="empty">Queue clear — no open Masquerade reports.</p>`
    : '';

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>Matterya · Masquerade moderation</title>
  <style>
    :root {
      --paper:#f8f6f2; --ink:#2c2825; --muted:#7a736c; --accent:#7b6347;
      --border:#ddd6cc; --surface:#fffcf8; --danger:#b91c1c;
    }
    * { box-sizing: border-box; }
    body {
      margin:0; font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
      background: var(--paper); color: var(--ink);
    }
    header {
      display:flex; flex-wrap:wrap; gap:12px; align-items:center; justify-content:space-between;
      padding:18px 22px; border-bottom:1px solid var(--border); background:var(--surface);
      position:sticky; top:0; z-index:5;
    }
    .mark { font-size:11px; font-weight:700; letter-spacing:.2em; text-transform:uppercase; color:var(--accent); }
    h1 { margin:0; font-size:1.35rem; font-weight:500; font-family: ui-serif, Georgia, serif; }
    .links a { color:var(--accent); margin-left:12px; text-decoration:none; font-size:13px; }
    main { max-width:860px; margin:0 auto; padding:20px 16px 60px; display:grid; gap:16px; }
    .card {
      background:var(--surface); border:1px solid var(--border); border-radius:16px;
      padding:16px 16px 14px; box-shadow:0 10px 28px rgba(44,40,37,.06);
    }
    .meta { display:flex; gap:10px; align-items:center; flex-wrap:wrap; margin-bottom:8px; font-size:12px; }
    .pill {
      background:#f3e8d8; color:var(--accent); border-radius:999px; padding:3px 10px; font-weight:700;
    }
    .muted { color:var(--muted); }
    .space { font-weight:650; }
    h2 { margin:0 0 6px; font-size:1.05rem; font-weight:600; }
    .body { margin:0 0 8px; color:var(--muted); font-size:14px; line-height:1.45; white-space:pre-wrap; }
    .reason {
      margin:0 0 12px; font-size:12px; color:#92400e; background:#fff7ed;
      border:1px solid #fed7aa; border-radius:10px; padding:8px 10px; word-break:break-word;
    }
    .media {
      width:100%; max-height:420px; object-fit:contain; background:#111; border-radius:12px;
      display:block; margin-bottom:12px;
    }
    .media.empty {
      height:120px; display:grid; place-items:center; color:#a8a29e; font-size:13px;
    }
    .actions { display:flex; gap:8px; flex-wrap:wrap; }
    .actions button {
      border:0; border-radius:999px; padding:10px 16px; font-weight:650; font-size:13px; cursor:pointer;
    }
    .actions .danger { background:var(--danger); color:#fff; }
    .actions .accent { background:var(--accent); color:#fff; }
    .actions .ghost { background:#efe8dc; color:var(--ink); }
    .empty { text-align:center; color:var(--muted); padding:40px 12px; }
    .sub { margin:4px 0 0; color:var(--muted); font-size:13px; }
  </style>
</head>
<body>
  <header>
    <div>
      <div class="mark">Matterya</div>
      <h1>Masquerade moderation</h1>
      <p class="sub">Open auto + user reports · Remove / Flag / Ignore</p>
    </div>
    <div class="links">
      <a href="/reports">Moderation</a>
      <a href="/reports/analytics">Insights</a>
      <a href="/reports/logout">Log out</a>
    </div>
  </header>
  <main>
    ${empty || cards}
  </main>
</body>
</html>`;
}

export async function handleMasqueradeModGet(req: Request, res: Response): Promise<void> {
  if (!hasReportsAccess(req)) {
    res.status(200).send(renderReportsLoginHtml({ next: '/reports/masquerade' }));
    return;
  }
  try {
    const items = await loadQueue(50);
    res.status(200).type('html').send(renderQueueHtml(items));
  } catch (err: any) {
    console.error('[reports/masquerade]', err?.message ?? err);
    res.status(500).type('html').send(`<pre>Failed to load queue: ${escapeHtml(err?.message ?? err)}</pre>`);
  }
}

export async function handleMasqueradeModAction(req: Request, res: Response): Promise<void> {
  if (!hasReportsAccess(req)) {
    res.status(401).send(renderReportsLoginHtml({ next: '/reports/masquerade', error: 'Login required' }));
    return;
  }
  const body = (req.body || {}) as Record<string, unknown>;
  const reportId = String(body.report_id || '').trim();
  const postId = String(body.post_id || '').trim();
  let decision = String(body.decision || '').trim().toLowerCase();
  if (decision === 'ignore') decision = 'skip';
  if (!reportId || !postId || !['remove', 'flag', 'skip'].includes(decision)) {
    res.status(400).send('bad request');
    return;
  }

  const client = await pool.connect();
  try {
    await client.query('begin');
    if (decision === 'remove') {
      await client.query(
        `
        update anonymous.posts
        set state = 'removed', updated_at = now()
        where id = $1::uuid
        `,
        [postId]
      );
      await client.query(
        `
        update anonymous.spaces s
        set post_count = greatest(0, post_count - 1), updated_at = now()
        from anonymous.posts p
        where p.id = $1::uuid and s.id = p.space_id
        `,
        [postId]
      );
      await client.query(
        `
        insert into anonymous.moderation_actions (actor_profile_id, target_type, target_id, action, reason)
        values (null, 'post', $1::uuid, 'mod_remove', 'reports/masquerade')
        `,
        [postId]
      );
    } else if (decision === 'flag') {
      await client.query(
        `
        update anonymous.posts
        set flagged_at = coalesce(flagged_at, now()),
            flag_reason = coalesce(flag_reason, 'mod_confirmed'),
            updated_at = now()
        where id = $1::uuid
        `,
        [postId]
      );
      await client.query(
        `
        insert into anonymous.moderation_actions (actor_profile_id, target_type, target_id, action, reason)
        values (null, 'post', $1::uuid, 'mod_flag', 'reports/masquerade')
        `,
        [postId]
      );
    } else {
      // skip — clear platform flag; policy allows / false positive
      await client.query(
        `
        update anonymous.posts
        set flagged_at = null, flag_reason = null, updated_at = now()
        where id = $1::uuid
        `,
        [postId]
      );
      await client.query(
        `
        insert into anonymous.moderation_actions (actor_profile_id, target_type, target_id, action, reason)
        values (null, 'post', $1::uuid, 'mod_skip', 'reports/masquerade')
        `,
        [postId]
      );
    }

    await client.query(
      `
      update anonymous.reports
      set state = $2
      where id = $1::uuid
      `,
      [reportId, decision === 'skip' ? 'dismissed' : 'resolved']
    );
    await client.query('commit');
  } catch (err) {
    try {
      await client.query('rollback');
    } catch {
      /* ignore */
    }
    throw err;
  } finally {
    client.release();
  }

  res.redirect(303, '/reports/masquerade');
}

/** Silence unused import warning if tree-shaken oddly. */
void REPORTS_PAGE_PASSWORD;
