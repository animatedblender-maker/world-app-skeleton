import { pool } from '../../../db.js';

export type AuthedUser = {
  id: string;
  email?: string;
  role?: string;
};

const PLATFORMS = ['netflix', 'apple_music', 'apple_tv', 'spotify', 'disney'] as const;
export type PlatformSlug = (typeof PLATFORMS)[number];

const NOW_PLAYING_TTL_SECONDS = Number(process.env.STREAMING_NOW_PLAYING_TTL_SECONDS ?? 1800);
const PRESENCE_TTL_SECONDS = Number(process.env.PRESENCE_TTL_SECONDS ?? 70);

export type StreamingConnection = {
  platform: string;
  is_linked: boolean;
  sharing_enabled: boolean;
  linked_at: string | null;
};

export type NowPlayingItem = {
  id: string;
  platform: string;
  title: string;
  subtitle: string | null;
  moment_label: string | null;
  progress_ms: number;
  duration_ms: number;
  progress: number;
  progress_label: string;
  is_sharing: boolean;
  updated_at: string;
};

export type FriendStreamingActivity = {
  user_id: string;
  display_name: string | null;
  username: string | null;
  avatar_url: string | null;
  platform: string;
  title: string;
  detail: string;
  is_live: boolean;
};

export type MomentRoomComment = {
  id: string;
  author_id: string;
  author_name: string;
  body: string;
  reactions: number;
  created_at: string;
};

export type MomentRoomItem = {
  room_key: string;
  platform: string;
  show_title: string;
  episode_label: string;
  timestamp_label: string;
  active_friends: number;
  heat: number;
  preview_comments: MomentRoomComment[];
};

function assertPlatform(platform: string): PlatformSlug {
  const normalized = String(platform || '').trim().toLowerCase();
  if (!PLATFORMS.includes(normalized as PlatformSlug)) {
    throw new Error(`Unsupported platform: ${platform}`);
  }
  return normalized as PlatformSlug;
}

function formatProgressLabel(progressMs: number): string {
  const totalSec = Math.max(0, Math.floor(progressMs / 1000));
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  return `${min}:${String(sec).padStart(2, '0')}`;
}

function slug(value: string): string {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48);
}

function buildRoomKey(
  platform: string,
  title: string,
  subtitle: string | null,
  progressMs: number
): { roomKey: string; timestampLabel: string } {
  const bucketMs = Math.floor(Math.max(0, progressMs) / 60000) * 60000;
  const roomKey = `${platform}:${slug(title)}:${slug(subtitle ?? '')}:${bucketMs}`;
  return { roomKey, timestampLabel: formatProgressLabel(bucketMs) };
}

export class StreamingService {
  private nowIso(): string {
    return new Date().toISOString();
  }

  async myConnections(userId: string): Promise<StreamingConnection[]> {
    const { rows } = await pool.query<{
      platform: string;
      is_linked: boolean;
      sharing_enabled: boolean;
      linked_at: string | null;
    }>(
      `
      select platform, is_linked, sharing_enabled, linked_at
      from public.streaming_platform_connections
      where user_id = $1
      `,
      [userId]
    );

    const byPlatform = new Map(rows.map((row) => [row.platform, row]));

    return PLATFORMS.map((platform) => {
      const row = byPlatform.get(platform);
      return {
        platform,
        is_linked: row?.is_linked ?? false,
        sharing_enabled: row?.sharing_enabled ?? true,
        linked_at: row?.linked_at ?? null,
      };
    });
  }

  async linkPlatform(userId: string, platform: string): Promise<StreamingConnection> {
    const slugPlatform = assertPlatform(platform);
    const now = this.nowIso();

    const { rows } = await pool.query<{
      platform: string;
      is_linked: boolean;
      sharing_enabled: boolean;
      linked_at: string | null;
    }>(
      `
      insert into public.streaming_platform_connections
        (user_id, platform, is_linked, sharing_enabled, linked_at, updated_at)
      values ($1, $2, true, true, $3, $3)
      on conflict (user_id, platform) do update set
        is_linked = true,
        linked_at = coalesce(public.streaming_platform_connections.linked_at, excluded.linked_at),
        updated_at = excluded.updated_at
      returning platform, is_linked, sharing_enabled, linked_at
      `,
      [userId, slugPlatform, now]
    );

    return rows[0];
  }

  async unlinkPlatform(userId: string, platform: string): Promise<boolean> {
    const slugPlatform = assertPlatform(platform);

    await pool.query(
      `
      update public.streaming_platform_connections
      set is_linked = false,
          sharing_enabled = false,
          updated_at = now()
      where user_id = $1 and platform = $2
      `,
      [userId, slugPlatform]
    );

    await pool.query(
      `delete from public.now_playing_status where user_id = $1 and platform = $2`,
      [userId, slugPlatform]
    );

    return true;
  }

  async setPlatformSharing(
    userId: string,
    platform: string,
    enabled: boolean
  ): Promise<StreamingConnection> {
    const slugPlatform = assertPlatform(platform);
    const now = this.nowIso();

    const { rows } = await pool.query<{
      platform: string;
      is_linked: boolean;
      sharing_enabled: boolean;
      linked_at: string | null;
    }>(
      `
      insert into public.streaming_platform_connections
        (user_id, platform, is_linked, sharing_enabled, linked_at, updated_at)
      values ($1, $2, true, $3, $4, $4)
      on conflict (user_id, platform) do update set
        is_linked = true,
        sharing_enabled = excluded.sharing_enabled,
        updated_at = excluded.updated_at
      returning platform, is_linked, sharing_enabled, linked_at
      `,
      [userId, slugPlatform, enabled, now]
    );

    await pool.query(
      `
      update public.now_playing_status
      set is_sharing = $3, updated_at = now()
      where user_id = $1 and platform = $2
      `,
      [userId, slugPlatform, enabled]
    );

    return rows[0];
  }

  async myNowPlaying(userId: string): Promise<NowPlayingItem[]> {
    const { rows } = await pool.query<{
      id: string;
      platform: string;
      title: string;
      subtitle: string | null;
      moment_label: string | null;
      progress_ms: number;
      duration_ms: number;
      is_sharing: boolean;
      updated_at: string;
    }>(
      `
      select id, platform, title, subtitle, moment_label,
             progress_ms, duration_ms, is_sharing, updated_at
      from public.now_playing_status
      where user_id = $1
      order by updated_at desc
      `,
      [userId]
    );

    return rows.map((row) => this.mapNowPlaying(row));
  }

  async updateNowPlaying(
    userId: string,
    input: {
      platform: string;
      title: string;
      subtitle?: string | null;
      moment_label?: string | null;
      progress_ms: number;
      duration_ms: number;
      is_sharing?: boolean | null;
    }
  ): Promise<NowPlayingItem> {
    const slugPlatform = assertPlatform(input.platform);
    const now = this.nowIso();

    await pool.query(
      `
      insert into public.streaming_platform_connections
        (user_id, platform, is_linked, sharing_enabled, linked_at, updated_at)
      values ($1, $2, true, true, $3, $3)
      on conflict (user_id, platform) do update set
        is_linked = true,
        updated_at = excluded.updated_at
      `,
      [userId, slugPlatform, now]
    );

    const { rows } = await pool.query<{
      id: string;
      platform: string;
      title: string;
      subtitle: string | null;
      moment_label: string | null;
      progress_ms: number;
      duration_ms: number;
      is_sharing: boolean;
      updated_at: string;
    }>(
      `
      insert into public.now_playing_status
        (user_id, platform, title, subtitle, moment_label,
         progress_ms, duration_ms, is_sharing, updated_at)
      values ($1, $2, $3, $4, $5, $6, $7, coalesce($8, true), $9)
      on conflict (user_id, platform) do update set
        title = excluded.title,
        subtitle = excluded.subtitle,
        moment_label = excluded.moment_label,
        progress_ms = excluded.progress_ms,
        duration_ms = excluded.duration_ms,
        is_sharing = coalesce($8, public.now_playing_status.is_sharing),
        updated_at = excluded.updated_at
      returning id, platform, title, subtitle, moment_label,
                progress_ms, duration_ms, is_sharing, updated_at
      `,
      [
        userId,
        slugPlatform,
        input.title,
        input.subtitle ?? null,
        input.moment_label ?? null,
        input.progress_ms,
        input.duration_ms,
        input.is_sharing ?? null,
        now,
      ]
    );

    return this.mapNowPlaying(rows[0]);
  }

  async clearNowPlaying(userId: string, platform: string): Promise<boolean> {
    const slugPlatform = assertPlatform(platform);
    await pool.query(
      `delete from public.now_playing_status where user_id = $1 and platform = $2`,
      [userId, slugPlatform]
    );
    return true;
  }

  async friendsActivity(userId: string, limit = 20): Promise<FriendStreamingActivity[]> {
    const { rows } = await pool.query<{
      user_id: string;
      display_name: string | null;
      username: string | null;
      avatar_url: string | null;
      platform: string;
      title: string;
      subtitle: string | null;
      progress_ms: number;
      is_sharing: boolean;
      updated_at: string;
      is_online: boolean | null;
      last_seen_at: string | null;
    }>(
      `
      select
        np.user_id,
        p.display_name,
        p.username,
        p.avatar_url,
        np.platform,
        np.title,
        np.subtitle,
        np.progress_ms,
        np.is_sharing,
        np.updated_at,
        up.is_online,
        up.last_seen_at
      from public.now_playing_status np
      join public.user_follows uf
        on uf.following_id = np.user_id
       and uf.follower_id = $1
      join public.profiles p
        on p.user_id = np.user_id
      left join public.user_presence up
        on up.user_id = np.user_id
      where np.is_sharing = true
        and np.updated_at > (now() - ($2 || ' seconds')::interval)
      order by np.updated_at desc
      limit $3
      `,
      [userId, NOW_PLAYING_TTL_SECONDS, limit]
    );

    return rows.map((row) => {
      const isOnline =
        row.is_online === true &&
        !!row.last_seen_at &&
        new Date(row.last_seen_at).getTime() >
          Date.now() - PRESENCE_TTL_SECONDS * 1000;

      return {
        user_id: row.user_id,
        display_name: row.display_name,
        username: row.username,
        avatar_url: row.avatar_url,
        platform: row.platform,
        title: row.title,
        detail: row.subtitle
          ? `${row.subtitle} · ${formatProgressLabel(row.progress_ms)}`
          : formatProgressLabel(row.progress_ms),
        is_live: isOnline,
      };
    });
  }

  async momentRooms(userId: string, limit = 12): Promise<MomentRoomItem[]> {
    const { rows } = await pool.query<{
      user_id: string;
      platform: string;
      title: string;
      subtitle: string | null;
      progress_ms: number;
    }>(
      `
      with visible as (
        select np.user_id, np.platform, np.title, np.subtitle, np.progress_ms
        from public.now_playing_status np
        where np.is_sharing = true
          and np.updated_at > (now() - ($2 || ' seconds')::interval)
          and (
            np.user_id = $1
            or exists (
              select 1
              from public.user_follows uf
              where uf.follower_id = $1
                and uf.following_id = np.user_id
            )
          )
      )
      select user_id, platform, title, subtitle, progress_ms
      from visible
      `,
      [userId, NOW_PLAYING_TTL_SECONDS]
    );

    type RoomAgg = {
      room_key: string;
      platform: string;
      show_title: string;
      episode_label: string;
      timestamp_label: string;
      active_friends: number;
    };

    const roomMap = new Map<string, RoomAgg>();

    for (const row of rows) {
      const { roomKey, timestampLabel } = buildRoomKey(
        row.platform,
        row.title,
        row.subtitle,
        row.progress_ms
      );

      const existing = roomMap.get(roomKey);
      if (existing) {
        existing.active_friends += 1;
      } else {
        roomMap.set(roomKey, {
          room_key: roomKey,
          platform: row.platform,
          show_title: row.title,
          episode_label: row.subtitle ?? 'Now playing',
          timestamp_label: timestampLabel,
          active_friends: 1,
        });
      }
    }

    const rooms = Array.from(roomMap.values())
      .sort((a, b) => b.active_friends - a.active_friends)
      .slice(0, limit);

    if (!rooms.length) return [];

    const roomKeys = rooms.map((room) => room.room_key);
    const commentRows = await this.commentsForRooms(roomKeys, 3, userId);

    const commentsByRoom = new Map<string, MomentRoomComment[]>();
    for (const comment of commentRows) {
      const key = comment.room_key;
      if (!commentsByRoom.has(key)) commentsByRoom.set(key, []);
      commentsByRoom.get(key)!.push(comment);
    }

    return rooms.map((room) => {
      const comments = commentsByRoom.get(room.room_key) ?? [];
      const heat = Math.min(1, room.active_friends / 15 + comments.length / 10);
      return {
        room_key: room.room_key,
        platform: room.platform,
        show_title: room.show_title,
        episode_label: room.episode_label,
        timestamp_label: room.timestamp_label,
        active_friends: room.active_friends,
        heat,
        preview_comments: comments,
      };
    });
  }

  private async commentsForRooms(
    roomKeys: string[],
    perRoom: number,
    viewerId: string
  ): Promise<Array<MomentRoomComment & { room_key: string }>> {
    const { rows } = await pool.query<{
      id: string;
      room_key: string;
      author_id: string;
      display_name: string | null;
      username: string | null;
      body: string;
      reactions: number;
      created_at: string;
    }>(
      `
      select
        c.id,
        c.room_key,
        c.author_id,
        p.display_name,
        p.username,
        c.body,
        c.reactions,
        c.created_at
      from public.moment_room_comments c
      join public.profiles p on p.user_id = c.author_id
      where c.room_key = any($1::text[])
      order by c.created_at desc
      `,
      [roomKeys]
    );

    const grouped = new Map<string, Array<MomentRoomComment & { room_key: string }>>();
    for (const row of rows) {
      if (!grouped.has(row.room_key)) grouped.set(row.room_key, []);
      const bucket = grouped.get(row.room_key)!;
      if (bucket.length >= perRoom) continue;
      bucket.push({
        room_key: row.room_key,
        id: row.id,
        author_id: row.author_id,
        author_name:
          row.author_id === viewerId
            ? 'You'
            : row.display_name ?? row.username ?? 'Friend',
        body: row.body,
        reactions: row.reactions,
        created_at: row.created_at,
      });
    }

    return roomKeys.flatMap((key) => grouped.get(key) ?? []);
  }

  async momentRoomComments(
    roomKey: string,
    viewerId: string,
    limit = 40
  ): Promise<MomentRoomComment[]> {
    const { rows } = await pool.query<{
      id: string;
      author_id: string;
      display_name: string | null;
      username: string | null;
      body: string;
      reactions: number;
      created_at: string;
    }>(
      `
      select
        c.id,
        c.author_id,
        p.display_name,
        p.username,
        c.body,
        c.reactions,
        c.created_at
      from public.moment_room_comments c
      join public.profiles p on p.user_id = c.author_id
      where c.room_key = $1
      order by c.created_at asc
      limit $2
      `,
      [roomKey, limit]
    );

    return rows.map((row) => ({
      id: row.id,
      author_id: row.author_id,
      author_name:
        row.author_id === viewerId
          ? 'You'
          : row.display_name ?? row.username ?? 'Friend',
      body: row.body,
      reactions: row.reactions,
      created_at: row.created_at,
    }));
  }

  async addMomentRoomComment(
    userId: string,
    roomKey: string,
    body: string
  ): Promise<MomentRoomComment> {
    const trimmed = String(body || '').trim();
    if (!trimmed) throw new Error('Comment body is required.');

    const { rows } = await pool.query<{
      id: string;
      author_id: string;
      display_name: string | null;
      username: string | null;
      body: string;
      reactions: number;
      created_at: string;
    }>(
      `
      insert into public.moment_room_comments (room_key, author_id, body)
      values ($1, $2, $3)
      returning id, author_id, body, reactions, created_at
      `,
      [roomKey, userId, trimmed]
    );

    const profile = await pool.query<{
      display_name: string | null;
      username: string | null;
    }>(
      `select display_name, username from public.profiles where user_id = $1 limit 1`,
      [userId]
    );

    const prof = profile.rows[0];

    return {
      id: rows[0].id,
      author_id: rows[0].author_id,
      author_name: prof?.display_name ?? prof?.username ?? 'You',
      body: rows[0].body,
      reactions: rows[0].reactions,
      created_at: rows[0].created_at,
    };
  }

  private mapNowPlaying(row: {
    id: string;
    platform: string;
    title: string;
    subtitle: string | null;
    moment_label: string | null;
    progress_ms: number;
    duration_ms: number;
    is_sharing: boolean;
    updated_at: string;
  }): NowPlayingItem {
    const duration = Math.max(row.duration_ms, 1);
    const progress = Math.min(1, Math.max(0, row.progress_ms / duration));
    return {
      id: row.id,
      platform: row.platform,
      title: row.title,
      subtitle: row.subtitle,
      moment_label: row.moment_label,
      progress_ms: row.progress_ms,
      duration_ms: row.duration_ms,
      progress,
      progress_label: formatProgressLabel(row.progress_ms),
      is_sharing: row.is_sharing,
      updated_at: row.updated_at,
    };
  }
}