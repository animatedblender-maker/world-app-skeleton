/**
 * Post-remove enforcement: notify author + reporters, record strikes,
 * and escalate into the account Claim-next queue when severe or at 3 mild.
 */
import { pool } from '../db.js';
import { NotificationsService } from '../graphql/modules/notifications/notifications.service.js';
import { createAnonymousNotification } from '../anonymous/notifications.js';
import { labelForCategory } from './categories.js';
import {
  getPolicyLeaf,
  leafSeverity,
  type PolicyLeaf,
} from './policy-tree.js';
import { ensureTicketsSchema, upsertTicketFromReport, type TicketRow } from './tickets.js';

export const MILD_STRIKE_THRESHOLD = 3;

export type StrikeSubjectKind = 'user' | 'anonymous_profile';

export type RemovalSubject = {
  kind: StrikeSubjectKind;
  id: string;
  username?: string | null;
};

export type ApplyRemovalEnforcementInput = {
  ticket: TicketRow;
  leafId?: string | null;
  /** Author subject captured before archive/delete. */
  subject: RemovalSubject | null;
  /** Feed reporter user ids (deduped). */
  reporterUserIds?: string[];
  /** Masquerade reporter profile ids (deduped). */
  reporterProfileIds?: string[];
};

const feedNotify = new NotificationsService();

function parseLeafFromNote(note: string | null | undefined): PolicyLeaf | null {
  const m = String(note || '').match(/policy:([a-z0-9_.]+)/i);
  if (!m?.[1]) return null;
  return getPolicyLeaf(m[1]) ?? null;
}

/** Look up author for a content ticket (live row or archive fallback). */
export async function resolveRemovalSubject(
  ticket: TicketRow
): Promise<RemovalSubject | null> {
  try {
    if (ticket.target_kind === 'post' && ticket.platform === 'masquerade') {
      const { rows } = await pool.query<{
        author_profile_id: string | null;
        username: string | null;
      }>(
        `
        select p.author_profile_id::text as author_profile_id, a.username
        from anonymous.posts p
        left join anonymous.profiles a on a.id = p.author_profile_id
        where p.id = $1::uuid
        limit 1
        `,
        [ticket.target_id]
      );
      const id = rows[0]?.author_profile_id;
      if (id) {
        return { kind: 'anonymous_profile', id, username: rows[0]?.username ?? null };
      }
    }

    if (ticket.target_kind === 'post') {
      const { rows } = await pool.query<{
        author_id: string | null;
        username: string | null;
      }>(
        `
        select p.author_id::text as author_id, pr.username
        from public.posts p
        left join public.profiles pr on pr.user_id = p.author_id
        where p.id = $1::uuid
        limit 1
        `,
        [ticket.target_id]
      );
      if (rows[0]?.author_id) {
        return {
          kind: 'user',
          id: rows[0].author_id,
          username: rows[0].username ?? null,
        };
      }
      // Feed posts are hard-deleted — fall back to archive.
      const { rows: arch } = await pool.query<{
        author_id: string | null;
        username: string | null;
      }>(
        `
        select a.author_id::text as author_id, pr.username
        from moderation_archive.posts a
        left join public.profiles pr on pr.user_id = a.author_id
        where a.original_post_id = $1::uuid
        order by a.ticket_id nulls last
        limit 1
        `,
        [ticket.target_id]
      );
      if (arch[0]?.author_id) {
        return {
          kind: 'user',
          id: arch[0].author_id,
          username: arch[0].username ?? null,
        };
      }
    }

    if (ticket.target_kind === 'comment' && ticket.platform === 'masquerade') {
      const { rows } = await pool.query<{
        author_profile_id: string | null;
        username: string | null;
      }>(
        `
        select c.author_profile_id::text as author_profile_id, a.username
        from anonymous.comments c
        left join anonymous.profiles a on a.id = c.author_profile_id
        where c.id = $1::uuid
        limit 1
        `,
        [ticket.target_id]
      );
      if (rows[0]?.author_profile_id) {
        return {
          kind: 'anonymous_profile',
          id: rows[0].author_profile_id,
          username: rows[0].username ?? null,
        };
      }
    }

    if (ticket.target_kind === 'comment') {
      const { rows } = await pool.query<{
        author_id: string | null;
        username: string | null;
      }>(
        `
        select c.author_id::text as author_id, pr.username
        from public.post_comments c
        left join public.profiles pr on pr.user_id = c.author_id
        where c.id = $1::uuid
        limit 1
        `,
        [ticket.target_id]
      );
      if (rows[0]?.author_id) {
        return {
          kind: 'user',
          id: rows[0].author_id,
          username: rows[0].username ?? null,
        };
      }
    }

    if (ticket.target_kind === 'message') {
      const { rows } = await pool.query<{ sender_id: string | null }>(
        `select sender_id::text as sender_id from public.messages where id = $1::uuid limit 1`,
        [ticket.target_id]
      );
      if (rows[0]?.sender_id) {
        return { kind: 'user', id: rows[0].sender_id };
      }
    }
  } catch (err: any) {
    console.warn('[enforcement] resolveRemovalSubject', err?.message ?? err);
  }
  return null;
}

/** Distinct user reporters for a feed post (skip auto / empty). */
export async function listFeedReporterUserIds(postId: string): Promise<string[]> {
  try {
    const { rows } = await pool.query<{ reporter_id: string }>(
      `
      select distinct reporter_id::text as reporter_id
      from public.post_reports
      where post_id = $1::uuid
        and reporter_id is not null
        and coalesce(status, 'open') in ('open', 'pending', 'in_review', 'actioned')
      `,
      [postId]
    );
    return rows.map((r) => r.reporter_id).filter(Boolean);
  } catch (err: any) {
    console.warn('[enforcement] listFeedReporterUserIds', err?.message ?? err);
    return [];
  }
}

/** Distinct masquerade reporters (skip auto:% reasons). */
export async function listAnonReporterProfileIds(
  targetId: string,
  targetType: string
): Promise<string[]> {
  try {
    const { rows } = await pool.query<{ reporter_profile_id: string }>(
      `
      select distinct reporter_profile_id::text as reporter_profile_id
      from anonymous.reports
      where target_id = $1::uuid
        and target_type = $2
        and reporter_profile_id is not null
        and coalesce(reason, '') not like 'auto:%'
        and coalesce(state, 'open') in ('open', 'pending', 'actioned')
      `,
      [targetId, targetType]
    );
    return rows.map((r) => r.reporter_profile_id).filter(Boolean);
  } catch (err: any) {
    console.warn('[enforcement] listAnonReporterProfileIds', err?.message ?? err);
    return [];
  }
}

async function notifyAuthorAndReporters(opts: {
  ticket: TicketRow;
  leaf: PolicyLeaf | null;
  subject: RemovalSubject | null;
  reporterUserIds: string[];
  reporterProfileIds: string[];
}): Promise<void> {
  const root = opts.leaf?.root || opts.ticket.category || 'other';
  const rootLabel = labelForCategory(root);
  const entityId = opts.ticket.target_id;
  const entityKind =
    opts.ticket.target_kind === 'comment'
      ? 'comment'
      : opts.ticket.target_kind === 'message'
        ? 'message'
        : 'post';

  if (opts.subject?.kind === 'user') {
    await feedNotify
      .notifyModerationRemoval(opts.subject.id, {
        entityType: entityKind,
        entityId,
        rootLabel,
      })
      .catch((err: any) =>
        console.warn('[enforcement] author notify', err?.message ?? err)
      );
  } else if (opts.subject?.kind === 'anonymous_profile') {
    await createAnonymousNotification({
      recipientProfileId: opts.subject.id,
      kind: 'moderation_removal',
      title: 'Post removed',
      body: `Your post was removed for ${rootLabel}.`,
      postId: opts.ticket.target_kind === 'post' ? entityId : null,
    });
  }

  const authorId = opts.subject?.id ?? null;
  if (opts.ticket.platform === 'masquerade') {
    for (const profileId of opts.reporterProfileIds) {
      if (authorId && profileId === authorId) continue;
      await createAnonymousNotification({
        recipientProfileId: profileId,
        kind: 'moderation_report_resolved',
        title: 'Report update',
        body: 'Thanks — we removed content you reported.',
        postId: opts.ticket.target_kind === 'post' ? entityId : null,
      });
    }
  } else {
    for (const userId of opts.reporterUserIds) {
      if (authorId && userId === authorId) continue;
      await feedNotify
        .notifyReportResolved(userId, {
          entityType: entityKind,
          entityId,
        })
        .catch((err: any) =>
          console.warn('[enforcement] reporter notify', err?.message ?? err)
        );
    }
  }
}

async function recordStrikeAndMaybeEscalate(opts: {
  ticket: TicketRow;
  leaf: PolicyLeaf | null;
  subject: RemovalSubject;
}): Promise<void> {
  await ensureTicketsSchema();
  const leaf = opts.leaf;
  const leafId = leaf?.id || 'unknown';
  const root = leaf?.root || opts.ticket.category || 'other';
  const severity = leaf ? leafSeverity(leaf) : 'mild';

  await pool.query(
    `
    insert into public.account_strikes (
      subject_kind, subject_id, leaf_id, root_category, severity,
      source_ticket_id, source_target_kind, source_target_id
    ) values (
      $1, $2::uuid, $3, $4, $5,
      $6::uuid, $7, $8::uuid
    )
    `,
    [
      opts.subject.kind,
      opts.subject.id,
      leafId,
      root,
      severity,
      opts.ticket.id,
      opts.ticket.target_kind,
      opts.ticket.target_id,
    ]
  );

  const { rows: countRows } = await pool.query<{ n: string }>(
    `
    select count(*)::text as n
    from public.account_strikes
    where subject_kind = $1
      and subject_id = $2::uuid
      and cleared_at is null
    `,
    [opts.subject.kind, opts.subject.id]
  );
  const openStrikes = Number(countRows[0]?.n || 0);
  const shouldEscalate =
    severity === 'severe' || openStrikes >= MILD_STRIKE_THRESHOLD;
  if (!shouldEscalate) return;

  const handle = opts.subject.username
    ? `@${opts.subject.username}`
    : opts.subject.id.slice(0, 8);
  const why =
    severity === 'severe'
      ? `Severe: ${leafId}`
      : `Strikes: ${openStrikes} · last: ${leafId}`;

  await upsertTicketFromReport({
    platform: opts.ticket.platform === 'masquerade' ? 'masquerade' : 'feed',
    targetKind: 'profile',
    targetId: opts.subject.id,
    category: root,
    source: 'auto',
    queue: 'account',
    previewTitle: `${handle} · account review`,
    previewBody: why,
    actor: 'enforcement',
  });
}

/**
 * After a successful content remove: notify, strike, maybe open account ticket.
 * Best-effort — never throws to the resolve path.
 */
export async function applyRemovalEnforcement(
  input: ApplyRemovalEnforcementInput
): Promise<void> {
  try {
    if (input.ticket.queue === 'account') return;
    if (input.ticket.target_kind === 'profile') return;

    const leaf =
      (input.leafId ? getPolicyLeaf(input.leafId) : null) ||
      parseLeafFromNote(
        // resolve stores policy leaf in mod_note after commit — re-read if needed
        null
      );

    let resolvedLeaf = leaf;
    if (!resolvedLeaf && input.leafId) {
      resolvedLeaf = getPolicyLeaf(input.leafId);
    }
    // Prefer leaf from input; fall back to ticket.mod note via re-fetch
    if (!resolvedLeaf) {
      const { rows } = await pool.query<{ mod_note: string | null }>(
        `select mod_note from public.moderation_tickets where id = $1::uuid limit 1`,
        [input.ticket.id]
      );
      resolvedLeaf = parseLeafFromNote(rows[0]?.mod_note);
    }

    let subject = input.subject;
    if (!subject) {
      subject = await resolveRemovalSubject(input.ticket);
    }

    let reporterUserIds = input.reporterUserIds ?? [];
    let reporterProfileIds = input.reporterProfileIds ?? [];
    if (
      !reporterUserIds.length &&
      !reporterProfileIds.length &&
      input.ticket.target_kind === 'post'
    ) {
      if (input.ticket.platform === 'masquerade') {
        reporterProfileIds = await listAnonReporterProfileIds(
          input.ticket.target_id,
          'post'
        );
      } else {
        reporterUserIds = await listFeedReporterUserIds(input.ticket.target_id);
      }
    }

    await notifyAuthorAndReporters({
      ticket: input.ticket,
      leaf: resolvedLeaf,
      subject,
      reporterUserIds,
      reporterProfileIds,
    });

    if (subject) {
      await recordStrikeAndMaybeEscalate({
        ticket: input.ticket,
        leaf: resolvedLeaf,
        subject,
      });
    }
  } catch (err: any) {
    console.warn('[enforcement] applyRemovalEnforcement', err?.message ?? err);
  }
}

/** Open (uncleared) strikes for a subject, newest first. */
export async function listOpenStrikes(
  subjectKind: StrikeSubjectKind,
  subjectId: string,
  limit = 10
): Promise<
  Array<{
    id: string;
    leaf_id: string;
    root_category: string;
    severity: string;
    source_ticket_id: string | null;
    created_at: string;
  }>
> {
  await ensureTicketsSchema();
  const { rows } = await pool.query(
    `
    select id::text, leaf_id, root_category, severity,
           source_ticket_id::text, created_at::text
    from public.account_strikes
    where subject_kind = $1
      and subject_id = $2::uuid
      and cleared_at is null
    order by created_at desc
    limit $3
    `,
    [subjectKind, subjectId, Math.max(1, Math.min(50, limit))]
  );
  return rows as any[];
}

export async function clearOpenStrikes(opts: {
  subjectKind: StrikeSubjectKind;
  subjectId: string;
  clearedBy: string;
  note?: string | null;
}): Promise<number> {
  await ensureTicketsSchema();
  const { rowCount } = await pool.query(
    `
    update public.account_strikes
    set cleared_at = now(),
        cleared_by = $3,
        clear_note = $4
    where subject_kind = $1
      and subject_id = $2::uuid
      and cleared_at is null
    `,
    [opts.subjectKind, opts.subjectId, opts.clearedBy, opts.note ?? null]
  );
  return rowCount ?? 0;
}
