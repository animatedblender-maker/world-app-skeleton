import { pool } from '../../../db.js';

export class NotificationsService {
  async listForUser(userId, limit, before) {
    const safeLimit = Math.max(1, Math.min(100, limit || 40));
    const params = [userId, safeLimit];
    const beforeClause = before ? `and n.created_at < $3::timestamptz` : '';
    if (before) params.push(before);

    const { rows } = await pool.query(
      `
      select
        n.*,
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url
        ) as actor
      from public.notifications n
      left join public.profiles pr on pr.user_id = n.actor_id
      where n.user_id = $1
        ${beforeClause}
      order by n.created_at desc
      limit $2
      `,
      params
    );

    return rows;
  }

  async unreadCount(userId) {
    const { rows } = await pool.query(
      `
      select count(*)::int as total
      from public.notifications
      where user_id = $1 and read_at is null
      `,
      [userId]
    );
    return rows[0]?.total ?? 0;
  }

  async markRead(userId, id) {
    const { rows } = await pool.query(
      `
      update public.notifications
      set read_at = coalesce(read_at, now())
      where id = $1 and user_id = $2
      returning id
      `,
      [id, userId]
    );
    return !!rows[0]?.id;
  }

  async markAllRead(userId) {
    const { rowCount } = await pool.query(
      `
      update public.notifications
      set read_at = now()
      where user_id = $1 and read_at is null
      `,
      [userId]
    );
    return rowCount ?? 0;
  }

  async notifyFollow(targetId, followerId) {
    if (!targetId || !followerId || targetId === followerId) return;
    await pool.query(
      `
      insert into public.notifications
        (user_id, actor_id, type, entity_type, entity_id)
      values
        ($1, $2, 'follow', 'user', $2)
      `,
      [targetId, followerId]
    );
  }

  async notifyPostLike(targetId, actorId, postId) {
    if (!targetId || !actorId || !postId || targetId === actorId) return;
    await pool.query(
      `
      insert into public.notifications
        (user_id, actor_id, type, entity_type, entity_id)
      values
        ($1, $2, 'like', 'post', $3)
      `,
      [targetId, actorId, postId]
    );
  }

  async notifyPostComment(targetId, actorId, postId) {
    if (!targetId || !actorId || !postId || targetId === actorId) return;
    await pool.query(
      `
      insert into public.notifications
        (user_id, actor_id, type, entity_type, entity_id)
      values
        ($1, $2, 'comment', 'post', $3)
      `,
      [targetId, actorId, postId]
    );
  }
}
