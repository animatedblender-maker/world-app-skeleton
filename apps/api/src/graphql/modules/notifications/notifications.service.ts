import { pool } from '../../../db.js';
import { PushService } from '../../../push/push.service.js';
import { ApnsService } from '../../../push/apns.service.js';
import { PresenceService } from '../presence/presence.service.js';

type NotificationRow = {
  id: string;
  user_id: string;
  actor_id: string | null;
  type: string;
  entity_type: string | null;
  entity_id: string | null;
  read_at: string | null;
  created_at: string;
  actor: {
    user_id: string;
    display_name: string | null;
    username: string | null;
    avatar_url: string | null;
  } | null;
};

export class NotificationsService {
  private push = new PushService();
  private apns = new ApnsService();
  private presence = new PresenceService();
  async listForUser(userId: string, limit: number, before?: string | null): Promise<NotificationRow[]> {
    const safeLimit = Math.max(1, Math.min(100, limit || 40));
    const params: Array<string | number> = [userId, safeLimit];
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

    return rows as NotificationRow[];
  }

  async unreadCount(userId: string): Promise<number> {
    const { rows } = await pool.query(
      `
      select count(*)::int as total
      from public.notifications
      where user_id = $1
        and read_at is null
        and type <> 'message'
      `,
      [userId]
    );
    return rows[0]?.total ?? 0;
  }

  async markRead(userId: string, id: string): Promise<boolean> {
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

  async markConversationMessageNotificationsRead(
    userId: string,
    conversationId: string
  ): Promise<number> {
    const wantUser = String(userId || '').trim();
    const wantConversation = String(conversationId || '').trim();
    if (!wantUser || !wantConversation) return 0;

    const { rowCount } = await pool.query(
      `
      update public.notifications
      set read_at = coalesce(read_at, now())
      where user_id = $1
        and read_at is null
        and type = 'message'
        and entity_type = 'conversation'
        and entity_id = $2
      `,
      [wantUser, wantConversation]
    );
    return rowCount ?? 0;
  }

  async markAllRead(userId: string): Promise<number> {
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

  async notifyFollow(targetId: string, followerId: string): Promise<void> {
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
    await Promise.all([
      this.push.sendToUser(targetId, {
        title: 'New notification',
        body: 'Someone followed you.',
        url: `/user/${followerId}`,
        tag: `follow:${followerId}`,
      }),
      this.apns.sendToUser(targetId, {
        title: 'New notification',
        body: 'Someone followed you.',
        data: { type: 'follow', entityId: followerId },
      }),
    ]);
  }

  async notifyPostLike(targetId: string, actorId: string, postId: string): Promise<void> {
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
    await Promise.all([
      this.push.sendToUser(targetId, {
        title: 'New notification',
        body: 'Your post got a like.',
        url: `/?post=${postId}`,
        tag: `post:${postId}`,
      }),
      this.apns.sendToUser(targetId, {
        title: 'New notification',
        body: 'Your post got a like.',
        data: { type: 'like', postId, entityId: postId },
      }),
    ]);
  }

  async notifyPostComment(targetId: string, actorId: string, postId: string): Promise<void> {
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
    await Promise.all([
      this.push.sendToUser(targetId, {
        title: 'New notification',
        body: 'New comment on your post.',
        url: `/?post=${postId}`,
        tag: `post:${postId}`,
      }),
      this.apns.sendToUser(targetId, {
        title: 'New notification',
        body: 'New comment on your post.',
        data: { type: 'comment', postId, entityId: postId },
      }),
    ]);
  }

  async notifyCommentLike(targetId: string, actorId: string, postId: string): Promise<void> {
    if (!targetId || !actorId || !postId || targetId === actorId) return;
    await pool.query(
      `
      insert into public.notifications
        (user_id, actor_id, type, entity_type, entity_id)
      values
        ($1, $2, 'comment_like', 'post', $3)
      `,
      [targetId, actorId, postId]
    );
    await Promise.all([
      this.push.sendToUser(targetId, {
        title: 'New notification',
        body: 'Someone liked your comment.',
        url: `/?post=${postId}`,
        tag: `post:${postId}`,
      }),
      this.apns.sendToUser(targetId, {
        title: 'New notification',
        body: 'Someone liked your comment.',
        data: { type: 'comment_like', postId, entityId: postId },
      }),
    ]);
  }

  async notifyCommentReply(targetId: string, actorId: string, postId: string): Promise<void> {
    if (!targetId || !actorId || !postId || targetId === actorId) return;
    await pool.query(
      `
      insert into public.notifications
        (user_id, actor_id, type, entity_type, entity_id)
      values
        ($1, $2, 'comment_reply', 'post', $3)
      `,
      [targetId, actorId, postId]
    );
    await Promise.all([
      this.push.sendToUser(targetId, {
        title: 'New notification',
        body: 'New reply on your comment.',
        url: `/?post=${postId}`,
        tag: `post:${postId}`,
      }),
      this.apns.sendToUser(targetId, {
        title: 'New notification',
        body: 'New reply on your comment.',
        data: { type: 'comment_reply', postId, entityId: postId },
      }),
    ]);
  }

  async notifyMessage(
    targetId: string,
    actorId: string,
    conversationId: string,
    meta?: { senderName?: string | null; preview?: string | null }
  ): Promise<void> {
    if (!targetId || !actorId || !conversationId || targetId === actorId) return;

    const isViewingChat = await this.presence.isViewingConversation(
      targetId,
      conversationId
    );
    if (isViewingChat) return;

    await pool.query(
      `
      insert into public.notifications
        (user_id, actor_id, type, entity_type, entity_id)
      values
        ($1, $2, 'message', 'conversation', $3)
      `,
      [targetId, actorId, conversationId]
    );
    const title = meta?.senderName?.trim() || 'New message';
    const preview = meta?.preview?.trim() || 'You received a new message.';
    await Promise.all([
      this.push.sendToUser(targetId, {
        title,
        body: preview,
        url: `/messages?c=${conversationId}`,
        tag: `message:${conversationId}`,
      }),
      this.apns.sendToUser(targetId, {
        title,
        body: preview,
        data: { type: 'message', conversationId },
      }),
    ]);
  }
}
