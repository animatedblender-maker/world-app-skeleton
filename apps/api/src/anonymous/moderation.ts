import { pool } from '../db.js';
import type { AnonymousProfilePublic } from './identity.js';

export async function createReport(opts: {
  profile: AnonymousProfilePublic;
  targetType: string;
  targetId: string;
  reason: string;
}): Promise<
  | { ok: true; report_id: string }
  | { ok: false; code: string; reason: string; status: number }
> {
  const targetType = String(opts.targetType || '').toLowerCase();
  if (!['post', 'comment', 'profile', 'space'].includes(targetType)) {
    return { ok: false, code: 'bad_target', reason: 'Invalid target_type.', status: 400 };
  }
  const reason = String(opts.reason || '').trim().slice(0, 1000);
  if (reason.length < 3) {
    return { ok: false, code: 'bad_reason', reason: 'Reason required.', status: 400 };
  }

  const { rows } = await pool.query<{ id: string }>(
    `
    insert into anonymous.reports (reporter_profile_id, target_type, target_id, reason)
    values ($1::uuid, $2, $3::uuid, $4)
    returning id
    `,
    [opts.profile.id, targetType, opts.targetId, reason]
  );
  const reportId = rows[0]!.id;

  // Same Claim-next queue as auto-detected — mix for now; priority later.
  try {
    const { upsertTicketFromReport } = await import('../moderation/tickets.js');
    const { normalizeCategory } = await import('../moderation/categories.js');
    let previewTitle: string | null = null;
    let previewBody: string | null = null;
    let previewMediaUrl: string | null = null;
    if (targetType === 'post') {
      const { rows: posts } = await pool.query<{
        title: string | null;
        body: string | null;
        media_url: string | null;
        thumb_url: string | null;
      }>(
        `select title, body, media_url, thumb_url from anonymous.posts where id = $1::uuid limit 1`,
        [opts.targetId]
      );
      previewTitle = posts[0]?.title ?? null;
      previewBody = posts[0]?.body ?? null;
      previewMediaUrl = posts[0]?.thumb_url || posts[0]?.media_url || null;
    } else if (targetType === 'comment') {
      const { rows: comments } = await pool.query<{ body: string | null }>(
        `select body from anonymous.comments where id = $1::uuid limit 1`,
        [opts.targetId]
      );
      previewBody = comments[0]?.body ?? null;
    }
    await upsertTicketFromReport({
      platform: 'masquerade',
      targetKind: targetType as 'post' | 'comment' | 'space' | 'profile',
      targetId: opts.targetId,
      category: normalizeCategory(reason),
      source: 'user',
      reporterProfileId: opts.profile.id,
      previewTitle,
      previewBody,
      previewMediaUrl,
      actor: opts.profile.id,
    });
  } catch (err: any) {
    console.warn('[anonymous/createReport] ticket upsert failed', err?.message ?? err);
  }

  return { ok: true, report_id: reportId };
}

export async function blockProfile(opts: {
  profile: AnonymousProfilePublic;
  blockedProfileId: string;
}): Promise<
  | { ok: true }
  | { ok: false; code: string; reason: string; status: number }
> {
  if (opts.blockedProfileId === opts.profile.id) {
    return { ok: false, code: 'bad_target', reason: 'Cannot block yourself.', status: 400 };
  }
  const exists = await pool.query(
    `select 1 from anonymous.profiles where id = $1::uuid limit 1`,
    [opts.blockedProfileId]
  );
  if (!exists.rows.length) {
    return { ok: false, code: 'not_found', reason: 'Profile not found.', status: 404 };
  }
  await pool.query(
    `
    insert into anonymous.blocks (blocker_profile_id, blocked_profile_id)
    values ($1::uuid, $2::uuid)
    on conflict (blocker_profile_id, blocked_profile_id) do nothing
    `,
    [opts.profile.id, opts.blockedProfileId]
  );
  return { ok: true };
}

export async function recordModAction(opts: {
  actor: AnonymousProfilePublic;
  targetType: string;
  targetId: string;
  action: string;
  reason?: string;
}): Promise<{ ok: true; action_id: string }> {
  const { rows } = await pool.query<{ id: string }>(
    `
    insert into anonymous.moderation_actions (actor_profile_id, target_type, target_id, action, reason)
    values ($1::uuid, $2, $3::uuid, $4, $5)
    returning id
    `,
    [
      opts.actor.id,
      opts.targetType,
      opts.targetId,
      opts.action,
      opts.reason ?? null,
    ]
  );
  return { ok: true, action_id: rows[0]!.id };
}
