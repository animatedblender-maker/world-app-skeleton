import { pool } from '../../../db.js';
import type { PoolClient } from '../../../db.js';
import { NotificationsService } from '../notifications/notifications.service.js';

type MessageRow = {
  id: string;
  conversation_id: string;
  sender_id: string;
  body: string;
  media_type?: string | null;
  media_path?: string | null;
  media_name?: string | null;
  media_mime?: string | null;
  media_size?: number | null;
  created_at: string;
  sender: {
    user_id: string;
    display_name: string | null;
    username: string | null;
    avatar_url: string | null;
    country_name: string | null;
    country_code: string | null;
  } | null;
};

type ConversationRow = {
  id: string;
  is_direct: boolean;
  created_at: string;
  updated_at: string;
  last_message_at: string | null;
  members: Array<{
    user_id: string;
    display_name: string | null;
    username: string | null;
    avatar_url: string | null;
    country_name: string | null;
    country_code: string | null;
  }>;
  last_message: MessageRow | null;
};

export class MessagesService {
  private notifications = new NotificationsService();

  async listConversations(userId: string, limit: number): Promise<ConversationRow[]> {
    const safeLimit = Math.max(1, Math.min(50, limit || 20));
    const { rows } = await pool.query(
      `
      select
        c.*,
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'user_id', pr.user_id,
                'display_name', pr.display_name,
                'username', pr.username,
                'avatar_url', pr.avatar_url,
                'country_name', pr.country_name,
                'country_code', pr.country_code
              )
            )
            from public.conversation_members cm2
            left join public.profiles pr on pr.user_id = cm2.user_id
            where cm2.conversation_id = c.id
          ),
          '[]'::jsonb
        ) as members,
        (
          select jsonb_build_object(
            'id', m.id,
            'conversation_id', m.conversation_id,
            'sender_id', m.sender_id,
            'body', m.body,
            'media_type', m.media_type,
            'media_path', m.media_path,
            'media_name', m.media_name,
            'media_mime', m.media_mime,
            'media_size', m.media_size,
            'created_at', m.created_at,
            'sender', jsonb_build_object(
              'user_id', pr2.user_id,
              'display_name', pr2.display_name,
              'username', pr2.username,
              'avatar_url', pr2.avatar_url,
              'country_name', pr2.country_name,
              'country_code', pr2.country_code
            )
          )
          from public.messages m
          left join public.profiles pr2 on pr2.user_id = m.sender_id
          where m.conversation_id = c.id
          order by m.created_at desc
          limit 1
        ) as last_message
      from public.conversations c
      join public.conversation_members cm on cm.conversation_id = c.id
      where cm.user_id = $1
      order by coalesce(c.last_message_at, c.updated_at, c.created_at) desc
      limit $2
      `,
      [userId, safeLimit]
    );

    return rows as ConversationRow[];
  }

  async messagesByConversation(
    conversationId: string,
    limit: number,
    before: string | null,
    userId: string
  ): Promise<MessageRow[]> {
    await this.ensureMember(conversationId, userId);
    if (!before) {
      await pool.query(
        `
        update public.conversation_members
        set last_read_at = now()
        where conversation_id = $1 and user_id = $2
        `,
        [conversationId, userId]
      );
    }
    const safeLimit = Math.max(1, Math.min(100, limit || 30));
    const params: Array<string | number> = [conversationId, safeLimit];
    const beforeClause = before ? `and m.created_at < $3::timestamptz` : '';
    if (before) params.push(before);

    const { rows } = await pool.query(
      `
      select
        m.*,
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as sender
      from public.messages m
      left join public.profiles pr on pr.user_id = m.sender_id
      where m.conversation_id = $1
        ${beforeClause}
      order by m.created_at asc
      limit $2
      `,
      params
    );

    return rows as MessageRow[];
  }

  async startConversation(targetId: string, userId: string): Promise<ConversationRow> {
    if (!targetId || targetId === userId) {
      throw new Error('Invalid target.');
    }

    const existing = await pool.query<{ id: string }>(
      `
      select c.id
      from public.conversations c
      join public.conversation_members m1 on m1.conversation_id = c.id and m1.user_id = $1
      join public.conversation_members m2 on m2.conversation_id = c.id and m2.user_id = $2
      where c.is_direct = true
      limit 1
      `,
      [userId, targetId]
    );

    const foundId = existing.rows[0]?.id;
    if (foundId) {
      const convo = await this.conversationById(foundId, userId);
      if (!convo) throw new Error('Conversation not found.');
      return convo;
    }

    const client = await pool.connect();
    let convoId: string | null = null;
    try {
      await client.query('begin');
      const inserted = await client.query<{ id: string }>(
        `insert into public.conversations (is_direct) values (true) returning id`,
        []
      );
      convoId = inserted.rows[0]?.id ?? null;
      if (!convoId) throw new Error('Failed to create conversation.');

      await client.query(
        `
        insert into public.conversation_members (conversation_id, user_id)
        values ($1, $2), ($1, $3)
        `,
        [convoId, userId, targetId]
      );

      await client.query('commit');
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }

    const convo = await this.conversationById(convoId, userId);
    if (!convo) throw new Error('Conversation not found.');
    return convo;
  }

  async sendMessage(
    conversationId: string,
    userId: string,
    payload: {
      body?: string | null;
      media_type?: string | null;
      media_path?: string | null;
      media_name?: string | null;
      media_mime?: string | null;
      media_size?: number | null;
    }
  ): Promise<MessageRow> {
    return await this.withAuthClient(userId, async (client) => {
      const trimmed = String(payload?.body ?? '').trim();
      const mediaPath = payload?.media_path ?? null;
      if (!trimmed && !mediaPath) throw new Error('Message is required.');

      const member = await client.query(
        `
        select 1
        from public.conversation_members
        where conversation_id = $1 and user_id = $2
        limit 1
        `,
        [conversationId, userId]
      );
      if (!member.rows[0]) {
        throw new Error('CONVERSATION_ACCESS_DENIED');
      }

      const { rows } = await client.query<{ id: string }>(
        `
        insert into public.messages (
          conversation_id,
          sender_id,
          body,
          media_type,
          media_path,
          media_name,
          media_mime,
          media_size
        )
        values ($1, $2, $3, $4, $5, $6, $7, $8)
        returning id
        `,
        [
          conversationId,
          userId,
          trimmed,
          payload?.media_type ?? null,
          mediaPath,
          payload?.media_name ?? null,
          payload?.media_mime ?? null,
          payload?.media_size ?? null,
        ]
      );

      const messageId = rows[0]?.id ?? null;
      if (!messageId) throw new Error('Failed to send message.');

      await client.query(
        `
        update public.conversations
        set updated_at = now(), last_message_at = now()
        where id = $1
        `,
        [conversationId]
      );

      await client.query(
        `
        update public.conversation_members
        set last_read_at = now()
        where conversation_id = $1 and user_id = $2
        `,
        [conversationId, userId]
      );

      const message = await this.messageById(messageId, client);
      if (!message) throw new Error('Message not found.');

      const otherMembers = await client.query<{ user_id: string }>(
        `
        select user_id
        from public.conversation_members
        where conversation_id = $1 and user_id <> $2
        `,
        [conversationId, userId]
      );

      for (const row of otherMembers.rows) {
        try {
          await this.notifications.notifyMessage(row.user_id, userId, conversationId);
        } catch {}
      }

      return message;
    });
  }

  async getConversationById(conversationId: string, userId: string): Promise<ConversationRow | null> {
    if (!conversationId) return null;
    return await this.conversationById(conversationId, userId);
  }

  async unreadCount(userId: string): Promise<number> {
    const { rows } = await pool.query<{ count: string }>(
      `
      select count(*) as count
      from public.messages m
      join public.conversation_members cm on cm.conversation_id = m.conversation_id
      where cm.user_id = $1
        and m.sender_id <> $1
        and (cm.last_read_at is null or m.created_at > cm.last_read_at)
      `,
      [userId]
    );

    return Number(rows[0]?.count ?? 0);
  }

  private async ensureMember(conversationId: string, userId: string): Promise<void> {
    const { rows } = await pool.query(
      `
      select 1
      from public.conversation_members
      where conversation_id = $1 and user_id = $2
      limit 1
      `,
      [conversationId, userId]
    );
    if (!rows[0]) {
      throw new Error('CONVERSATION_ACCESS_DENIED');
    }
  }

  private async conversationById(conversationId: string, userId: string): Promise<ConversationRow | null> {
    const { rows } = await pool.query(
      `
      select
        c.*,
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'user_id', pr.user_id,
                'display_name', pr.display_name,
                'username', pr.username,
                'avatar_url', pr.avatar_url,
                'country_name', pr.country_name,
                'country_code', pr.country_code
              )
            )
            from public.conversation_members cm2
            left join public.profiles pr on pr.user_id = cm2.user_id
            where cm2.conversation_id = c.id
          ),
          '[]'::jsonb
        ) as members,
        (
          select jsonb_build_object(
            'id', m.id,
            'conversation_id', m.conversation_id,
            'sender_id', m.sender_id,
            'body', m.body,
            'media_type', m.media_type,
            'media_path', m.media_path,
            'media_name', m.media_name,
            'media_mime', m.media_mime,
            'media_size', m.media_size,
            'created_at', m.created_at,
            'sender', jsonb_build_object(
              'user_id', pr2.user_id,
              'display_name', pr2.display_name,
              'username', pr2.username,
              'avatar_url', pr2.avatar_url,
              'country_name', pr2.country_name,
              'country_code', pr2.country_code
            )
          )
          from public.messages m
          left join public.profiles pr2 on pr2.user_id = m.sender_id
          where m.conversation_id = c.id
          order by m.created_at desc
          limit 1
        ) as last_message
      from public.conversations c
      join public.conversation_members cm on cm.conversation_id = c.id
      where c.id = $1 and cm.user_id = $2
      limit 1
      `,
      [conversationId, userId]
    );

    return (rows[0] as ConversationRow) ?? null;
  }

  private async messageById(
    messageId: string,
    client?: PoolClient | null
  ): Promise<MessageRow | null> {
    const executor = client ?? pool;
    const { rows } = await executor.query(
      `
      select
        m.*,
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as sender
      from public.messages m
      left join public.profiles pr on pr.user_id = m.sender_id
      where m.id = $1
      limit 1
      `,
      [messageId]
    );

    return (rows[0] as MessageRow) ?? null;
  }

  private async withAuthClient<T>(userId: string, fn: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await pool.connect();
    try {
      await client.query('begin');
      await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [userId]);
      await client.query(`select set_config('request.jwt.claim.role', 'authenticated', true)`);
      const result = await fn(client);
      await client.query('commit');
      return result;
    } catch (err) {
      await client.query('rollback');
      throw err;
    } finally {
      client.release();
    }
  }
}
