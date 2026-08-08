import { pool } from '../../../db.js';

export type ChannelMemberRole = 'owner' | 'admin';

export type PostAuthorRow = {
  user_id: string;
  display_name: string | null;
  username: string | null;
  avatar_url: string | null;
  country_name: string | null;
  country_code: string | null;
};

export type ChannelRow = {
  id: string;
  owner_user_id: string;
  name: string;
  handle: string | null;
  about: string | null;
  avatar_url: string | null;
  created_at: string;
  updated_at: string;
  owner: PostAuthorRow | null;
  my_role: ChannelMemberRole | null;
  video_count: number;
};

export type ChannelMemberRow = {
  channel_id: string;
  user_id: string;
  role: ChannelMemberRole;
  invited_by: string | null;
  created_at: string;
  profile: PostAuthorRow | null;
};

type CreateChannelInput = {
  name: string;
  about?: string | null;
  avatar_url?: string | null;
  handle?: string | null;
};

type UpdateChannelInput = {
  name?: string | null;
  about?: string | null;
  avatar_url?: string | null;
  handle?: string | null;
};

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    value.trim()
  );
}

function cleanName(raw: string | null | undefined): string {
  return String(raw ?? '').trim().slice(0, 80);
}

function cleanHandle(raw: string | null | undefined): string | null {
  const h = String(raw ?? '')
    .trim()
    .toLowerCase()
    .replace(/^@+/, '')
    .replace(/[^a-z0-9_]/g, '')
    .slice(0, 32);
  return h.length ? h : null;
}

const CHANNEL_SELECT = `
  select
    c.id,
    c.owner_user_id,
    c.name,
    c.handle,
    c.about,
    c.avatar_url,
    c.created_at,
    c.updated_at,
    case
      when pr.user_id is null then null
      else jsonb_build_object(
        'user_id', pr.user_id,
        'display_name', pr.display_name,
        'username', pr.username,
        'avatar_url', pr.avatar_url,
        'country_name', pr.country_name,
        'country_code', pr.country_code
      )
    end as owner,
    (
      select m.role
      from public.channel_members m
      where m.channel_id = c.id and m.user_id = $2::uuid
      limit 1
    ) as my_role,
    (
      select count(*)::int
      from public.posts p
      where p.channel_id = c.id
        and p.channel_hidden_at is null
        and coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted')
        and p.media_type in ('video', 'reel')
    ) as video_count
  from public.channels c
  left join public.profiles pr on pr.user_id = c.owner_user_id
`;

export class ChannelsService {
  async assertAdminOrOwner(channelId: string, userId: string): Promise<void> {
    const { rows } = await pool.query<{ ok: boolean }>(
      `select public.is_channel_admin_or_owner($1::uuid, $2::uuid) as ok`,
      [channelId, userId]
    );
    if (!rows[0]?.ok) {
      throw new Error('CHANNEL_FORBIDDEN');
    }
  }

  async assertOwner(channelId: string, userId: string): Promise<void> {
    const { rows } = await pool.query<{ ok: boolean }>(
      `select public.is_channel_owner($1::uuid, $2::uuid) as ok`,
      [channelId, userId]
    );
    if (!rows[0]?.ok) {
      throw new Error('CHANNEL_OWNER_REQUIRED');
    }
  }

  async myChannel(userId: string): Promise<ChannelRow | null> {
    const { rows } = await pool.query(
      `${CHANNEL_SELECT}
       where c.owner_user_id = $1::uuid
       limit 1`,
      [userId, userId]
    );
    return (rows[0] as ChannelRow) ?? null;
  }

  async channelById(channelId: string, viewerId: string | null): Promise<ChannelRow | null> {
    if (!isUuid(channelId)) return null;
    const { rows } = await pool.query(
      `${CHANNEL_SELECT}
       where c.id = $1::uuid
       limit 1`,
      [channelId, viewerId]
    );
    return (rows[0] as ChannelRow) ?? null;
  }

  async channelByOwner(ownerUserId: string, viewerId: string | null): Promise<ChannelRow | null> {
    if (!isUuid(ownerUserId)) return null;
    const { rows } = await pool.query(
      `${CHANNEL_SELECT}
       where c.owner_user_id = $1::uuid
       limit 1`,
      [ownerUserId, viewerId]
    );
    return (rows[0] as ChannelRow) ?? null;
  }

  async channelByHandle(handle: string, viewerId: string | null): Promise<ChannelRow | null> {
    const h = cleanHandle(handle);
    if (!h) return null;
    const { rows } = await pool.query(
      `${CHANNEL_SELECT}
       where lower(c.handle) = $1
       limit 1`,
      [h, viewerId]
    );
    return (rows[0] as ChannelRow) ?? null;
  }

  async channelsIAdmin(userId: string): Promise<ChannelRow[]> {
    const { rows } = await pool.query(
      `${CHANNEL_SELECT}
       where exists (
         select 1 from public.channel_members m
         where m.channel_id = c.id
           and m.user_id = $1::uuid
           and m.role in ('owner', 'admin')
       )
       order by c.name asc`,
      [userId, userId]
    );
    return rows as ChannelRow[];
  }

  async members(channelId: string): Promise<ChannelMemberRow[]> {
    if (!isUuid(channelId)) return [];
    const { rows } = await pool.query(
      `
      select
        m.channel_id,
        m.user_id,
        m.role,
        m.invited_by,
        m.created_at,
        case
          when pr.user_id is null then null
          else jsonb_build_object(
            'user_id', pr.user_id,
            'display_name', pr.display_name,
            'username', pr.username,
            'avatar_url', pr.avatar_url,
            'country_name', pr.country_name,
            'country_code', pr.country_code
          )
        end as profile
      from public.channel_members m
      left join public.profiles pr on pr.user_id = m.user_id
      where m.channel_id = $1::uuid
      order by
        case m.role when 'owner' then 0 else 1 end,
        m.created_at asc
      `,
      [channelId]
    );
    return rows as ChannelMemberRow[];
  }

  async createChannel(userId: string, input: CreateChannelInput): Promise<ChannelRow> {
    const name = cleanName(input.name);
    if (!name) throw new Error('CHANNEL_NAME_REQUIRED');

    const existing = await this.myChannel(userId);
    if (existing) throw new Error('CHANNEL_ALREADY_EXISTS');

    let handle = cleanHandle(input.handle);
    if (!handle) {
      const { rows: profileRows } = await pool.query<{ username: string | null }>(
        `select username from public.profiles where user_id = $1::uuid limit 1`,
        [userId]
      );
      handle = cleanHandle(profileRows[0]?.username ?? null);
    }

    const about = String(input.about ?? '').trim().slice(0, 2000) || null;
    const avatarUrl = String(input.avatar_url ?? '').trim() || null;

    try {
      const { rows } = await pool.query<{ id: string }>(
        `
        insert into public.channels (owner_user_id, name, handle, about, avatar_url)
        values ($1::uuid, $2, $3, $4, $5)
        returning id
        `,
        [userId, name, handle, about, avatarUrl]
      );
      const id = rows[0]?.id;
      if (!id) throw new Error('CHANNEL_CREATE_FAILED');

      // Dual-write living channel marker into bio for older clients.
      await this.dualWriteBioMarker(userId, name);

      const channel = await this.channelById(id, userId);
      if (!channel) throw new Error('CHANNEL_CREATE_FAILED');
      return channel;
    } catch (err: any) {
      if (String(err?.code) === '23505') {
        throw new Error('CHANNEL_HANDLE_TAKEN');
      }
      throw err;
    }
  }

  async updateChannel(
    channelId: string,
    userId: string,
    input: UpdateChannelInput
  ): Promise<ChannelRow> {
    if (!isUuid(channelId)) throw new Error('CHANNEL_NOT_FOUND');
    await this.assertAdminOrOwner(channelId, userId);

    const name =
      input.name !== undefined && input.name !== null ? cleanName(input.name) : null;
    if (input.name !== undefined && input.name !== null && !name) {
      throw new Error('CHANNEL_NAME_REQUIRED');
    }
    const handle =
      input.handle !== undefined
        ? cleanHandle(input.handle)
        : undefined;
    const about =
      input.about !== undefined
        ? String(input.about ?? '').trim().slice(0, 2000) || null
        : undefined;
    const avatarUrl =
      input.avatar_url !== undefined
        ? String(input.avatar_url ?? '').trim() || null
        : undefined;

    try {
      const { rows } = await pool.query<{ id: string }>(
        `
        update public.channels
        set
          name = coalesce($3, name),
          handle = case when $4::boolean then $5 else handle end,
          about = case when $6::boolean then $7 else about end,
          avatar_url = case when $8::boolean then $9 else avatar_url end,
          updated_at = now()
        where id = $1::uuid
        returning id
        `,
        [
          channelId,
          userId,
          name,
          handle !== undefined,
          handle ?? null,
          about !== undefined,
          about ?? null,
          avatarUrl !== undefined,
          avatarUrl ?? null,
        ]
      );
      if (!rows[0]?.id) throw new Error('CHANNEL_NOT_FOUND');
    } catch (err: any) {
      if (String(err?.code) === '23505') throw new Error('CHANNEL_HANDLE_TAKEN');
      throw err;
    }

    const channel = await this.channelById(channelId, userId);
    if (!channel) throw new Error('CHANNEL_NOT_FOUND');

    if (name) {
      await this.dualWriteBioMarker(channel.owner_user_id, name);
    }
    return channel;
  }

  async deleteChannel(channelId: string, userId: string): Promise<boolean> {
    if (!isUuid(channelId)) return false;
    await this.assertOwner(channelId, userId);
    const { rowCount } = await pool.query(
      `delete from public.channels where id = $1::uuid and owner_user_id = $2::uuid`,
      [channelId, userId]
    );
    return (rowCount ?? 0) > 0;
  }

  async addChannelAdmin(
    channelId: string,
    actorId: string,
    targetUserId: string
  ): Promise<ChannelMemberRow> {
    if (!isUuid(channelId) || !isUuid(targetUserId)) {
      throw new Error('CHANNEL_BAD_INPUT');
    }
    await this.assertAdminOrOwner(channelId, actorId);

    if (targetUserId === actorId) {
      // Owner is already a member; adding self as admin is a no-op error.
      throw new Error('CHANNEL_CANNOT_ADD_SELF');
    }

    const { rows: profileRows } = await pool.query<{ user_id: string; account_status: string | null }>(
      `
      select user_id, account_status
      from public.profiles
      where user_id = $1::uuid
      limit 1
      `,
      [targetUserId]
    );
    if (!profileRows[0]) throw new Error('USER_NOT_FOUND');
    const status = String(profileRows[0].account_status ?? 'active').toLowerCase();
    if (status && status !== 'active') throw new Error('USER_NOT_ACTIVE');

    // Never demote owner via this path.
    const { rows: ownerCheck } = await pool.query<{ owner_user_id: string }>(
      `select owner_user_id from public.channels where id = $1::uuid limit 1`,
      [channelId]
    );
    if (ownerCheck[0]?.owner_user_id === targetUserId) {
      throw new Error('CHANNEL_TARGET_IS_OWNER');
    }

    await pool.query(
      `
      insert into public.channel_members (channel_id, user_id, role, invited_by)
      values ($1::uuid, $2::uuid, 'admin', $3::uuid)
      on conflict (channel_id, user_id) do update
        set role = 'admin',
            invited_by = excluded.invited_by
      where public.channel_members.role <> 'owner'
      `,
      [channelId, targetUserId, actorId]
    );

    const members = await this.members(channelId);
    const row = members.find((m) => m.user_id === targetUserId);
    if (!row) throw new Error('CHANNEL_ADD_ADMIN_FAILED');
    return row;
  }

  async removeChannelAdmin(
    channelId: string,
    actorId: string,
    targetUserId: string
  ): Promise<boolean> {
    if (!isUuid(channelId) || !isUuid(targetUserId)) return false;
    await this.assertAdminOrOwner(channelId, actorId);

    const { rows: ownerCheck } = await pool.query<{ owner_user_id: string }>(
      `select owner_user_id from public.channels where id = $1::uuid limit 1`,
      [channelId]
    );
    if (ownerCheck[0]?.owner_user_id === targetUserId) {
      throw new Error('CHANNEL_CANNOT_REMOVE_OWNER');
    }

    const { rowCount } = await pool.query(
      `
      delete from public.channel_members
      where channel_id = $1::uuid
        and user_id = $2::uuid
        and role = 'admin'
      `,
      [channelId, targetUserId]
    );
    return (rowCount ?? 0) > 0;
  }

  async transferChannelOwnership(
    channelId: string,
    actorId: string,
    newOwnerUserId: string
  ): Promise<ChannelRow> {
    if (!isUuid(channelId) || !isUuid(newOwnerUserId)) {
      throw new Error('CHANNEL_BAD_INPUT');
    }
    await this.assertOwner(channelId, actorId);
    if (newOwnerUserId === actorId) {
      const current = await this.channelById(channelId, actorId);
      if (!current) throw new Error('CHANNEL_NOT_FOUND');
      return current;
    }

    // New owner must not already own another channel (1:1).
    const { rows: existing } = await pool.query(
      `select id from public.channels where owner_user_id = $1::uuid and id <> $2::uuid limit 1`,
      [newOwnerUserId, channelId]
    );
    if (existing[0]) throw new Error('CHANNEL_TARGET_ALREADY_OWNS');

    const client = await pool.connect();
    try {
      await client.query('begin');
      await client.query(
        `update public.channels set owner_user_id = $2::uuid, updated_at = now() where id = $1::uuid`,
        [channelId, newOwnerUserId]
      );
      // Promote new owner
      await client.query(
        `
        insert into public.channel_members (channel_id, user_id, role, invited_by)
        values ($1::uuid, $2::uuid, 'owner', $3::uuid)
        on conflict (channel_id, user_id) do update set role = 'owner'
        `,
        [channelId, newOwnerUserId, actorId]
      );
      // Demote previous owner to admin
      await client.query(
        `
        update public.channel_members
        set role = 'admin'
        where channel_id = $1::uuid and user_id = $2::uuid
        `,
        [channelId, actorId]
      );
      await client.query('commit');
    } catch (err) {
      await client.query('rollback');
      throw err;
    } finally {
      client.release();
    }

    const channel = await this.channelById(channelId, actorId);
    if (!channel) throw new Error('CHANNEL_NOT_FOUND');
    return channel;
  }

  async setChannelPostHidden(
    postId: string,
    actorId: string,
    hidden: boolean
  ): Promise<boolean> {
    if (!isUuid(postId)) return false;
    const { rows } = await pool.query<{ channel_id: string | null }>(
      `select channel_id from public.posts where id = $1::uuid limit 1`,
      [postId]
    );
    const channelId = rows[0]?.channel_id;
    if (!channelId) throw new Error('POST_NOT_ON_CHANNEL');
    await this.assertAdminOrOwner(channelId, actorId);

    if (hidden) {
      await pool.query(
        `
        update public.posts
        set channel_hidden_at = now(), channel_hidden_by = $2::uuid, updated_at = now()
        where id = $1::uuid
        `,
        [postId, actorId]
      );
    } else {
      await pool.query(
        `
        update public.posts
        set channel_hidden_at = null, channel_hidden_by = null, updated_at = now()
        where id = $1::uuid
        `,
        [postId]
      );
    }
    return true;
  }

  async deleteChannelComment(commentId: string, actorId: string): Promise<boolean> {
    if (!isUuid(commentId)) return false;

    const { rows } = await pool.query<{
      id: string;
      author_id: string;
      post_id: string;
      channel_id: string | null;
    }>(
      `
      select
        c.id,
        c.author_id,
        c.post_id,
        p.channel_id
      from public.post_comments c
      join public.posts p on p.id = c.post_id
      where c.id = $1::uuid
      limit 1
      `,
      [commentId]
    );
    const comment = rows[0];
    if (!comment) return false;

    const isAuthor = comment.author_id === actorId;
    let isStaff = false;
    if (comment.channel_id) {
      const { rows: staffRows } = await pool.query<{ ok: boolean }>(
        `select public.is_channel_admin_or_owner($1::uuid, $2::uuid) as ok`,
        [comment.channel_id, actorId]
      );
      isStaff = !!staffRows[0]?.ok;
    }
    if (!isAuthor && !isStaff) throw new Error('COMMENT_FORBIDDEN');

    const client = await pool.connect();
    try {
      await client.query('begin');
      await client.query(`delete from public.post_comment_likes where comment_id = $1::uuid`, [
        commentId,
      ]);
      // Also delete nested replies
      await client.query(`delete from public.post_comments where parent_id = $1::uuid`, [
        commentId,
      ]);
      const del = await client.query(`delete from public.post_comments where id = $1::uuid`, [
        commentId,
      ]);
      if ((del.rowCount ?? 0) > 0) {
        await client.query(
          `
          update public.posts
          set comment_count = greatest(0, comment_count - 1), updated_at = now()
          where id = $1::uuid
          `,
          [comment.post_id]
        );
      }
      await client.query('commit');
      return (del.rowCount ?? 0) > 0;
    } catch (err) {
      await client.query('rollback');
      throw err;
    } finally {
      client.release();
    }
  }

  /** Resolve channel for post-as-channel; returns owner user id. */
  async resolvePostAsChannel(
    channelId: string,
    actorId: string
  ): Promise<{ channelId: string; ownerUserId: string }> {
    if (!isUuid(channelId)) throw new Error('CHANNEL_NOT_FOUND');
    await this.assertAdminOrOwner(channelId, actorId);
    const { rows } = await pool.query<{ owner_user_id: string }>(
      `select owner_user_id from public.channels where id = $1::uuid limit 1`,
      [channelId]
    );
    if (!rows[0]) throw new Error('CHANNEL_NOT_FOUND');
    return { channelId, ownerUserId: rows[0].owner_user_id };
  }

  private async dualWriteBioMarker(userId: string, channelName: string): Promise<void> {
    const name = cleanName(channelName);
    if (!name) return;
    const { rows } = await pool.query<{ bio: string | null }>(
      `select bio from public.profiles where user_id = $1::uuid limit 1`,
      [userId]
    );
    if (!rows[0]) return;
    const raw = String(rows[0].bio ?? '');
    const displayLines = raw
      .split('\n')
      .filter((line) => !line.trim().startsWith('__living_channel__|'));
    const displayBio = displayLines.join('\n').trim();
    const next = [displayBio, `__living_channel__|name=${name}`].filter(Boolean).join('\n');
    await pool.query(
      `update public.profiles set bio = $2, updated_at = now() where user_id = $1::uuid`,
      [userId, next]
    );
  }
}
