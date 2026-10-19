import { pool } from '../../../db.js';
import type { PoolClient } from '../../../db.js';
import {
  enqueueOutbox,
  kafkaEnabled,
  kafkaShadowMode,
  KafkaTopics,
  MessageEventTypes,
  type MessageDeletedPayload,
  type MessageEditedPayload,
  type MessageSentPayload,
} from '../../../kafka/index.js';
import { NotificationsService } from '../notifications/notifications.service.js';

let inboxColumnsReady: boolean | null = null;

async function supportsInboxColumns(): Promise<boolean> {
  if (inboxColumnsReady !== null) return inboxColumnsReady;
  const { rows } = await pool.query<{ ok: boolean }>(
    `
    select
      exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'conversation_members'
          and column_name = 'deleted_at'
      )
      and exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'conversation_members'
          and column_name = 'archived_at'
      ) as ok
    `
  );
  inboxColumnsReady = !!rows[0]?.ok;
  return inboxColumnsReady;
}

async function inboxVisibilityFilter(alias = 'cm'): Promise<string> {
  return (await supportsInboxColumns())
    ? `and ${alias}.deleted_at is null and ${alias}.archived_at is null`
    : '';
}

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
  updated_at?: string | null;
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
  /** Viewer-side: pending message request from a non-follower. */
  is_request?: boolean;
  request_status?: string | null;
  members: Array<{
    user_id: string;
    display_name: string | null;
    username: string | null;
    avatar_url: string | null;
    country_name: string | null;
    country_code: string | null;
    last_read_at: string | null;
  }>;
  last_message: MessageRow | null;
};

export type MessagePrivacy = 'everyone' | 'following' | 'requests';
export type ConversationInbox = 'primary' | 'requests' | 'all';

let messagePrivacyColumnReady: boolean | null = null;
let requestColumnsReady: boolean | null = null;

async function supportsMessagePrivacyColumn(): Promise<boolean> {
  if (messagePrivacyColumnReady !== null) return messagePrivacyColumnReady;
  const { rows } = await pool.query<{ ok: boolean }>(
    `
    select exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'profiles' and column_name = 'message_privacy'
    ) as ok
    `
  );
  messagePrivacyColumnReady = !!rows[0]?.ok;
  return messagePrivacyColumnReady;
}

async function supportsRequestColumns(): Promise<boolean> {
  if (requestColumnsReady !== null) return requestColumnsReady;
  const { rows } = await pool.query<{ ok: boolean }>(
    `
    select exists (
      select 1 from information_schema.columns
      where table_schema = 'public'
        and table_name = 'conversation_members'
        and column_name = 'is_request'
    ) as ok
    `
  );
  requestColumnsReady = !!rows[0]?.ok;
  return requestColumnsReady;
}

function normalizeMessagePrivacy(raw: unknown): MessagePrivacy {
  const v = String(raw ?? 'everyone').trim().toLowerCase();
  if (v === 'following' || v === 'requests') return v;
  return 'everyone';
}

export class MessagesService {
  private notifications = new NotificationsService();

  private async getMessagePrivacy(userId: string): Promise<MessagePrivacy> {
    if (!(await supportsMessagePrivacyColumn())) return 'everyone';
    try {
      const { rows } = await pool.query<{ message_privacy: string | null }>(
        `select message_privacy from public.profiles where user_id = $1 limit 1`,
        [userId]
      );
      return normalizeMessagePrivacy(rows[0]?.message_privacy);
    } catch {
      return 'everyone';
    }
  }

  /** True when followerId follows followingId. */
  private async isFollowing(followerId: string, followingId: string): Promise<boolean> {
    const { rows } = await pool.query(
      `select 1 from public.user_follows where follower_id = $1 and following_id = $2 limit 1`,
      [followerId, followingId]
    );
    return !!rows[0];
  }

  /**
   * Enforce recipient message_privacy when sender starts or messages a direct chat.
   * Returns whether the recipient membership should be flagged as a request.
   */
  private async resolveInboundPolicy(
    senderId: string,
    recipientId: string
  ): Promise<{ allow: boolean; asRequest: boolean; reason?: string }> {
    if (senderId === recipientId) return { allow: false, asRequest: false, reason: 'Invalid target.' };
    const privacy = await this.getMessagePrivacy(recipientId);
    const recipientFollowsSender = await this.isFollowing(recipientId, senderId);
    if (recipientFollowsSender) {
      return { allow: true, asRequest: false };
    }
    if (privacy === 'everyone') {
      return { allow: true, asRequest: false };
    }
    if (privacy === 'following') {
      return {
        allow: false,
        asRequest: false,
        reason: 'This person only accepts messages from people they follow.',
      };
    }
    // requests — non-followers land in Message Requests
    return { allow: true, asRequest: true };
  }

  async listConversations(
    userId: string,
    limit: number,
    inbox: ConversationInbox = 'primary'
  ): Promise<ConversationRow[]> {
    const safeLimit = Math.max(1, Math.min(50, limit || 20));
    const inboxFilter = await inboxVisibilityFilter('cm');
    const hasRequestCols = await supportsRequestColumns();
    const folder = String(inbox || 'primary').toLowerCase() as ConversationInbox;

    let requestFilter = '';
    if (hasRequestCols) {
      if (folder === 'requests') {
        requestFilter = `and coalesce(cm.is_request, false) = true and coalesce(cm.request_status, 'pending') = 'pending'`;
      } else if (folder === 'primary') {
        requestFilter = `and (
          coalesce(cm.is_request, false) = false
          or coalesce(cm.request_status, '') = 'accepted'
        )`;
      }
    } else if (folder === 'requests') {
      return [];
    }

    const requestSelect = hasRequestCols
      ? `, coalesce(cm.is_request, false) as is_request, cm.request_status`
      : `, false as is_request, null::text as request_status`;

    const { rows } = await pool.query(
      `
      select
        c.*
        ${requestSelect},
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'user_id', pr.user_id,
                'display_name', pr.display_name,
                'username', pr.username,
                'avatar_url', pr.avatar_url,
                'country_name', pr.country_name,
                'country_code', pr.country_code,
                'last_read_at', cm2.last_read_at
              )
            )
            from public.conversation_members cm2
            left join public.profiles pr on pr.user_id = cm2.user_id
            where cm2.conversation_id = c.id
              and cm2.user_id is not null
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
            'updated_at', m.updated_at,
            'sender', case
              when pr2.user_id is null then null
              else jsonb_build_object(
                'user_id', pr2.user_id,
                'display_name', pr2.display_name,
                'username', pr2.username,
                'avatar_url', pr2.avatar_url,
                'country_name', pr2.country_name,
                'country_code', pr2.country_code
              )
            end
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
        ${inboxFilter}
        ${requestFilter}
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
    const safeLimit = Math.max(1, Math.min(500, limit || 30));
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
      order by m.created_at desc
      limit $2
      `,
      params
    );

    return rows.reverse() as MessageRow[];
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

    const policy = await this.resolveInboundPolicy(userId, targetId);
    if (!policy.allow) {
      throw new Error(policy.reason || 'MESSAGE_PRIVACY_DENIED');
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

      const hasRequestCols = await supportsRequestColumns();
      if (hasRequestCols && policy.asRequest) {
        // Sender: normal membership. Recipient: pending request.
        await client.query(
          `
          insert into public.conversation_members (conversation_id, user_id, is_request, request_status)
          values
            ($1, $2, false, null),
            ($1, $3, true, 'pending')
          `,
          [convoId, userId, targetId]
        );
      } else {
        await client.query(
          `
          insert into public.conversation_members (conversation_id, user_id)
          values ($1, $2), ($1, $3)
          `,
          [convoId, userId, targetId]
        );
      }

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

  async acceptMessageRequest(conversationId: string, userId: string): Promise<ConversationRow> {
    if (!(await supportsRequestColumns())) {
      throw new Error('Message requests are not available yet.');
    }
    await this.ensureMember(conversationId, userId);
    const { rowCount } = await pool.query(
      `
      update public.conversation_members
      set is_request = false, request_status = 'accepted'
      where conversation_id = $1 and user_id = $2 and is_request = true
      `,
      [conversationId, userId]
    );
    if (!rowCount) throw new Error('No pending message request.');
    const convo = await this.conversationById(conversationId, userId);
    if (!convo) throw new Error('Conversation not found.');
    return convo;
  }

  async declineMessageRequest(conversationId: string, userId: string): Promise<boolean> {
    if (!(await supportsRequestColumns())) {
      throw new Error('Message requests are not available yet.');
    }
    await this.ensureMember(conversationId, userId);
    await pool.query(
      `
      update public.conversation_members
      set request_status = 'declined', is_request = true
      where conversation_id = $1 and user_id = $2
      `,
      [conversationId, userId]
    );
    // Soft-hide from recipient inbox (reuse deleted_at when available).
    if (await supportsInboxColumns()) {
      await pool.query(
        `
        update public.conversation_members
        set deleted_at = now()
        where conversation_id = $1 and user_id = $2
        `,
        [conversationId, userId]
      );
    }
    return true;
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

      // Block sends into declined request threads; re-check following-only for DMs.
      if (await supportsRequestColumns()) {
        const declined = await client.query(
          `
          select 1
          from public.conversation_members
          where conversation_id = $1
            and user_id <> $2
            and coalesce(request_status, '') = 'declined'
          limit 1
          `,
          [conversationId, userId]
        );
        if (declined.rows[0]) {
          throw new Error('This person declined the message request.');
        }
      }
      const others = await client.query<{ user_id: string }>(
        `
        select user_id
        from public.conversation_members
        where conversation_id = $1 and user_id <> $2
        `,
        [conversationId, userId]
      );
      if (others.rows.length === 1) {
        const recipientId = others.rows[0].user_id;
        const prior = await client.query(
          `
          select 1 from public.messages
          where conversation_id = $1 and sender_id = $2
          limit 1
          `,
          [conversationId, userId]
        );
        if (!prior.rows[0]) {
          const policy = await this.resolveInboundPolicy(userId, recipientId);
          if (!policy.allow) {
            throw new Error(policy.reason || 'MESSAGE_PRIVACY_DENIED');
          }
          if (policy.asRequest && (await supportsRequestColumns())) {
            await client.query(
              `
              update public.conversation_members
              set is_request = true, request_status = 'pending'
              where conversation_id = $1 and user_id = $2
                and coalesce(request_status, '') is distinct from 'accepted'
              `,
              [conversationId, recipientId]
            );
          }
        }
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

      const senderName =
        message.sender?.display_name || message.sender?.username || 'New message';
      const preview = String(message.body ?? '').trim().slice(0, 140);
      const isCallLog = preview.startsWith('__call__|');
      const isReaction = preview.startsWith('__react__|');

      if (await supportsInboxColumns()) {
        await client.query(
          `
          update public.conversation_members
          set archived_at = null, deleted_at = null
          where conversation_id = $1 and user_id <> $2
          `,
          [conversationId, userId]
        );
      }

      const recipientIds = otherMembers.rows.map((r) => r.user_id).filter(Boolean);

      // Transactional outbox → Kafka (when enabled). Same DB transaction as the insert.
      let outboxEnqueued = false;
      if (kafkaEnabled()) {
        const sentPayload: MessageSentPayload = {
          messageId: message.id,
          conversationId,
          senderId: userId,
          body: String(message.body ?? ''),
          mediaType: message.media_type ?? null,
          mediaPath: message.media_path ?? null,
          senderName,
          preview,
          recipientIds,
          isCallLog,
          isReaction,
        };
        try {
          await enqueueOutbox(client, {
            topic: KafkaTopics.MESSAGES,
            partitionKey: conversationId,
            eventType: MessageEventTypes.Sent,
            payload: sentPayload as unknown as Record<string, unknown>,
          });
          outboxEnqueued = true;
        } catch (err) {
          // Table missing or outbox failure — fall back to inline notify.
          console.warn('[messages] outbox enqueue failed', err);
        }
      }

      // Inline notify when Kafka is off, shadow mode, or outbox failed.
      const useInlineNotify = !kafkaEnabled() || kafkaShadowMode() || !outboxEnqueued;
      if (useInlineNotify && !isCallLog && !isReaction) {
        for (const row of otherMembers.rows) {
          try {
            await this.notifications.notifyMessage(row.user_id, userId, conversationId, {
              senderName,
              preview,
            });
          } catch {}
        }
      }

      return message;
    });
  }

  async updateMessage(messageId: string, userId: string, body: string): Promise<MessageRow> {
    return await this.withAuthClient(userId, async (client) => {
      const trimmed = String(body ?? '').trim();
      if (!trimmed) throw new Error('Message is required.');

      const { rows } = await client.query<{ id: string }>(
        `
        update public.messages
        set body = $2, updated_at = now()
        where id = $1 and sender_id = $3
        returning id
        `,
        [messageId, trimmed, userId]
      );

      const updatedId = rows[0]?.id ?? null;
      if (!updatedId) throw new Error('MESSAGE_NOT_FOUND');

      const message = await this.messageById(updatedId, client);
      if (!message) throw new Error('Message not found.');

      if (kafkaEnabled()) {
        const editedPayload: MessageEditedPayload = {
          messageId: message.id,
          conversationId: message.conversation_id,
          senderId: userId,
          body: String(message.body ?? ''),
          preview: String(message.body ?? '').trim().slice(0, 140),
        };
        try {
          await enqueueOutbox(client, {
            topic: KafkaTopics.MESSAGES,
            partitionKey: message.conversation_id,
            eventType: MessageEventTypes.Edited,
            payload: editedPayload as unknown as Record<string, unknown>,
          });
        } catch (err) {
          console.warn('[messages] outbox enqueue (edit) failed', err);
        }
      }

      return message;
    });
  }

  async deleteMessage(messageId: string, userId: string): Promise<boolean> {
    return await this.withAuthClient(userId, async (client) => {
      const { rows } = await client.query<{ conversation_id: string }>(
        `
        delete from public.messages
        where id = $1 and sender_id = $2
        returning conversation_id
        `,
        [messageId, userId]
      );

      const convoId = rows[0]?.conversation_id ?? null;
      if (!convoId) return false;

      await client.query(
        `
        update public.conversations
        set updated_at = now(),
            last_message_at = (
              select max(created_at)
              from public.messages
              where conversation_id = $1
            )
        where id = $1
        `,
        [convoId]
      );

      if (kafkaEnabled()) {
        const deletedPayload: MessageDeletedPayload = {
          messageId,
          conversationId: convoId,
          senderId: userId,
        };
        try {
          await enqueueOutbox(client, {
            topic: KafkaTopics.MESSAGES,
            partitionKey: convoId,
            eventType: MessageEventTypes.Deleted,
            payload: deletedPayload as unknown as Record<string, unknown>,
          });
        } catch (err) {
          console.warn('[messages] outbox enqueue (delete) failed', err);
        }
      }

      return true;
    });
  }

  async getConversationById(conversationId: string, userId: string): Promise<ConversationRow | null> {
    if (!conversationId) return null;
    return await this.conversationById(conversationId, userId);
  }

  async archiveConversation(conversationId: string, userId: string): Promise<boolean> {
    await this.ensureMember(conversationId, userId);
    if (!(await supportsInboxColumns())) return true;
    const { rowCount } = await pool.query(
      `
      update public.conversation_members
      set archived_at = now(), deleted_at = null
      where conversation_id = $1 and user_id = $2
      `,
      [conversationId, userId]
    );
    return (rowCount ?? 0) > 0;
  }

  async deleteConversation(conversationId: string, userId: string): Promise<boolean> {
    await this.ensureMember(conversationId, userId);
    if (!(await supportsInboxColumns())) return true;
    const { rowCount } = await pool.query(
      `
      update public.conversation_members
      set deleted_at = now(), archived_at = null
      where conversation_id = $1 and user_id = $2
      `,
      [conversationId, userId]
    );
    return (rowCount ?? 0) > 0;
  }

  async unreadCount(userId: string): Promise<number> {
    const inboxFilter = await inboxVisibilityFilter('cm');
    const { rows } = await pool.query<{ count: string }>(
      `
      select count(*) as count
      from public.messages m
      join public.conversation_members cm on cm.conversation_id = m.conversation_id
      where cm.user_id = $1
        ${inboxFilter}
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
    const hasRequestCols = await supportsRequestColumns();
    const requestSelect = hasRequestCols
      ? `, coalesce(cm.is_request, false) as is_request, cm.request_status`
      : `, false as is_request, null::text as request_status`;
    const { rows } = await pool.query(
      `
      select
        c.*
        ${requestSelect},
        coalesce(
          (
            select jsonb_agg(
              jsonb_build_object(
                'user_id', pr.user_id,
                'display_name', pr.display_name,
                'username', pr.username,
                'avatar_url', pr.avatar_url,
                'country_name', pr.country_name,
                'country_code', pr.country_code,
                'last_read_at', cm2.last_read_at
              )
            )
            from public.conversation_members cm2
            left join public.profiles pr on pr.user_id = cm2.user_id
            where cm2.conversation_id = c.id
              and cm2.user_id is not null
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
            'updated_at', m.updated_at,
            'sender', case
              when pr2.user_id is null then null
              else jsonb_build_object(
                'user_id', pr2.user_id,
                'display_name', pr2.display_name,
                'username', pr2.username,
                'avatar_url', pr2.avatar_url,
                'country_name', pr2.country_name,
                'country_code', pr2.country_code
              )
            end
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
