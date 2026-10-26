import { pool } from '../db.js';

export type AnonymousNotificationRow = {
  id: string;
  kind: string;
  title: string | null;
  body: string | null;
  space_id: string | null;
  space_title: string | null;
  post_id: string | null;
  actor_username: string | null;
  created_at: Date | string;
  read_at: Date | string | null;
};

function iso(v: Date | string | null | undefined): string | null {
  if (v == null) return null;
  if (v instanceof Date) return v.toISOString();
  return String(v);
}

export function mapNotification(r: AnonymousNotificationRow) {
  return {
    id: String(r.id),
    kind: r.kind,
    title: r.title,
    body: r.body,
    space_id: r.space_id,
    space_title: r.space_title,
    post_id: r.post_id,
    actor_username: r.actor_username,
    created_at: iso(r.created_at),
    read_at: iso(r.read_at),
  };
}

/** Best-effort insert — never fail the product path if the table is missing. */
export async function createAnonymousNotification(input: {
  recipientProfileId: string;
  actorProfileId?: string | null;
  kind: string;
  title?: string | null;
  body?: string | null;
  spaceId?: string | null;
  postId?: string | null;
  commentId?: string | null;
}): Promise<void> {
  const recipient = String(input.recipientProfileId || '').trim();
  const actor = input.actorProfileId ? String(input.actorProfileId).trim() : null;
  if (!recipient || (actor && actor === recipient)) return;
  try {
    await pool.query(
      `
      insert into anonymous.notifications (
        recipient_profile_id, actor_profile_id, kind, title, body,
        space_id, post_id, comment_id
      )
      values ($1::uuid, $2::uuid, $3, $4, $5, $6::uuid, $7::uuid, $8::uuid)
      `,
      [
        recipient,
        actor,
        String(input.kind || 'alert').slice(0, 40),
        input.title ? String(input.title).slice(0, 200) : null,
        input.body ? String(input.body).slice(0, 500) : null,
        input.spaceId ?? null,
        input.postId ?? null,
        input.commentId ?? null,
      ]
    );
  } catch (err: any) {
    console.warn('[anonymous/notifications/create]', err?.message ?? err);
  }
}

export async function listAnonymousNotifications(opts: {
  profileId: string;
  cursor?: string | null;
  limit?: number;
}): Promise<{ notifications: ReturnType<typeof mapNotification>[]; next_cursor: string | null; unread_count: number }> {
  const limit = Math.min(Math.max(opts.limit ?? 40, 1), 80);
  const params: unknown[] = [opts.profileId];
  let cursorClause = '';
  if (opts.cursor) {
    params.push(opts.cursor);
    cursorClause = `and n.created_at < $${params.length}::timestamptz`;
  }
  params.push(limit + 1);

  const { rows } = await pool.query<AnonymousNotificationRow>(
    `
    select
      n.id,
      n.kind,
      n.title,
      n.body,
      n.space_id,
      s.title as space_title,
      n.post_id,
      a.username as actor_username,
      n.created_at,
      n.read_at
    from anonymous.notifications n
    left join anonymous.spaces s on s.id = n.space_id
    left join anonymous.profiles a on a.id = n.actor_profile_id
    where n.recipient_profile_id = $1::uuid
      ${cursorClause}
    order by n.created_at desc
    limit $${params.length}
    `,
    params
  );

  const { rows: countRows } = await pool.query<{ count: string }>(
    `
    select count(*)::text as count
    from anonymous.notifications
    where recipient_profile_id = $1::uuid
      and read_at is null
    `,
    [opts.profileId]
  );

  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;
  const next =
    hasMore && page.length
      ? iso(page[page.length - 1]!.created_at)
      : null;

  return {
    notifications: page.map(mapNotification),
    next_cursor: next,
    unread_count: Number(countRows[0]?.count ?? 0),
  };
}

export async function markAnonymousNotificationRead(opts: {
  profileId: string;
  notificationId: string;
}): Promise<boolean> {
  const { rowCount } = await pool.query(
    `
    update anonymous.notifications
    set read_at = coalesce(read_at, now())
    where id = $1::uuid
      and recipient_profile_id = $2::uuid
    `,
    [opts.notificationId, opts.profileId]
  );
  return (rowCount ?? 0) > 0;
}

export async function markAllAnonymousNotificationsRead(opts: {
  profileId: string;
}): Promise<number> {
  const { rowCount } = await pool.query(
    `
    update anonymous.notifications
    set read_at = now()
    where recipient_profile_id = $1::uuid
      and read_at is null
    `,
    [opts.profileId]
  );
  return rowCount ?? 0;
}

export async function unreadAnonymousNotificationCount(profileId: string): Promise<number> {
  try {
    const { rows } = await pool.query<{ count: string }>(
      `
      select count(*)::text as count
      from anonymous.notifications
      where recipient_profile_id = $1::uuid
        and read_at is null
      `,
      [profileId]
    );
    return Number(rows[0]?.count ?? 0);
  } catch {
    return 0;
  }
}
