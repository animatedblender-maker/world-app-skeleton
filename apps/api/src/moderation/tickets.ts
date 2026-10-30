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
export async function claimNextTicket(actor: string): Promise<TicketRow | null> {
  const client = await pool.connect();
  try {
    await client.query('begin');
    const { rows } = await client.query<TicketRow>(
      `
      with next as (
        select id
        from public.moderation_tickets
        where status = 'open'
          and assigned_to is null
        order by last_report_at asc
        for update skip locked
        limit 1
      )
      update public.moderation_tickets t
      set status = 'claimed',
          assigned_to = $1,
          claimed_at = now(),
          updated_at = now()
      from next
      where t.id = next.id
      returning
        t.id, t.platform, t.target_kind, t.target_id, t.category, t.status, t.source,
        t.report_count, t.last_report_at::text, t.preview_title, t.preview_body,
        t.preview_media_url, t.assigned_to, t.claimed_at::text, t.mod_action, t.mod_category,
        t.created_at::text
      `,
      [actor]
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

export async function releaseTicket(ticketId: string, actor: string): Promise<boolean> {
  const client = await pool.connect();
  try {
    await client.query('begin');
    const { rows } = await client.query<{ id: string; target_kind: string; target_id: string; platform: string; category: string }>(
      `
      update public.moderation_tickets
      set status = 'open',
          assigned_to = null,
          claimed_at = null,
          updated_at = now()
      where id = $1::uuid
        and status = 'claimed'
        and assigned_to = $2
      returning id, target_kind, target_id, platform, category
      `,
      [ticketId, actor]
    );
    if (!rows[0]) {
      await client.query('rollback');
      return false;
    }
    await logAction(client, {
      ticketId,
      actor,
      action: 'release',
      category: rows[0].category,
      targetKind: rows[0].target_kind,
      targetId: rows[0].target_id,
      platform: rows[0].platform,
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

export async function getClaimedTicketForActor(actor: string): Promise<TicketRow | null> {
  const { rows } = await pool.query<TicketRow>(
    `
    select
      id, platform, target_kind, target_id, category, status, source,
      report_count, last_report_at::text, preview_title, preview_body,
      preview_media_url, assigned_to, claimed_at::text, mod_action, mod_category,
      created_at::text
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

export async function openTicketCount(): Promise<number> {
  const { rows } = await pool.query<{ n: string }>(
    `select count(*)::text as n from public.moderation_tickets where status = 'open'`
  );
  return Number(rows[0]?.n || 0);
}
