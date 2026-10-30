/**
 * Unified moderation tickets — claim-next, Remove as / Mark as / Skip,
 * action log, and category archive moves.
 */
import { pool } from '../db.js';
import type { PoolClient } from '../db.js';
import {
  type ModerationCategorySlug,
  type ModerationPlatform,
  type ModerationTargetKind,
  isModerationCategory,
  normalizeCategory,
} from './categories.js';

export type TicketRow = {
  id: string;
  platform: ModerationPlatform;
  target_kind: ModerationTargetKind;
  target_id: string;
  category: string;
  status: string;
  source: string;
  report_count: number;
  last_report_at: string;
  preview_title: string | null;
  preview_body: string | null;
  preview_media_url: string | null;
  assigned_to: string | null;
  claimed_at: string | null;
  mod_action: string | null;
  mod_category: string | null;
  created_at: string;
};

export type UpsertTicketInput = {
  platform: ModerationPlatform;
  targetKind: ModerationTargetKind;
  targetId: string;
  category: string;
  source?: 'user' | 'auto';
  reporterUserId?: string | null;
  reporterProfileId?: string | null;
  previewTitle?: string | null;
  previewBody?: string | null;
  previewMediaUrl?: string | null;
  actor?: string;
};

let ticketsSchemaEnsured = false;

/** Ensure Pass can hand a ticket to another moderator (per-actor skip list). */
export async function ensureTicketsSchema(): Promise<void> {
  if (ticketsSchemaEnsured) return;
  await pool.query(`
    alter table public.moderation_tickets
      add column if not exists passed_by text[] not null default '{}'::text[]
  `);
  await pool.query(`
    create index if not exists moderation_tickets_open_fifo_idx
      on public.moderation_tickets (last_report_at asc, created_at asc)
      where status = 'open'
  `);
  ticketsSchemaEnsured = true;
}

async function logAction(
  client: PoolClient,
  opts: {
    ticketId: string | null;
    actor: string;
    action: 'claim' | 'remove' | 'mark' | 'skip' | 'release' | 'report';
    category?: string | null;
    targetKind?: string | null;
    targetId?: string | null;
    platform?: string | null;
    detail?: Record<string, unknown>;
  }
): Promise<void> {
  await client.query(
    `
    insert into public.moderation_action_log (
      ticket_id, actor, action, category, target_kind, target_id, platform, detail
    ) values ($1::uuid, $2, $3, $4, $5, $6::uuid, $7, $8::jsonb)
    `,
    [
      opts.ticketId,
      opts.actor,
      opts.action,
      opts.category ?? null,
      opts.targetKind ?? null,
      opts.targetId ?? null,
      opts.platform ?? null,
      JSON.stringify(opts.detail ?? {}),
    ]
  );
}

/** Create or bump an open/claimed ticket for a target. */
export async function upsertTicketFromReport(input: UpsertTicketInput): Promise<string> {
  const category = normalizeCategory(input.category);
  const source = input.source === 'auto' ? 'auto' : 'user';
  const actor = input.actor || 'reporter';
  const client = await pool.connect();
  try {
    await client.query('begin');
    const { rows } = await client.query<{ id: string }>(
      `
      insert into public.moderation_tickets (
        platform, target_kind, target_id,
        reporter_user_id, reporter_profile_id,
        category, source,
        preview_title, preview_body, preview_media_url,
        status, report_count, last_report_at, updated_at
      ) values (
        $1, $2, $3::uuid,
        $4::uuid, $5::uuid,
        $6, $7,
        $8, $9, $10,
        'open', 1, now(), now()
      )
      on conflict (target_kind, target_id) where (status in ('open', 'claimed'))
      do update set
        report_count = public.moderation_tickets.report_count + 1,
        last_report_at = now(),
        updated_at = now(),
        preview_title = coalesce(excluded.preview_title, public.moderation_tickets.preview_title),
        preview_body = coalesce(excluded.preview_body, public.moderation_tickets.preview_body),
        preview_media_url = coalesce(excluded.preview_media_url, public.moderation_tickets.preview_media_url),
        -- Prefer auto mature flag if user reported something else first.
        category = case
          when excluded.source = 'auto' then excluded.category
          else public.moderation_tickets.category
        end
      returning id
      `,
      [
        input.platform,
        input.targetKind,
        input.targetId,
        input.reporterUserId ?? null,
        input.reporterProfileId ?? null,
        category,
        source,
        input.previewTitle ?? null,
        input.previewBody ?? null,
        input.previewMediaUrl ?? null,
      ]
    );
    const ticketId = rows[0]?.id;
    if (!ticketId) throw new Error('ticket_upsert_failed');
    await logAction(client, {
      ticketId,
      actor,
      action: 'report',
      category,
      targetKind: input.targetKind,
      targetId: input.targetId,
      platform: input.platform,
      detail: { source },
    });
    await client.query('commit');
    return ticketId;
  } catch (err) {
    await client.query('rollback');
    throw err;
  } finally {
    client.release();
  }
}

/** Claim the next open unassigned ticket (one-at-a-time). */
export async function claimNextTicket(
  actor: string,
  opts?: { excludeTicketId?: string | null; excludeTicketIds?: string[] | null }
): Promise<TicketRow | null> {
  await ensureTicketsSchema();
  const excludeIds = [
    ...(opts?.excludeTicketIds ?? []),
    opts?.excludeTicketId ?? null,
  ]
    .map((id) => String(id || '').trim())
    .filter((id) => /^[0-9a-f-]{36}$/i.test(id));
  const client = await pool.connect();
  try {
    await client.query('begin');
    // Skip tickets this actor already Passed — those wait for another moderator.
    const { rows } = await client.query<TicketRow>(
      `
      with next as (
        select id
        from public.moderation_tickets
        where status = 'open'
          and assigned_to is null
          and not (id = any($2::uuid[]))
          and not ($1 = any(coalesce(passed_by, '{}'::text[])))
        -- Mix auto + user reports for now; priority ordering comes later.
        order by last_report_at asc nulls last, created_at asc
        for update skip locked
        limit 1
      )
      update public.moderation_tickets t
      set status = 'claimed',
          assigned_to = $1,
          claimed_at = now(),
          -- New claimant clears pass list so handoff can cycle later.
          passed_by = '{}'::text[],
          updated_at = now()
      from next
      where t.id = next.id
      returning
        t.id, t.platform, t.target_kind, t.target_id, t.category, t.status, t.source,
        t.report_count, t.last_report_at::text, t.preview_title, t.preview_body,
        t.preview_media_url, t.assigned_to, t.claimed_at::text, t.mod_action, t.mod_category,
        t.created_at::text
      `,
      [actor, excludeIds]
    );
    const ticket = rows[0] ?? null;
    if (ticket) {
      await logAction(client, {
        ticketId: ticket.id,
        actor,
        action: 'claim',
        category: ticket.category,
        targetKind: ticket.target_kind,
        targetId: ticket.target_id,
        platform: ticket.platform,
      });
    }
    await client.query('commit');
    return ticket;
  } catch (err) {
    await client.query('rollback');
    throw err;
  } finally {
    client.release();
  }
}

export async function releaseTicket(
  ticketId: string,
  actor: string,
  opts?: { force?: boolean; passToOther?: boolean }
): Promise<boolean> {
  await ensureTicketsSchema();
  const passToOther = opts?.passToOther !== false;
  const client = await pool.connect();
  try {
    await client.query('begin');
    // Pass: mark this actor on passed_by so only another moderator can claim it.
    const { rows } = await client.query<{
      id: string;
      target_kind: string;
      target_id: string;
      platform: string;
      category: string;
    }>(
      `
      update public.moderation_tickets
      set status = 'open',
          assigned_to = null,
          claimed_at = null,
          last_report_at = greatest(now(), coalesce(last_report_at, now())) + interval '1 second',
          passed_by = case
            when $4::boolean then (
              select array_agg(distinct x)
              from unnest(
                array_append(coalesce(passed_by, '{}'::text[]), $2::text)
              ) as x
              where x is not null and length(x) > 0
            )
            else coalesce(passed_by, '{}'::text[])
          end,
          updated_at = now()
      where id = $1::uuid
        and status = 'claimed'
        and ($3::boolean or assigned_to = $2)
      returning id, target_kind, target_id, platform, category
      `,
      [ticketId, actor, !!opts?.force, passToOther]
    );
    if (!rows[0]) {
      await client.query('rollback');
      return false;
    }

    // Drop any other claims this actor still holds so Pass is one-at-a-time.
    await client.query(
      `
      update public.moderation_tickets
      set status = 'open',
          assigned_to = null,
          claimed_at = null,
          last_report_at = greatest(now(), coalesce(last_report_at, now())) + interval '1 second',
          updated_at = now()
      where status = 'claimed'
        and assigned_to = $1
        and id <> $2::uuid
      `,
      [actor, ticketId]
    );

    await logAction(client, {
      ticketId,
      actor,
      action: 'release',
      category: rows[0].category,
      targetKind: rows[0].target_kind,
      targetId: rows[0].target_id,
      platform: rows[0].platform,
      detail: { force: !!opts?.force, via: 'pass', pass_to_other: passToOther },
    });
    await client.query('commit');
    return true;
  } catch (err) {
    await client.query('rollback');
    throw err;
  } finally {
    client.release();
  }
}

async function archiveAndDeletePost(
  client: PoolClient,
  postId: string,
  category: ModerationCategorySlug,
  ticketId: string,
  actor: string,
  platform: string
): Promise<void> {
  const { rows } = await client.query<{ snapshot: unknown }>(
    `select to_jsonb(p.*) as snapshot from public.posts p where p.id = $1::uuid limit 1`,
    [postId]
  );
  const snap = rows[0]?.snapshot as Record<string, unknown> | undefined;
  if (!snap) return;
  await client.query(
    `
    insert into moderation_archive.posts (
      original_post_id, removed_category, ticket_id, removed_by, snapshot,
      title, body, media_type, media_url, thumb_url, author_id, platform
    ) values (
      $1::uuid, $2, $3::uuid, $4, $5::jsonb,
      $6, $7, $8, $9, $10, $11::uuid, $12
    )
    `,
    [
      postId,
      category,
      ticketId,
      actor,
      JSON.stringify(snap),
      snap.title ?? null,
      snap.body ?? null,
      snap.media_type ?? null,
      snap.media_url ?? null,
      snap.thumb_url ?? null,
      snap.author_id ?? null,
      platform,
    ]
  );
  await client.query(`delete from public.posts where id = $1::uuid`, [postId]);
}

async function archiveAndDeleteAnonymousPost(
  client: PoolClient,
  postId: string,
  category: ModerationCategorySlug,
  ticketId: string,
  actor: string
): Promise<void> {
  const { rows } = await client.query<{ snapshot: unknown }>(
    `select to_jsonb(p.*) as snapshot from anonymous.posts p where p.id = $1::uuid limit 1`,
    [postId]
  );
  const snap = rows[0]?.snapshot as Record<string, unknown> | undefined;
  if (!snap) return;
  await client.query(
    `
    insert into moderation_archive.posts (
      original_post_id, removed_category, ticket_id, removed_by, snapshot,
      title, body, media_type, media_url, thumb_url, author_id, platform
    ) values (
      $1::uuid, $2, $3::uuid, $4, $5::jsonb,
      $6, $7, $8, $9, $10, $11::uuid, 'masquerade'
    )
    `,
    [
      postId,
      category,
      ticketId,
      actor,
      JSON.stringify(snap),
      snap.title ?? null,
      snap.body ?? null,
      snap.media_type ?? null,
      snap.media_url ?? null,
      snap.thumb_url ?? null,
      snap.author_profile_id ?? null,
    ]
  );
  await client.query(
    `update anonymous.posts set state = 'removed', updated_at = now() where id = $1::uuid`,
    [postId]
  );
}

async function archiveAndDeleteComment(
  client: PoolClient,
  commentId: string,
  category: ModerationCategorySlug,
  ticketId: string,
  actor: string,
  platform: string
): Promise<void> {
  if (platform === 'masquerade') {
    const { rows } = await client.query<{ snapshot: unknown }>(
      `select to_jsonb(c.*) as snapshot from anonymous.comments c where c.id = $1::uuid limit 1`,
      [commentId]
    );
    const snap = rows[0]?.snapshot as Record<string, unknown> | undefined;
    if (!snap) return;
    await client.query(
      `
      insert into moderation_archive.comments (
        original_comment_id, removed_category, ticket_id, removed_by, snapshot,
        post_id, author_id, body, platform
      ) values ($1::uuid, $2, $3::uuid, $4, $5::jsonb, $6::uuid, $7::uuid, $8, 'masquerade')
      `,
      [
        commentId,
        category,
        ticketId,
        actor,
        JSON.stringify(snap),
        snap.post_id ?? null,
        snap.author_profile_id ?? null,
        snap.body ?? null,
      ]
    );
    await client.query(
      `update anonymous.comments set state = 'removed' where id = $1::uuid`,
      [commentId]
    );
    return;
  }

  const { rows } = await client.query<{ snapshot: unknown }>(
    `select to_jsonb(c.*) as snapshot from public.post_comments c where c.id = $1::uuid limit 1`,
    [commentId]
  );
  const snap = rows[0]?.snapshot as Record<string, unknown> | undefined;
  if (!snap) return;
  await client.query(
    `
    insert into moderation_archive.comments (
      original_comment_id, removed_category, ticket_id, removed_by, snapshot,
      post_id, author_id, body, platform
    ) values ($1::uuid, $2, $3::uuid, $4, $5::jsonb, $6::uuid, $7::uuid, $8, $9)
    `,
    [
      commentId,
      category,
      ticketId,
      actor,
      JSON.stringify(snap),
      snap.post_id ?? null,
      snap.author_id ?? null,
      snap.body ?? null,
      platform,
    ]
  );
  await client.query(`delete from public.post_comments where id = $1::uuid`, [commentId]);
}

async function archiveAndDeleteMessage(
  client: PoolClient,
  messageId: string,
  category: ModerationCategorySlug,
  ticketId: string,
  actor: string
): Promise<void> {
  const { rows } = await client.query<{ snapshot: unknown }>(
    `select to_jsonb(m.*) as snapshot from public.messages m where m.id = $1::uuid limit 1`,
    [messageId]
  );
  const snap = rows[0]?.snapshot as Record<string, unknown> | undefined;
  if (!snap) return;
  await client.query(
    `
    insert into moderation_archive.messages (
      original_message_id, removed_category, ticket_id, removed_by, snapshot,
      conversation_id, sender_id, body, platform
    ) values ($1::uuid, $2, $3::uuid, $4, $5::jsonb, $6::uuid, $7::uuid, $8, 'messages')
    `,
    [
      messageId,
      category,
      ticketId,
      actor,
      JSON.stringify(snap),
      snap.conversation_id ?? null,
      snap.sender_id ?? null,
      snap.body ?? snap.text ?? null,
    ]
  );
  // Prefer tombstone; fall back to hard delete if columns differ.
  try {
    await client.query(
      `
      update public.messages
      set body = '[Removed by moderator]',
          deleted_at = coalesce(deleted_at, now())
      where id = $1::uuid
      `,
      [messageId]
    );
  } catch {
    await client.query(`delete from public.messages where id = $1::uuid`, [messageId]);
  }
}

export type ResolveAction = 'remove' | 'mark' | 'skip';

export async function resolveTicket(opts: {
  ticketId: string;
  actor: string;
  action: ResolveAction;
  category?: string | null;
  note?: string | null;
}): Promise<{ ok: boolean; error?: string }> {
  const modCategory = opts.action === 'skip' ? null : normalizeCategory(opts.category);
  if (opts.action !== 'skip' && !isModerationCategory(modCategory)) {
    return { ok: false, error: 'invalid_category' };
  }

  const client = await pool.connect();
  try {
    await client.query('begin');
    const { rows } = await client.query<TicketRow>(
      `
      select
        id, platform, target_kind, target_id, category, status, source,
        report_count, last_report_at::text, preview_title, preview_body,
        preview_media_url, assigned_to, claimed_at::text, mod_action, mod_category,
        created_at::text
      from public.moderation_tickets
      where id = $1::uuid
      for update
      `,
      [opts.ticketId]
    );
    const ticket = rows[0];
    if (!ticket) {
      await client.query('rollback');
      return { ok: false, error: 'not_found' };
    }
    if (ticket.status !== 'claimed' && ticket.status !== 'open') {
      await client.query('rollback');
      return { ok: false, error: 'already_resolved' };
    }

    if (opts.action === 'remove' && modCategory) {
      if (ticket.target_kind === 'post') {
        if (ticket.platform === 'masquerade') {
          await archiveAndDeleteAnonymousPost(
            client,
            ticket.target_id,
            modCategory,
            ticket.id,
            opts.actor
          );
        } else {
          await archiveAndDeletePost(
            client,
            ticket.target_id,
            modCategory,
            ticket.id,
            opts.actor,
            ticket.platform
          );
        }
      } else if (ticket.target_kind === 'comment') {
        await archiveAndDeleteComment(
          client,
          ticket.target_id,
          modCategory,
          ticket.id,
          opts.actor,
          ticket.platform
        );
      } else if (ticket.target_kind === 'message') {
        await archiveAndDeleteMessage(
          client,
          ticket.target_id,
          modCategory,
          ticket.id,
          opts.actor
        );
      }
    } else if (opts.action === 'mark' && modCategory) {
      if (ticket.target_kind === 'post' && ticket.platform !== 'masquerade') {
        await client.query(
          `
          update public.posts
          set mod_mark_category = $2,
              moderation_note = coalesce($3, moderation_note),
              moderated_at = now(),
              moderation_actor = $4
          where id = $1::uuid
          `,
          [ticket.target_id, modCategory, opts.note ?? null, opts.actor]
        );
      } else if (ticket.target_kind === 'post' && ticket.platform === 'masquerade') {
        await client.query(
          `
          update anonymous.posts
          set flagged_at = coalesce(flagged_at, now()),
              flag_reason = $2,
              updated_at = now()
          where id = $1::uuid
          `,
          [ticket.target_id, `mark:${modCategory}`]
        );
      } else if (ticket.target_kind === 'comment' && ticket.platform !== 'masquerade') {
        await client.query(
          `update public.post_comments set mod_mark_category = $2 where id = $1::uuid`,
          [ticket.target_id, modCategory]
        );
      }
    } else if (opts.action === 'skip' && ticket.platform === 'masquerade' && ticket.target_kind === 'post') {
      // Clear auto flag on false positive.
      await client.query(
        `
        update anonymous.posts
        set flagged_at = null, flag_reason = null, updated_at = now()
        where id = $1::uuid
        `,
        [ticket.target_id]
      );
    }

    const newStatus = opts.action === 'skip' ? 'dismissed' : 'resolved';
    await client.query(
      `
      update public.moderation_tickets
      set status = $2,
          mod_action = $3,
          mod_category = $4,
          mod_note = $5,
          moderated_at = now(),
          moderated_by = $6,
          assigned_to = null,
          updated_at = now()
      where id = $1::uuid
      `,
      [
        ticket.id,
        newStatus,
        opts.action,
        modCategory,
        opts.note ?? null,
        opts.actor,
      ]
    );

    await logAction(client, {
      ticketId: ticket.id,
      actor: opts.actor,
      action: opts.action,
      category: modCategory,
      targetKind: ticket.target_kind,
      targetId: ticket.target_id,
      platform: ticket.platform,
      detail: { note: opts.note ?? null, prior_category: ticket.category },
    });

    await client.query('commit');
    return { ok: true };
  } catch (err) {
    await client.query('rollback');
    throw err;
  } finally {
    client.release();
  }
}

const TICKET_SELECT = `
  id, platform, target_kind, target_id, category, status, source,
  report_count, last_report_at::text, preview_title, preview_body,
  preview_media_url, assigned_to, claimed_at::text, mod_action, mod_category,
  created_at::text
`;

export async function getClaimedTicketForActor(actor: string): Promise<TicketRow | null> {
  const { rows } = await pool.query<TicketRow>(
    `
    select ${TICKET_SELECT}
    from public.moderation_tickets
    where status = 'claimed'
      and assigned_to = $1
    order by claimed_at desc
    limit 1
    `,
    [actor]
  );
  return rows[0] ?? null;
}

export async function getTicketById(ticketId: string): Promise<TicketRow | null> {
  const { rows } = await pool.query<TicketRow>(
    `
    select ${TICKET_SELECT}
    from public.moderation_tickets
    where id = $1::uuid
    limit 1
    `,
    [ticketId]
  );
  return rows[0] ?? null;
}

/** Claim a specific open ticket (queue deep-link). */
export async function claimTicketById(
  ticketId: string,
  actor: string
): Promise<{ ok: boolean; ticket?: TicketRow; error?: string }> {
  await ensureTicketsSchema();
  const client = await pool.connect();
  try {
    await client.query('begin');
    const { rows: existing } = await client.query<TicketRow & { passed_by: string[] | null }>(
      `
      select ${TICKET_SELECT}, coalesce(passed_by, '{}'::text[]) as passed_by
      from public.moderation_tickets
      where id = $1::uuid
      for update
      `,
      [ticketId]
    );
    const row = existing[0];
    if (!row) {
      await client.query('rollback');
      return { ok: false, error: 'not_found' };
    }
    if (row.status === 'claimed' && row.assigned_to === actor) {
      await client.query('commit');
      return { ok: true, ticket: row };
    }
    if (row.status === 'claimed') {
      await client.query('rollback');
      return { ok: false, error: 'claimed_by_other' };
    }
    if (row.status !== 'open') {
      await client.query('rollback');
      return { ok: false, error: 'already_resolved' };
    }
    const passedBy = Array.isArray(row.passed_by) ? row.passed_by : [];
    if (passedBy.includes(actor)) {
      await client.query('rollback');
      return { ok: false, error: 'passed_to_other' };
    }

    // Drop any other claim this actor holds so one-at-a-time stays true.
    await client.query(
      `
      update public.moderation_tickets
      set status = 'open', assigned_to = null, claimed_at = null, updated_at = now()
      where status = 'claimed' and assigned_to = $1 and id <> $2::uuid
      `,
      [actor, ticketId]
    );

    const { rows } = await client.query<TicketRow>(
      `
      update public.moderation_tickets
      set status = 'claimed',
          assigned_to = $2,
          claimed_at = now(),
          passed_by = '{}'::text[],
          updated_at = now()
      where id = $1::uuid
        and status = 'open'
        and not ($2 = any(coalesce(passed_by, '{}'::text[])))
      returning ${TICKET_SELECT}
      `,
      [ticketId, actor]
    );
    const ticket = rows[0];
    if (!ticket) {
      await client.query('rollback');
      return { ok: false, error: 'claim_failed' };
    }
    await logAction(client, {
      ticketId: ticket.id,
      actor,
      action: 'claim',
      category: ticket.category,
      targetKind: ticket.target_kind,
      targetId: ticket.target_id,
      platform: ticket.platform,
      detail: { via: 'queue_link' },
    });
    await client.query('commit');
    return { ok: true, ticket };
  } catch (err) {
    await client.query('rollback');
    throw err;
  } finally {
    client.release();
  }
}

export async function openTicketCount(): Promise<number> {
  const { rows } = await pool.query<{ n: string }>(
    `select count(*)::text as n from public.moderation_tickets where status = 'open'`
  );
  return Number(rows[0]?.n || 0);
}

/** Display fields hydrated for the Claim-next UI (author + signed media). */
export type TicketDisplay = TicketRow & {
  author_username: string | null;
  author_avatar_seed: string | null;
  /** Direct avatar image URL when available (Sparks profiles). */
  author_avatar_url: string | null;
  author_profile_id: string | null;
  space_slug: string | null;
  space_title: string | null;
  flag_reason: string | null;
  media_type: string | null;
  /** Signed playable media URL (video or image). */
  media_url: string | null;
  /** Signed poster / image preview. */
  thumb_url: string | null;
};

/**
 * Load author chrome + signed media for a claimed ticket.
 * Masquerade posts use anonymous.profiles (username + avatar_seed).
 */
export async function hydrateTicketDisplay(
  ticket: TicketRow
): Promise<TicketDisplay> {
  const base: TicketDisplay = {
    ...ticket,
    author_username: null,
    author_avatar_seed: null,
    author_avatar_url: null,
    author_profile_id: null,
    space_slug: null,
    space_title: null,
    flag_reason: null,
    media_type: null,
    media_url: null,
    thumb_url: null,
  };

  try {
    if (ticket.target_kind === 'post' && ticket.platform === 'masquerade') {
      const { rows } = await pool.query<{
        title: string | null;
        body: string | null;
        media_type: string | null;
        media_url: string | null;
        thumb_url: string | null;
        flag_reason: string | null;
        author_profile_id: string | null;
        username: string | null;
        avatar_seed: string | null;
        space_slug: string | null;
        space_title: string | null;
      }>(
        `
        select p.title, p.body, p.media_type, p.media_url, p.thumb_url,
               p.flag_reason, p.author_profile_id::text as author_profile_id,
               a.username, a.avatar_seed,
               s.slug as space_slug, s.title as space_title
        from anonymous.posts p
        left join anonymous.profiles a on a.id = p.author_profile_id
        left join anonymous.spaces s on s.id = p.space_id
        where p.id = $1::uuid
        limit 1
        `,
        [ticket.target_id]
      );
      const row = rows[0];
      if (!row) return base;

      const { resolveAnonymousMediaUrl } = await import('../anonymous/media.js');
      const [media_url, thumb_url] = await Promise.all([
        resolveAnonymousMediaUrl(row.media_url),
        resolveAnonymousMediaUrl(row.thumb_url),
      ]);

      return {
        ...base,
        preview_title: ticket.preview_title || row.title,
        preview_body: ticket.preview_body || row.body,
        preview_media_url: thumb_url || media_url || ticket.preview_media_url,
        author_username: row.username,
        author_avatar_seed: row.avatar_seed,
        author_avatar_url: null,
        author_profile_id: row.author_profile_id,
        space_slug: row.space_slug,
        space_title: row.space_title,
        flag_reason: row.flag_reason,
        media_type: row.media_type,
        media_url,
        thumb_url,
      };
    }

    if (ticket.target_kind === 'post') {
      const { rows } = await pool.query<{
        title: string | null;
        body: string | null;
        media_type: string | null;
        media_url: string | null;
        thumb_url: string | null;
        author_id: string | null;
        username: string | null;
        display_name: string | null;
        avatar_url: string | null;
      }>(
        `
        select p.title, p.body, p.media_type, p.media_url, p.thumb_url,
               p.author_id::text as author_id,
               pr.username, pr.display_name, pr.avatar_url
        from public.posts p
        left join public.profiles pr on pr.user_id = p.author_id
        where p.id = $1::uuid
        limit 1
        `,
        [ticket.target_id]
      );
      const row = rows[0];
      if (!row) return base;

      const { freshenMediaUrlString, freshenThumbUrlString } = await import(
        '../media/r2-playback.js'
      );
      const [media_url, thumb_url] = await Promise.all([
        freshenMediaUrlString(row.media_url),
        freshenThumbUrlString(row.thumb_url),
      ]);

      return {
        ...base,
        preview_title: ticket.preview_title || row.title,
        preview_body: ticket.preview_body || row.body,
        preview_media_url: thumb_url || media_url || ticket.preview_media_url,
        author_username: row.username || row.display_name,
        author_avatar_seed: row.username || row.display_name,
        author_avatar_url: row.avatar_url,
        author_profile_id: row.author_id,
        space_slug: null,
        space_title: null,
        flag_reason: null,
        media_type: row.media_type,
        media_url,
        thumb_url,
      };
    }
  } catch (err: any) {
    console.warn('[moderation/tickets] hydrate failed', err?.message ?? err);
  }

  return base;
}

/**
 * Open Claim-next tickets for flagged Masquerade posts that never got one
 * (e.g. upsert failed while the tickets table was missing).
 */
export async function backfillAutoTicketsFromFlaggedPosts(
  limit = 500
): Promise<{ created: number; scanned: number }> {
  const { rows } = await pool.query<{
    id: string;
    title: string | null;
    body: string | null;
    media_url: string | null;
    thumb_url: string | null;
    flag_reason: string | null;
  }>(
    `
    select p.id, p.title, p.body, p.media_url, p.thumb_url, p.flag_reason
    from anonymous.posts p
    where p.state = 'active'
      and p.flagged_at is not null
      and not exists (
        select 1 from public.moderation_tickets t
        where t.target_kind = 'post'
          and t.target_id = p.id
          and t.status in ('open', 'claimed')
      )
    order by p.flagged_at asc
    limit $1
    `,
    [limit]
  );

  let created = 0;
  for (const p of rows) {
    const reason = p.flag_reason || 'mature';
    const category = /nsfw|adult|sexual|video:nsfw|mature/i.test(reason)
      ? 'mature'
      : normalizeCategory(reason, 'mature');
    try {
      await upsertTicketFromReport({
        platform: 'masquerade',
        targetKind: 'post',
        targetId: p.id,
        category,
        source: 'auto',
        previewTitle: p.title,
        previewBody: p.body,
        previewMediaUrl: p.thumb_url || p.media_url,
        actor: 'auto-backfill',
      });
      created += 1;
    } catch (err: any) {
      console.warn(
        '[moderation/tickets] backfill upsert failed',
        p.id,
        err?.message ?? err
      );
    }
  }
  return { created, scanned: rows.length };
}

/**
 * Open Claim-next tickets for open user reports that never got one
 * (Masquerade anonymous.reports + public post_reports).
 */
export async function backfillUserReportTickets(
  limit = 300
): Promise<{ created: number; scanned: number }> {
  let created = 0;
  let scanned = 0;

  const { rows: anon } = await pool.query<{
    target_type: string;
    target_id: string;
    reason: string;
    reporter_profile_id: string | null;
    title: string | null;
    body: string | null;
    media_url: string | null;
    thumb_url: string | null;
  }>(
    `
    select r.target_type, r.target_id::text, r.reason,
           r.reporter_profile_id::text as reporter_profile_id,
           p.title, p.body, p.media_url, p.thumb_url
    from anonymous.reports r
    left join anonymous.posts p
      on r.target_type = 'post' and p.id = r.target_id
    where coalesce(r.state, 'open') in ('open', 'pending')
      and r.reason not like 'auto:%'
      and r.target_type in ('post', 'comment', 'profile', 'space')
      and not exists (
        select 1 from public.moderation_tickets t
        where t.target_id = r.target_id
          and t.target_kind = r.target_type
          and t.status in ('open', 'claimed')
      )
    order by r.created_at asc
    limit $1
    `,
    [limit]
  );
  scanned += anon.length;
  for (const r of anon) {
    try {
      await upsertTicketFromReport({
        platform: 'masquerade',
        targetKind: r.target_type as 'post' | 'comment' | 'profile' | 'space',
        targetId: r.target_id,
        category: normalizeCategory(r.reason),
        source: 'user',
        reporterProfileId: r.reporter_profile_id,
        previewTitle: r.title,
        previewBody: r.body || r.reason,
        previewMediaUrl: r.thumb_url || r.media_url,
        actor: 'user-report-backfill',
      });
      created += 1;
    } catch (err: any) {
      console.warn(
        '[moderation/tickets] user anon backfill failed',
        r.target_id,
        err?.message ?? err
      );
    }
  }

  const { rows: feed } = await pool.query<{
    post_id: string;
    reason: string;
    reporter_id: string | null;
    title: string | null;
    body: string | null;
    media_url: string | null;
    thumb_url: string | null;
    media_type: string | null;
  }>(
    `
    select pr.post_id::text, pr.reason, pr.reporter_id::text as reporter_id,
           p.title, p.body, p.media_url, p.thumb_url, p.media_type
    from public.post_reports pr
    left join public.posts p on p.id = pr.post_id
    where coalesce(pr.status, 'open') in ('open', 'pending')
      and not exists (
        select 1 from public.moderation_tickets t
        where t.target_kind = 'post'
          and t.target_id = pr.post_id
          and t.status in ('open', 'claimed')
      )
    order by pr.created_at asc
    limit $1
    `,
    [limit]
  );
  scanned += feed.length;
  for (const r of feed) {
    const body = String(r.body || '');
    const platform = /__spark__|__spark_share__|__reel__/i.test(body)
      ? 'sparks'
      : String(r.media_type || '').toLowerCase() === 'video'
        ? 'hubs'
        : 'feed';
    try {
      await upsertTicketFromReport({
        platform,
        targetKind: 'post',
        targetId: r.post_id,
        category: normalizeCategory(r.reason),
        source: 'user',
        reporterUserId: r.reporter_id,
        previewTitle: r.title,
        previewBody: r.body,
        previewMediaUrl: r.thumb_url || r.media_url,
        actor: 'user-report-backfill',
      });
      created += 1;
    } catch (err: any) {
      console.warn(
        '[moderation/tickets] user feed backfill failed',
        r.post_id,
        err?.message ?? err
      );
    }
  }

  return { created, scanned };
}

let lastEnsureAt = 0;

/** Cheap heal: backfill missing auto + user tickets at most once per 60s per process. */
export async function ensureAutoTicketsFromFlaggedPosts(): Promise<void> {
  const now = Date.now();
  if (now - lastEnsureAt < 60_000) return;
  lastEnsureAt = now;
  try {
    const auto = await backfillAutoTicketsFromFlaggedPosts(200);
    const user = await backfillUserReportTickets(200);
    if (auto.created > 0 || user.created > 0) {
      console.log(
        `[moderation/tickets] ensured auto=${auto.created}/${auto.scanned} user=${user.created}/${user.scanned}`
      );
    }
  } catch (err: any) {
    console.warn('[moderation/tickets] ensure tickets', err?.message ?? err);
  }
}
