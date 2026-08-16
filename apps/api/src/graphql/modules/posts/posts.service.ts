import { pool } from '../../../db.js';
import {
  emitContentPosted,
  emitServerEngagement,
} from '../../../engagement/engagement.service.js';
import { EngagementEventTypes } from '../../../kafka/types.js';
import {
  freshenOnePostMedia,
  freshenPostsMedia,
  resolvePlaybackForPostRow,
} from '../../../media/r2-playback.js';
import { NotificationsService } from '../notifications/notifications.service.js';

type PostAuthorRow = {
  user_id: string;
  display_name: string | null;
  username: string | null;
  avatar_url: string | null;
  country_name: string | null;
  country_code: string | null;
};

type SharedPostRow = {
  id: string;
  author_id: string;
  category_id: string;
  country_name: string;
  country_code: string | null;
  city_name: string | null;
  title: string | null;
  body: string;
  media_type: string;
  media_url: string | null;
  thumb_url: string | null;
  visibility: string;
  like_count: number;
  comment_count: number;
  liked_by_me: boolean;
  saved_by_me: boolean;
  created_at: string;
  updated_at: string;
  author: PostAuthorRow | null;
};

type PostRow = SharedPostRow & {
  shared_post_id: string | null;
  shared_post: SharedPostRow | null;
};

type PostCommentRow = {
  id: string;
  post_id: string;
  parent_id: string | null;
  author_id: string;
  body: string;
  like_count: number;
  liked_by_me: boolean;
  created_at: string;
  updated_at: string;
  author: PostAuthorRow | null;
};

type PostLikeRow = {
  user_id: string;
  created_at: string;
  user: PostAuthorRow | null;
};

type CreatePostInput = {
  title?: string | null;
  body: string;
  country_name: string;
  country_code: string;
  city_name?: string | null;
  visibility?: string | null;
  media_type?: string | null;
  media_url?: string | null;
  thumb_url?: string | null;
  shared_post_id?: string | null;
  /** Post as this channel (actor must be owner/admin). author_id becomes channel owner. */
  channel_id?: string | null;
};

function isMomentRow(row: { body?: string | null; media_type?: string | null } | null | undefined): boolean {
  if (!row) return false;
  const media = String(row.media_type ?? '').trim().toLowerCase();
  if (media === 'story' || media === 'moment') return true;
  const body = String(row.body ?? '');
  // Match __story__|expires=... and loose "story expires" markers clients may have written.
  if (/__story__/i.test(body)) return true;
  if (/\bstory\b/i.test(body) && /\bexpir/i.test(body)) return true;
  return false;
}

/** Never surface internal moment markers in feed/list APIs. */
function stripMomentMarkers(body: string | null | undefined): string {
  return String(body ?? '')
    .split('\n')
    .filter((line) => {
      const t = line.trim();
      if (!t) return true;
      if (/__story__/i.test(t)) return false;
      if (/\bstory\b/i.test(t) && /\bexpir/i.test(t)) return false;
      return true;
    })
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

/** Postgres `id uuid` — Archive/hub seed ids (`ia_*`, `hub_*`) must never hit `$1::uuid`. */
function isUuid(value: string | null | undefined): boolean {
  if (!value) return false;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
    String(value).trim()
  );
}

/**
 * Normalize recentPosts(before:) cursor.
 * Clients sometimes send epoch ms (`1786664811920`) instead of ISO timestamptz → PG error.
 */
function normalizeTimestamptzCursor(raw: string | null | undefined): string | null {
  if (raw == null) return null;
  const s = String(raw).trim();
  if (!s) return null;

  // Pure digits: epoch seconds or milliseconds
  if (/^\d{10,16}$/.test(s)) {
    const n = Number(s);
    if (!Number.isFinite(n) || n <= 0) return null;
    // 13+ digits → ms; 10–12 → seconds
    const ms = s.length >= 13 ? n : n * 1000;
    // Reject absurd ranges (before 2000 / after ~2100)
    if (ms < 946_684_800_000 || ms > 4_102_444_800_000) return null;
    return new Date(ms).toISOString();
  }

  // Already ISO / PG-friendly
  const d = new Date(s);
  if (!Number.isNaN(d.getTime())) {
    return d.toISOString();
  }
  return null;
}

function presentPostRow<T extends Record<string, any>>(row: T): T {
  if (!row) return row;
  const next: any = { ...row, body: stripMomentMarkers(row.body) };
  let ownComments = Number(row.comment_count) || 0;
  if (row.shared_post && typeof row.shared_post === 'object') {
    const sp: any = {
      ...row.shared_post,
      body: stripMomentMarkers((row.shared_post as any).body),
    };
    const originComments = Number(sp.comment_count) || 0;
    // Spark/hub *shares* often have empty local threads while the origin holds R2 comments.
    // Surface the fuller count so feed cards keep “View N comments”.
    if (originComments > ownComments) {
      ownComments = originComments;
    }
    next.shared_post = sp;
  }
  next.comment_count = ownComments;
  return next as T;
}

/** Present + re-sign R2 media_url so clients never receive expired X-Amz links. */
async function presentPostRows<T extends Record<string, any>>(rows: T[]): Promise<T[]> {
  const base = (rows ?? []).map((r) => presentPostRow(r));
  return freshenPostsMedia(base);
}

async function presentPostRowAsync<T extends Record<string, any>>(row: T): Promise<T> {
  return freshenOnePostMedia(presentPostRow(row));
}

async function withoutMoments<T extends { body?: string | null; media_type?: string | null }>(
  rows: T[]
): Promise<T[]> {
  return await presentPostRows((rows ?? []).filter((r) => !isMomentRow(r)));
}

// Exclude moments from country/recent/search feeds (moments live on author feeds only).
const EXCLUDE_MOMENTS_SQL = `
  and lower(coalesce(p.media_type, '')) not in ('story', 'moment')
  and position('__story__' in lower(coalesce(p.body, ''))) = 0
`;

/** Non-owners never see posts from private profiles (requires profiles.is_private). */
function privateAuthorVisible(viewerParam: string): string {
  return `and (
    coalesce(pr.is_private, false) = false
    or (${viewerParam} is not null and p.author_id = ${viewerParam})
  )`;
}

/** Redact avatar when the profile is private and the viewer is not the owner. */
function avatarSql(viewerParam: string, alias: string): string {
  return `case
    when coalesce(${alias}.is_private, false)
      and (${viewerParam} is null or ${alias}.user_id is distinct from ${viewerParam})
    then null
    else ${alias}.avatar_url
  end`;
}

export class PostsService {
  private notifications = new NotificationsService();
  private bookmarksTableExists: boolean | null = null;
  /** profiles.is_private — shipped in code before migration landed; detect at runtime. */
  private privacyColumnExists: boolean | null = null;
  /** public.post_comment_likes — comment likes migration may lag behind deploy. */
  private commentLikesTableExists: boolean | null = null;

  private async bookmarksEnabled(): Promise<boolean> {
    if (this.bookmarksTableExists !== null) return this.bookmarksTableExists;
    try {
      const { rows } = await pool.query<{ exists: boolean }>(
        `select to_regclass('public.post_bookmarks') is not null as exists`
      );
      this.bookmarksTableExists = !!rows?.[0]?.exists;
    } catch {
      this.bookmarksTableExists = false;
    }
    return this.bookmarksTableExists;
  }

  private async privacyEnabled(): Promise<boolean> {
    if (this.privacyColumnExists !== null) return this.privacyColumnExists;
    try {
      const { rows } = await pool.query<{ exists: boolean }>(
        `
        select exists (
          select 1
          from information_schema.columns
          where table_schema = 'public'
            and table_name = 'profiles'
            and column_name = 'is_private'
        ) as exists
        `
      );
      this.privacyColumnExists = !!rows?.[0]?.exists;
    } catch {
      this.privacyColumnExists = false;
    }
    if (!this.privacyColumnExists) {
      console.warn(
        '[PostsService] profiles.is_private missing — privacy filters disabled until migration runs'
      );
    }
    return this.privacyColumnExists;
  }

  private async commentLikesEnabled(): Promise<boolean> {
    if (this.commentLikesTableExists !== null) return this.commentLikesTableExists;
    try {
      const { rows } = await pool.query<{ exists: boolean }>(
        `select to_regclass('public.post_comment_likes') is not null as exists`
      );
      this.commentLikesTableExists = !!rows?.[0]?.exists;
    } catch {
      this.commentLikesTableExists = false;
    }
    if (!this.commentLikesTableExists) {
      console.warn(
        '[PostsService] post_comment_likes missing — comment like counts disabled until migration runs'
      );
    }
    return this.commentLikesTableExists;
  }

  private async privateAuthorVisibleSql(viewerParam: string): Promise<string> {
    if (!(await this.privacyEnabled())) return '';
    return privateAuthorVisible(viewerParam);
  }

  private async avatarSqlExpr(viewerParam: string, alias: string): Promise<string> {
    if (!(await this.privacyEnabled())) return `${alias}.avatar_url`;
    return avatarSql(viewerParam, alias);
  }

  private async commentLikeSelectSql(viewerParam: string): Promise<string> {
    if (!(await this.commentLikesEnabled())) {
      return `0 as like_count, false as liked_by_me`;
    }
    return `
        (select count(*)::int from public.post_comment_likes pcl where pcl.comment_id = c.id) as like_count,
        case
          when ${viewerParam} is not null
            and exists (
              select 1
              from public.post_comment_likes pcl
              where pcl.comment_id = c.id and pcl.user_id = ${viewerParam}
            )
          then true
          else false
        end as liked_by_me`;
  }

  private async savedByMeExpr(viewerParam: string): Promise<string> {
    if (!(await this.bookmarksEnabled())) {
      return `false as saved_by_me`;
    }
    return `
        case
          when ${viewerParam} is not null
            and exists (
              select 1
              from public.post_bookmarks pb
              where pb.post_id = p.id and pb.user_id = ${viewerParam}
            )
          then true
          else false
        end as saved_by_me`;
  }

  private async savedByMeSharedExpr(viewerParam: string): Promise<string> {
    if (!(await this.bookmarksEnabled())) {
      return `'saved_by_me', false,`;
    }
    return `
            'saved_by_me', case
              when ${viewerParam} is not null
                and exists (
                  select 1
                  from public.post_bookmarks spb
                  where spb.post_id = sp.id and spb.user_id = ${viewerParam}
                )
              then true
              else false
            end,`;
  }

  async postsByCountry(code: string, limit: number, viewerId: string | null): Promise<PostRow[]> {
    const iso = (code || '').toUpperCase();
    // Deep enough for full R2 focus-country catalogs (per-country hundreds of Sparks).
    const safeLimit = Math.max(1, Math.min(500, limit || 25));
    const savedByMe = await this.savedByMeExpr('$3::uuid');
    const savedByMeShared = await this.savedByMeSharedExpr('$3::uuid');
    const { rows } = await pool.query(
      `
      select
        p.*,
        greatest(
          coalesce(p.like_count, 0),
          (select count(*)::int from public.post_likes pl where pl.post_id = p.id)
        ) as like_count,
        (select count(*)::int from public.post_comments pc where pc.post_id = p.id) as comment_count,
        case
          when $3::uuid is not null
            and exists (
              select 1
              from public.post_likes pl
              where pl.post_id = p.id and pl.user_id = $3::uuid
            )
          then true
          else false
        end as liked_by_me,${savedByMe},
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as author,
        case
          when sp.id is null then null
          else jsonb_build_object(
            'id', sp.id,
            'author_id', sp.author_id,
            'category_id', sp.category_id,
            'country_name', sp.country_name,
            'country_code', sp.country_code,
            'city_name', sp.city_name,
            'title', sp.title,
            'body', sp.body,
            'media_type', sp.media_type,
            'media_url', sp.media_url,
            'thumb_url', sp.thumb_url,
            'visibility', sp.visibility,
            'like_count', greatest(
              coalesce(sp.like_count, 0),
              (select count(*)::int from public.post_likes spl where spl.post_id = sp.id)
            ),
            'comment_count', (select count(*)::int from public.post_comments spc where spc.post_id = sp.id),
            'liked_by_me', case
              when $3::uuid is not null
                and exists (
                  select 1
                  from public.post_likes spl
                  where spl.post_id = sp.id and spl.user_id = $3::uuid
                )
              then true
              else false
            end,${savedByMeShared}
            'created_at', sp.created_at,
            'updated_at', sp.updated_at,
            'author', jsonb_build_object(
              'user_id', spr.user_id,
              'display_name', spr.display_name,
              'username', spr.username,
              'avatar_url', spr.avatar_url,
              'country_name', spr.country_name,
              'country_code', spr.country_code
            )
          )
        end as shared_post
      from public.posts p
      left join public.profiles pr on pr.user_id = p.author_id
      left join public.posts sp on sp.id = p.shared_post_id
        and coalesce(sp.moderation_status, 'active') not in ('hidden', 'deleted')
      left join public.profiles spr on spr.user_id = sp.author_id
      where upper(coalesce(p.country_code, '')) = $1
        and coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted')
        ${EXCLUDE_MOMENTS_SQL}
        and (
          p.visibility in ('public', 'country')
          or ($3::uuid is not null and p.author_id = $3::uuid)
          or (
            p.visibility = 'followers'
            and $3::uuid is not null
            and exists (
              select 1
              from public.user_follows f
              where f.follower_id = $3::uuid and f.following_id = p.author_id
            )
          )
        )
        ${await this.privateAuthorVisibleSql('$3::uuid')}
      order by p.created_at desc, p.id desc
      limit $2
      `,
      [iso, safeLimit, viewerId]
    );

    return await withoutMoments(rows as PostRow[]);
  }

  async postsByAuthor(authorId: string, limit: number, viewerId: string | null): Promise<PostRow[]> {
    const savedByMe = await this.savedByMeExpr('$2::uuid');
    const savedByMeShared = await this.savedByMeSharedExpr('$2::uuid');
    const isOwner = !!viewerId && viewerId === authorId;
    if (!isOwner && (await this.privacyEnabled())) {
      try {
        const { rows: privacyRows } = await pool.query(
          `select coalesce(is_private, false) as is_private from public.profiles where user_id = $1 limit 1`,
          [authorId]
        );
        if (privacyRows[0]?.is_private) {
          return [];
        }
      } catch (err) {
        // Column missing / transient — do not blank the whole author feed.
        console.warn('[PostsService] postsByAuthor privacy check failed:', (err as Error)?.message ?? err);
      }
    }
    if (isOwner) {
      const { rows } = await pool.query(
        `
        select
          p.*,
          greatest(
          coalesce(p.like_count, 0),
          (select count(*)::int from public.post_likes pl where pl.post_id = p.id)
        ) as like_count,
          (select count(*)::int from public.post_comments pc where pc.post_id = p.id) as comment_count,
          case
            when $2::uuid is not null
              and exists (
                select 1
                from public.post_likes pl
                where pl.post_id = p.id and pl.user_id = $2::uuid
              )
            then true
            else false
          end as liked_by_me,${savedByMe},
          jsonb_build_object(
            'user_id', pr.user_id,
            'display_name', pr.display_name,
            'username', pr.username,
            'avatar_url', pr.avatar_url,
            'country_name', pr.country_name,
            'country_code', pr.country_code
          ) as author,
          case
            when sp.id is null then null
            else jsonb_build_object(
              'id', sp.id,
              'author_id', sp.author_id,
              'category_id', sp.category_id,
              'country_name', sp.country_name,
              'country_code', sp.country_code,
              'city_name', sp.city_name,
              'title', sp.title,
              'body', sp.body,
              'media_type', sp.media_type,
              'media_url', sp.media_url,
              'thumb_url', sp.thumb_url,
              'visibility', sp.visibility,
              'like_count', greatest(
              coalesce(sp.like_count, 0),
              (select count(*)::int from public.post_likes spl where spl.post_id = sp.id)
            ),
              'comment_count', (select count(*)::int from public.post_comments spc where spc.post_id = sp.id),
              'liked_by_me', case
                when $2::uuid is not null
                  and exists (
                    select 1
                    from public.post_likes spl
                    where spl.post_id = sp.id and spl.user_id = $2::uuid
                  )
                then true
                else false
              end,${savedByMeShared}
              'created_at', sp.created_at,
              'updated_at', sp.updated_at,
              'author', jsonb_build_object(
                'user_id', spr.user_id,
                'display_name', spr.display_name,
                'username', spr.username,
                'avatar_url', spr.avatar_url,
                'country_name', spr.country_name,
                'country_code', spr.country_code
              )
            )
          end as shared_post
        from public.posts p
        left join public.profiles pr on pr.user_id = p.author_id
        left join public.posts sp on sp.id = p.shared_post_id
          and coalesce(sp.moderation_status, 'active') not in ('hidden', 'deleted')
        left join public.profiles spr on spr.user_id = sp.author_id
        where p.author_id = $1
          and coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted')
        order by p.created_at desc
        limit $3
        `,
        [authorId, viewerId, Math.max(1, limit)]
      );

      // Author feed keeps moments (for the strip) but never leaks raw markers.
      return await presentPostRows(rows as PostRow[]);
    }

    const { rows } = await pool.query(
      `
      select
        p.*,
        greatest(
          coalesce(p.like_count, 0),
          (select count(*)::int from public.post_likes pl where pl.post_id = p.id)
        ) as like_count,
        (select count(*)::int from public.post_comments pc where pc.post_id = p.id) as comment_count,
        case
          when $2::uuid is not null
            and exists (
              select 1
              from public.post_likes pl
              where pl.post_id = p.id and pl.user_id = $2::uuid
            )
          then true
          else false
        end as liked_by_me,${savedByMe},
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as author,
        case
          when sp.id is null then null
          else jsonb_build_object(
            'id', sp.id,
            'author_id', sp.author_id,
            'category_id', sp.category_id,
            'country_name', sp.country_name,
            'country_code', sp.country_code,
            'city_name', sp.city_name,
            'title', sp.title,
            'body', sp.body,
            'media_type', sp.media_type,
            'media_url', sp.media_url,
            'thumb_url', sp.thumb_url,
            'visibility', sp.visibility,
            'like_count', greatest(
              coalesce(sp.like_count, 0),
              (select count(*)::int from public.post_likes spl where spl.post_id = sp.id)
            ),
            'comment_count', (select count(*)::int from public.post_comments spc where spc.post_id = sp.id),
            'liked_by_me', case
              when $2::uuid is not null
                and exists (
                  select 1
                  from public.post_likes spl
                  where spl.post_id = sp.id and spl.user_id = $2::uuid
                )
              then true
              else false
            end,${savedByMeShared}
            'created_at', sp.created_at,
            'updated_at', sp.updated_at,
            'author', jsonb_build_object(
              'user_id', spr.user_id,
              'display_name', spr.display_name,
              'username', spr.username,
              'avatar_url', spr.avatar_url,
              'country_name', spr.country_name,
              'country_code', spr.country_code
            )
          )
        end as shared_post
      from public.posts p
      left join public.profiles pr on pr.user_id = p.author_id
      left join public.posts sp on sp.id = p.shared_post_id
        and coalesce(sp.moderation_status, 'active') not in ('hidden', 'deleted')
      left join public.profiles spr on spr.user_id = sp.author_id
      where p.author_id = $1
        and coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted')
        and (
          p.visibility in ('public', 'country')
          or (
            p.visibility = 'followers'
            and $2::uuid is not null
            and exists (
              select 1
              from public.user_follows f
              where f.follower_id = $2::uuid and f.following_id = $1
            )
          )
        )
      order by p.created_at desc
      limit $3
      `,
      [authorId, viewerId, Math.max(1, limit)]
    );

    return await presentPostRows(rows as PostRow[]);
  }

  async recentPosts(
    limit: number,
    viewerId: string | null,
    before?: string | null
  ): Promise<PostRow[]> {
    // Allow deep pages so full R2 focus catalogs (thousands of rows) are reachable via cursor.
    const safeLimit = Math.max(1, Math.min(500, limit || 25));
    const savedByMe = await this.savedByMeExpr('$2::uuid');
    const savedByMeShared = await this.savedByMeSharedExpr('$2::uuid');
    const params: Array<string | number | null> = [safeLimit, viewerId];
    // Never pass raw epoch-ms / garbage into ::timestamptz (Render ERR spam + pool stress).
    const beforeTs = normalizeTimestamptzCursor(before);
    const beforeClause = beforeTs ? `and p.created_at < $3::timestamptz` : '';
    if (beforeTs) params.push(beforeTs);
    const { rows } = await pool.query(
      `
      select
        p.*,
        greatest(
          coalesce(p.like_count, 0),
          (select count(*)::int from public.post_likes pl where pl.post_id = p.id)
        ) as like_count,
        (select count(*)::int from public.post_comments pc where pc.post_id = p.id) as comment_count,
        case
          when $2::uuid is not null
            and exists (
              select 1
              from public.post_likes pl
              where pl.post_id = p.id and pl.user_id = $2::uuid
            )
          then true
          else false
        end as liked_by_me,${savedByMe},
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as author,
        case
          when sp.id is null then null
          else jsonb_build_object(
            'id', sp.id,
            'author_id', sp.author_id,
            'category_id', sp.category_id,
            'country_name', sp.country_name,
            'country_code', sp.country_code,
            'city_name', sp.city_name,
            'title', sp.title,
            'body', sp.body,
            'media_type', sp.media_type,
            'media_url', sp.media_url,
            'thumb_url', sp.thumb_url,
            'visibility', sp.visibility,
            'like_count', greatest(
              coalesce(sp.like_count, 0),
              (select count(*)::int from public.post_likes spl where spl.post_id = sp.id)
            ),
            'comment_count', (select count(*)::int from public.post_comments spc where spc.post_id = sp.id),
            'liked_by_me', case
              when $2::uuid is not null
                and exists (
                  select 1
                  from public.post_likes spl
                  where spl.post_id = sp.id and spl.user_id = $2::uuid
                )
              then true
              else false
            end,${savedByMeShared}
            'created_at', sp.created_at,
            'updated_at', sp.updated_at,
            'author', jsonb_build_object(
              'user_id', spr.user_id,
              'display_name', spr.display_name,
              'username', spr.username,
              'avatar_url', spr.avatar_url,
              'country_name', spr.country_name,
              'country_code', spr.country_code
            )
          )
        end as shared_post
      from public.posts p
      left join public.profiles pr on pr.user_id = p.author_id
      left join public.posts sp on sp.id = p.shared_post_id
        and coalesce(sp.moderation_status, 'active') not in ('hidden', 'deleted')
      left join public.profiles spr on spr.user_id = sp.author_id
      where coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted')
        ${EXCLUDE_MOMENTS_SQL}
        and (
          p.visibility in ('public', 'country')
          or ($2::uuid is not null and p.author_id = $2::uuid)
          or (
            p.visibility = 'followers'
            and $2::uuid is not null
            and exists (
              select 1
              from public.user_follows f
              where f.follower_id = $2::uuid and f.following_id = p.author_id
            )
          )
        )
        ${await this.privateAuthorVisibleSql('$2::uuid')}
        ${beforeClause}
      order by p.created_at desc, p.id desc
      limit $1
      `,
      params
    );

    return await withoutMoments(rows as PostRow[]);
  }

  async searchPosts(query: string, limit: number, viewerId: string | null): Promise<PostRow[]> {
    const savedByMe = await this.savedByMeExpr('$4::uuid');
    const savedByMeShared = await this.savedByMeSharedExpr('$4::uuid');
    const term = String(query ?? '').trim();
    if (!term) return [];
    const max = Math.max(1, Math.min(100, limit || 25));
    const like = `%${term.toLowerCase()}%`;

    const { rows } = await pool.query(
      `
      with q as (
        select websearch_to_tsquery('simple', $1) as tsq
      )
      select
        p.*,
        greatest(
          coalesce(p.like_count, 0),
          (select count(*)::int from public.post_likes pl where pl.post_id = p.id)
        ) as like_count,
        (select count(*)::int from public.post_comments pc where pc.post_id = p.id) as comment_count,
        case
          when $4::uuid is not null
            and exists (
              select 1
              from public.post_likes pl
              where pl.post_id = p.id and pl.user_id = $4::uuid
            )
          then true
          else false
        end as liked_by_me,${savedByMe},
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as author,
        case
          when sp.id is null then null
          else jsonb_build_object(
            'id', sp.id,
            'author_id', sp.author_id,
            'category_id', sp.category_id,
            'country_name', sp.country_name,
            'country_code', sp.country_code,
            'city_name', sp.city_name,
            'title', sp.title,
            'body', sp.body,
            'media_type', sp.media_type,
            'media_url', sp.media_url,
            'thumb_url', sp.thumb_url,
            'visibility', sp.visibility,
            'like_count', greatest(
              coalesce(sp.like_count, 0),
              (select count(*)::int from public.post_likes spl where spl.post_id = sp.id)
            ),
            'comment_count', (select count(*)::int from public.post_comments spc where spc.post_id = sp.id),
            'liked_by_me', case
              when $4::uuid is not null
                and exists (
                  select 1
                  from public.post_likes spl
                  where spl.post_id = sp.id and spl.user_id = $4::uuid
                )
              then true
              else false
            end,${savedByMeShared}
            'created_at', sp.created_at,
            'updated_at', sp.updated_at,
            'author', jsonb_build_object(
              'user_id', spr.user_id,
              'display_name', spr.display_name,
              'username', spr.username,
              'avatar_url', spr.avatar_url,
              'country_name', spr.country_name,
              'country_code', spr.country_code
            )
          )
        end as shared_post,
        ts_rank_cd(
          to_tsvector('simple', coalesce(p.title, '') || ' ' || coalesce(p.body, '')),
          q.tsq
        ) as rank
      from public.posts p
      cross join q
      left join public.profiles pr on pr.user_id = p.author_id
      left join public.posts sp on sp.id = p.shared_post_id
        and coalesce(sp.moderation_status, 'active') not in ('hidden', 'deleted')
      left join public.profiles spr on spr.user_id = sp.author_id
      where (
          to_tsvector('simple', coalesce(p.title, '') || ' ' || coalesce(p.body, '')) @@ q.tsq
          or lower(coalesce(p.title, '')) like $2
          or lower(coalesce(p.body, '')) like $2
        )
        and coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted')
        ${EXCLUDE_MOMENTS_SQL}
        and (
          p.visibility = 'public'
          or ($4::uuid is not null and p.author_id = $4::uuid)
          or (
            p.visibility = 'followers'
            and $4::uuid is not null
            and exists (
              select 1
              from public.user_follows f
              where f.follower_id = $4::uuid and f.following_id = p.author_id
            )
          )
        )
        ${await this.privateAuthorVisibleSql('$4::uuid')}
      order by rank desc nulls last, p.created_at desc, p.id desc
      limit $3
      `,
      [term, like, max, viewerId]
    );

    return await withoutMoments(rows as PostRow[]);
  }

  /**
   * Random Sparks from the **full** library (not only recentPosts head).
   * Powers endless player/feed variety across 10k–28k+ R2-seeded rows.
   */
  async discoverSparks(
    limit: number,
    excludeIds: string[],
    viewerId: string | null
  ): Promise<PostRow[]> {
    const safeLimit = Math.max(1, Math.min(120, limit || 48));
    const viewer = viewerId && isUuid(viewerId) ? viewerId : null;
    const exclude = (excludeIds || []).filter((id) => isUuid(id)).slice(0, 400);
    const savedByMe = await this.savedByMeExpr('$2::uuid');
    const savedByMeShared = await this.savedByMeSharedExpr('$2::uuid');

    // Two-step sample: random offset into spark-like set, then small window.
    // Cheaper than ORDER BY random() on the full posts table every call.
    const countParams: any[] = [];
    let excludeSql = '';
    if (exclude.length) {
      countParams.push(exclude);
      excludeSql = `and p.id <> all($1::uuid[])`;
    }
    const { rows: countRows } = await pool.query<{ n: string }>(
      `
      select count(*)::text as n
      from public.posts p
      where coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted')
        and p.visibility in ('public', 'country')
        ${EXCLUDE_MOMENTS_SQL}
        and (
          lower(coalesce(p.media_type, '')) in ('reel', 'spark')
          or position('__spark__|' in coalesce(p.body, '')) > 0
          or position('"reel":true' in lower(coalesce(p.media_url, ''))) > 0
          or (
            coalesce(p.media_path, '') like 'r2:%'
            and position('longform' in lower(coalesce(p.media_path, ''))) = 0
            and position('LongForm' in coalesce(p.media_path, '')) = 0
          )
        )
        ${excludeSql}
      `,
      countParams
    );
    const total = Math.max(0, parseInt(countRows[0]?.n || '0', 10) || 0);
    if (total === 0) return [];

    const maxOffset = Math.max(0, total - safeLimit);
    const offset = maxOffset > 0 ? Math.floor(Math.random() * (maxOffset + 1)) : 0;

    const params: any[] = [safeLimit, viewer, offset];
    let excludeClause = '';
    if (exclude.length) {
      params.push(exclude);
      excludeClause = `and p.id <> all($4::uuid[])`;
    }

    const { rows } = await pool.query(
      `
      select
        p.*,
        greatest(
          coalesce(p.like_count, 0),
          (select count(*)::int from public.post_likes pl where pl.post_id = p.id)
        ) as like_count,
        (select count(*)::int from public.post_comments pc where pc.post_id = p.id) as comment_count,
        case
          when $2::uuid is not null
            and exists (
              select 1 from public.post_likes pl
              where pl.post_id = p.id and pl.user_id = $2::uuid
            )
          then true else false
        end as liked_by_me,${savedByMe},
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as author,
        case
          when sp.id is null then null
          else jsonb_build_object(
            'id', sp.id,
            'author_id', sp.author_id,
            'category_id', sp.category_id,
            'country_name', sp.country_name,
            'country_code', sp.country_code,
            'city_name', sp.city_name,
            'title', sp.title,
            'body', sp.body,
            'media_type', sp.media_type,
            'media_url', sp.media_url,
            'thumb_url', sp.thumb_url,
            'visibility', sp.visibility,
            'like_count', greatest(
              coalesce(sp.like_count, 0),
              (select count(*)::int from public.post_likes spl where spl.post_id = sp.id)
            ),
            'comment_count', (select count(*)::int from public.post_comments spc where spc.post_id = sp.id),
            'liked_by_me', false,${savedByMeShared}
            'created_at', sp.created_at,
            'updated_at', sp.updated_at,
            'author', jsonb_build_object(
              'user_id', spr.user_id,
              'display_name', spr.display_name,
              'username', spr.username,
              'avatar_url', spr.avatar_url,
              'country_name', spr.country_name,
              'country_code', spr.country_code
            )
          )
        end as shared_post
      from public.posts p
      left join public.profiles pr on pr.user_id = p.author_id
      left join public.posts sp on sp.id = p.shared_post_id
        and coalesce(sp.moderation_status, 'active') not in ('hidden', 'deleted')
      left join public.profiles spr on spr.user_id = sp.author_id
      where coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted')
        and p.visibility in ('public', 'country')
        ${EXCLUDE_MOMENTS_SQL}
        and (
          lower(coalesce(p.media_type, '')) in ('reel', 'spark')
          or position('__spark__|' in coalesce(p.body, '')) > 0
          or position('"reel":true' in lower(coalesce(p.media_url, ''))) > 0
          or (
            coalesce(p.media_path, '') like 'r2:%'
            and position('longform' in lower(coalesce(p.media_path, ''))) = 0
            and position('LongForm' in coalesce(p.media_path, '')) = 0
          )
        )
        ${excludeClause}
      order by p.created_at desc, p.id desc
      offset $3
      limit $1
      `,
      params
    );

    // Shuffle the page so offset windows don't feel chronological.
    const presented = await presentPostRows(rows as PostRow[]);
    for (let i = presented.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [presented[i], presented[j]] = [presented[j], presented[i]];
    }
    return presented;
  }

  async postById(postId: string, viewerId: string | null): Promise<PostRow | null> {
    if (!postId) return null;
    // Seed / offline ids (ia_*, hub_*, demo_*) are not UUIDs — do not query Postgres.
    if (!isUuid(postId)) return null;
    const post = await this.postByIdForViewer(postId, viewerId);
    return post ? await presentPostRowAsync(post) : null;
  }

  /**
   * On-demand playback resolution — always a *live* URL for R2 objects.
   * Clients should call this before play when they only have a cached post.
   */
  async playbackMedia(
    postId: string,
    viewerId: string | null
  ): Promise<{ post_id: string; url: string; media_url: string; r2_key: string | null } | null> {
    if (!postId) return null;
    if (!isUuid(postId)) return null;
    const post = await this.postByIdForViewer(postId, viewerId);
    if (!post) return null;
    const resolved = await resolvePlaybackForPostRow(post as any);
    if (!resolved) return null;
    return {
      post_id: postId,
      url: resolved.url,
      media_url: resolved.media_url,
      r2_key: resolved.key || null,
    };
  }

  async createPost(actorId: string, input: CreatePostInput): Promise<PostRow> {
    const sharedPostId = input.shared_post_id ? String(input.shared_post_id) : null;
    if (sharedPostId) {
      await this.ensurePostAccess(sharedPostId, actorId);
      const { rows: sharedRows } = await pool.query<{ body: string; media_type: string | null }>(
        `select body, media_type from public.posts where id = $1 limit 1`,
        [sharedPostId]
      );
      if (isMomentRow(sharedRows[0])) {
        throw new Error('Moments cannot be shared as feed posts.');
      }
    }

    // Optional post-as-channel: author becomes channel owner; actor is posted_by.
    let authorId = actorId;
    let channelId: string | null = null;
    let postedByUserId: string | null = actorId;
    const rawChannelId = input.channel_id ? String(input.channel_id).trim() : '';
    if (rawChannelId) {
      const { rows: staffRows } = await pool.query<{ ok: boolean; owner_user_id: string | null }>(
        `
        select
          public.is_channel_admin_or_owner($1::uuid, $2::uuid) as ok,
          c.owner_user_id
        from public.channels c
        where c.id = $1::uuid
        limit 1
        `,
        [rawChannelId, actorId]
      );
      if (!staffRows[0]?.ok || !staffRows[0].owner_user_id) {
        throw new Error('CHANNEL_FORBIDDEN');
      }
      channelId = rawChannelId;
      authorId = staffRows[0].owner_user_id;
      postedByUserId = actorId;
    }

    const categoryId = await this.resolveCategoryId(input.country_code);
    const iso = (input.country_code || '').toUpperCase();
    let body = (input.body ?? '').trim();
    const isMomentBody = body.includes('__story__|');
    const normalizedInputType = String(input.media_type ?? '').trim().toLowerCase();
    const isMoment = isMomentBody || normalizedInputType === 'story' || normalizedInputType === 'moment';
    const visibility = isMoment
      ? 'country'
      : this.normalizeVisibility(input.visibility) ?? 'public';
    // Moments always store media_type=story so feed SQL can exclude them reliably.
    const mediaType = isMoment
      ? 'story'
      : this.normalizeMediaType(input.media_type, input.media_url);
    const mediaUrl = mediaType === 'none' ? null : (input.media_url ?? null);
    const thumbUrl = mediaType === 'none' ? null : (input.thumb_url ?? null);

    // Channel publishes: stamp hub channel marker so older clients still catalog as Hubs.
    // Never stamp channel marker on feed shares (origin / shared_post / Archive re-hosts).
    const mediaUrlLower = String(mediaUrl ?? '').toLowerCase();
    const isArchiveMedia =
      mediaUrlLower.includes('archive.org') ||
      mediaUrlLower.includes('ia800') ||
      mediaUrlLower.includes('ia600');
    const isFeedShare =
      !!sharedPostId ||
      body.includes('__hub_origin__|') ||
      body.includes('__spark_share__|') ||
      // Self-contained re-share of Internet Archive catalog media (no shared_post_id).
      (isArchiveMedia && (mediaType === 'video' || mediaType === 'reel'));
    if (
      channelId &&
      !isMoment &&
      !isFeedShare &&
      (mediaType === 'video' || mediaType === 'reel') &&
      !body.includes('__hub_channel__|')
    ) {
      body = body.length ? `__hub_channel__|\n${body}` : '__hub_channel__|';
    }

    // GraphQL Post.body is non-null, so never return null here.
    let bodyValue = body.length ? body : '';

    // Bind channel_id only for intentional hub-channel publishes — never for feed shares.
    if (!channelId && bodyValue.includes('__hub_channel__|') && !isFeedShare) {
      const { rows: ownCh } = await pool.query<{ id: string }>(
        `select id from public.channels where owner_user_id = $1::uuid limit 1`,
        [actorId]
      );
      if (ownCh[0]?.id) {
        channelId = ownCh[0].id;
        postedByUserId = actorId;
      }
    }
    // Feed shares must not attach to the sharer's channel row.
    // Also strip a mistaken hub_channel stamp on Archive re-shares so they never
    // appear as the sharer's own channel uploads.
    if (isFeedShare) {
      channelId = null;
      if (bodyValue.includes('__hub_channel__|')) {
        bodyValue = bodyValue
          .split('\n')
          .map((l) => l.trim())
          .filter((l) => l && !l.startsWith('__hub_channel__|') && l !== '__hub_channel__|')
          .join('\n');
      }
    }

    const { rows } = await pool.query(
      `
      insert into public.posts
        (author_id, category_id, country_name, country_code, city_name, title, body, visibility,
         media_type, media_url, thumb_url, shared_post_id, channel_id, posted_by_user_id)
      values
        ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
      returning id
      `,
      [
        authorId,
        categoryId,
        input.country_name,
        iso,
        input.city_name ?? null,
        input.title?.trim() || null,
        bodyValue,
        visibility,
        mediaType,
        mediaUrl,
        thumbUrl,
        sharedPostId,
        channelId,
        postedByUserId,
      ]
    );

    const createdId = rows[0]?.id;
    if (!createdId) throw new Error('Failed to create post.');

    const post = await this.postByIdForViewer(createdId, actorId);
    if (!post) throw new Error('Newly created post not found.');

    // Immediate platform sync → Kafka + Uploads report (feed / Spark / Hubs / share).
    void this.emitUploadEvent({
      actorId,
      authorId,
      postId: createdId,
      title: input.title?.trim() || null,
      body: bodyValue,
      mediaType,
      mediaUrl,
      countryCode: iso || null,
      countryName: input.country_name ?? null,
      cityName: input.city_name ?? null,
      channelId,
      postedByUserId,
      sharedPostId,
      isMoment,
    });

    return await presentPostRowAsync(post);
  }

  /** Plain-language upload line + Kafka ContentPosted (stats / report tab). */
  private async emitUploadEvent(opts: {
    actorId: string;
    authorId: string;
    postId: string;
    title: string | null;
    body: string;
    mediaType: string | null;
    mediaUrl: string | null;
    countryCode: string | null;
    countryName: string | null;
    cityName: string | null;
    channelId: string | null;
    postedByUserId: string | null;
    sharedPostId: string | null;
    isMoment: boolean;
  }): Promise<void> {
    try {
      const { rows: actorRows } = await pool.query<{
        display_name: string | null;
        username: string | null;
      }>(
        `select display_name, username from public.profiles where user_id = $1::uuid limit 1`,
        [opts.actorId]
      );
      const actorName =
        actorRows[0]?.display_name?.trim() ||
        (actorRows[0]?.username ? `@${actorRows[0].username}` : null) ||
        'Someone';

      let channelName: string | null = null;
      let channelRole: string | null = null;
      if (opts.channelId) {
        const { rows: ch } = await pool.query<{ name: string; owner_user_id: string }>(
          `select name, owner_user_id from public.channels where id = $1::uuid limit 1`,
          [opts.channelId]
        );
        channelName = ch[0]?.name?.trim() || null;
        if (ch[0]?.owner_user_id) {
          channelRole = ch[0].owner_user_id === opts.actorId ? 'owner' : 'admin';
        }
      }

      const isSpark =
        opts.mediaType === 'reel' ||
        opts.body.includes('__spark__|') ||
        opts.body.includes('__spark_share__|');
      const isShare = !!opts.sharedPostId || opts.body.includes('__hub_origin__|');
      const isHubLongForm =
        !!opts.channelId ||
        opts.body.includes('__hub_channel__|') ||
        (!!opts.mediaUrl &&
          (opts.mediaUrl.toLowerCase().includes('longform/') ||
            opts.mediaUrl.toLowerCase().includes('matterya-sparks')));
      const place =
        opts.cityName?.trim() ||
        opts.countryName?.trim() ||
        (opts.countryCode ? opts.countryCode.toUpperCase() : null);
      const titleBit = opts.title?.trim() ? `"${opts.title.trim()}"` : null;

      let destination = 'feed';
      let summary: string;
      if (opts.isMoment) {
        destination = 'moment';
        summary = place
          ? `${actorName} shared a Moment from ${place}`
          : `${actorName} shared a Moment`;
      } else if (isShare) {
        destination = 'share';
        summary = place
          ? `${actorName} shared a post to the feed from ${place}`
          : `${actorName} shared a post to the feed`;
      } else if (isSpark && opts.channelId) {
        destination = 'sparks';
        summary = channelName
          ? `${actorName} uploaded a Spark${titleBit ? ' ' + titleBit : ''} as ${channelRole || 'staff'} to channel “${channelName}” in Matterya Hubs${place ? ` (${place})` : ''}`
          : `${actorName} uploaded a Spark${titleBit ? ' ' + titleBit : ''} to a Hubs channel`;
      } else if (isSpark) {
        destination = 'sparks';
        summary = place
          ? `${actorName} uploaded a Spark${titleBit ? ' ' + titleBit : ''} to Matterya Sparks from ${place}`
          : `${actorName} uploaded a Spark${titleBit ? ' ' + titleBit : ''} to Matterya Sparks`;
      } else if (opts.channelId || (isHubLongForm && opts.body.includes('__hub_channel__|'))) {
        destination = 'hubs';
        summary = channelName
          ? `${actorName} uploaded a Hub video${titleBit ? ' ' + titleBit : ''} as ${channelRole || 'staff'} to channel “${channelName}” in Matterya Hubs${place ? ` (${place})` : ''}`
          : `${actorName} uploaded a Hub video${titleBit ? ' ' + titleBit : ''} to Matterya Hubs${place ? ` from ${place}` : ''}`;
      } else if (opts.mediaType === 'video' || opts.mediaType === 'image') {
        destination = 'feed';
        summary = place
          ? `${actorName} uploaded a ${opts.mediaType === 'image' ? 'photo' : 'video'} post to the feed from ${place}`
          : `${actorName} uploaded a ${opts.mediaType === 'image' ? 'photo' : 'video'} post to the feed`;
      } else {
        destination = 'feed';
        summary = place
          ? `${actorName} published a post to the feed from ${place}`
          : `${actorName} published a post to the feed`;
      }

      await emitContentPosted({
        entityId: opts.actorId,
        contentId: opts.postId,
        authorId: opts.authorId,
        mediaType: opts.mediaType,
        countryCode: opts.countryCode,
        countryName: opts.countryName,
        cityName: opts.cityName,
        isSpark,
        isHubLongForm: isHubLongForm && !isSpark,
        isMoment: opts.isMoment,
        sharedPostId: opts.sharedPostId,
        channelId: opts.channelId,
        channelName,
        channelRole,
        title: opts.title,
        summary,
        surface: destination === 'hubs' ? 'hubs' : destination === 'sparks' ? 'sparks' : 'feed',
        mediaUrl: opts.mediaUrl,
        destination,
      });
    } catch (err) {
      console.warn('[posts] emitUploadEvent failed', err);
    }
  }

  async updatePost(
    postId: string,
    authorId: string,
    input: {
      title?: string | null;
      body?: string | null;
      visibility?: string | null;
      media_type?: string | null;
      media_url?: string | null;
      thumb_url?: string | null;
      clear_media?: boolean | null;
    }
  ): Promise<PostRow> {
    const visibility = this.normalizeVisibility(input.visibility);
    const clearMedia = input.clear_media === true;
    const hasMediaUpdate =
      clearMedia ||
      (input.media_url !== undefined && input.media_url !== null && String(input.media_url).trim().length > 0);

    let mediaType: string | null = null;
    let mediaUrl: string | null = null;
    let thumbUrl: string | null = null;

    if (clearMedia) {
      mediaType = 'none';
      mediaUrl = null;
      thumbUrl = null;
    } else if (hasMediaUpdate) {
      mediaUrl = String(input.media_url ?? '').trim() || null;
      mediaType = this.normalizeMediaType(input.media_type, mediaUrl);
      thumbUrl = mediaType === 'none' ? null : (input.thumb_url ?? null);
      if (mediaType === 'none') {
        mediaUrl = null;
        thumbUrl = null;
      }
    }

    const { rows } = await pool.query(
      `
      update public.posts
      set
        title = coalesce($3, title),
        body = coalesce($4, body),
        visibility = coalesce($5, visibility),
        media_type = case when $6::boolean then $7 else media_type end,
        media_url = case when $6::boolean then $8 else media_url end,
        thumb_url = case when $6::boolean then $9 else thumb_url end,
        updated_at = now()
      where id = $1
        and (
          author_id = $2
          or (
            channel_id is not null
            and public.is_channel_admin_or_owner(channel_id, $2::uuid)
          )
        )
      returning id
      `,
      [
        postId,
        authorId,
        input.title?.trim() ?? null,
        input.body?.trim() ?? null,
        visibility,
        hasMediaUpdate,
        mediaType,
        mediaUrl,
        thumbUrl,
      ]
    );

    const updatedId = rows[0]?.id;
    if (!updatedId) throw new Error('POST_UPDATE_NOT_FOUND');
    const post = await this.postByIdForViewer(updatedId, authorId);
    if (!post) throw new Error('Updated post not found.');
    return post;
  }

  async likePost(postId: string, userId: string): Promise<PostRow> {
    const post = await this.ensurePostAccess(postId, userId);
    const client = await pool.connect();
    let inserted = false;

    try {
      await client.query('begin');
      const { rowCount } = await client.query(
        `
        insert into public.post_likes (post_id, user_id)
        values ($1, $2)
        on conflict do nothing
        `,
        [postId, userId]
      );
      inserted = (rowCount ?? 0) > 0;
      if (inserted) {
        await client.query(
          `
          update public.posts
          set like_count = like_count + 1
          where id = $1
          `,
          [postId]
        );
      }
      await client.query('commit');
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }

    const updated = await this.postByIdForViewer(postId, userId);
    if (!updated) throw new Error('POST_NOT_FOUND');

    if (inserted) {
      try {
        await this.notifications.notifyPostLike(post.author_id, userId, postId);
      } catch {}
      void emitServerEngagement({
        entityId: userId,
        eventType: EngagementEventTypes.Liked,
        payload: {
          entityId: userId,
          contentId: postId,
          authorId: post.author_id,
          strength: 0.55,
          surface: 'api',
          mediaType: post.media_type ?? null,
          countryCode: post.country_code ?? null,
        },
      });
    }

    return updated;
  }

  async unlikePost(postId: string, userId: string): Promise<PostRow> {
    await this.ensurePostAccess(postId, userId);
    const client = await pool.connect();
    let removed = false;

    try {
      await client.query('begin');
      const { rowCount } = await client.query(
        `
        delete from public.post_likes
        where post_id = $1 and user_id = $2
        `,
        [postId, userId]
      );
      removed = (rowCount ?? 0) > 0;
      if (removed) {
        await client.query(
          `
          update public.posts
          set like_count = greatest(like_count - 1, 0)
          where id = $1
          `,
          [postId]
        );
      }
      await client.query('commit');
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }

    const updated = await this.postByIdForViewer(postId, userId);
    if (!updated) throw new Error('POST_NOT_FOUND');
    return updated;
  }

  async savePost(postId: string, userId: string): Promise<PostRow> {
    await this.ensurePostAccess(postId, userId);
    await pool.query(
      `
      insert into public.post_bookmarks (post_id, user_id)
      values ($1, $2)
      on conflict do nothing
      `,
      [postId, userId]
    );
    const updated = await this.postByIdForViewer(postId, userId);
    if (!updated) throw new Error('POST_NOT_FOUND');
    return updated;
  }

  async unsavePost(postId: string, userId: string): Promise<PostRow> {
    await this.ensurePostAccess(postId, userId);
    await pool.query(
      `
      delete from public.post_bookmarks
      where post_id = $1 and user_id = $2
      `,
      [postId, userId]
    );
    const updated = await this.postByIdForViewer(postId, userId);
    if (!updated) throw new Error('POST_NOT_FOUND');
    return updated;
  }

  async savedPosts(userId: string, limit: number): Promise<PostRow[]> {
    const safeLimit = Math.max(1, Math.min(100, limit || 25));
    const { rows } = await pool.query(
      `
      select pb.post_id
      from public.post_bookmarks pb
      where pb.user_id = $1
      order by pb.created_at desc
      limit $2
      `,
      [userId, safeLimit]
    );

    const posts: PostRow[] = [];
    for (const row of rows) {
      const post = await this.postByIdForViewer(String(row.post_id), userId);
      if (post) posts.push(post);
    }
    return await presentPostRows(posts);
  }

  async likesByPost(postId: string, limit: number, viewerId: string | null): Promise<PostLikeRow[]> {
    await this.ensurePostAccess(postId, viewerId);
    const safeLimit = Math.max(1, Math.min(100, limit || 25));
    const { rows } = await pool.query(
      `
      select
        pl.user_id,
        pl.created_at,
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', ${await this.avatarSqlExpr('$3::uuid', 'pr')},
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as user
      from public.post_likes pl
      left join public.profiles pr on pr.user_id = pl.user_id
      where pl.post_id = $1
      order by pl.created_at desc
      limit $2
      `,
      [postId, safeLimit, viewerId]
    );

    return rows as PostLikeRow[];
  }

  async commentsByPost(
    postId: string,
    limit: number,
    before: string | null,
    viewerId: string | null
  ): Promise<PostCommentRow[]> {
    await this.ensurePostAccess(postId, viewerId);
    // Allow full R2 comments.json threads (often 50–200+); still bounded for safety.
    const safeLimit = Math.max(1, Math.min(5000, limit || 200));
    const params: Array<string | number | null> = [postId, safeLimit, viewerId];
    const beforeClause = before ? `and c.created_at < $4::timestamptz` : '';
    if (before) params.push(before);
    const likeSelect = await this.commentLikeSelectSql('$3::uuid');
    const avatar = await this.avatarSqlExpr('$3::uuid', 'pr');

    const { rows } = await pool.query(
      `
      select
        c.*,
        ${likeSelect},
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', ${avatar},
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as author
      from public.post_comments c
      left join public.profiles pr on pr.user_id = c.author_id
      where c.post_id = $1
        ${beforeClause}
      order by c.created_at asc, c.id asc
      limit $2
      `,
      params
    );

    return rows as PostCommentRow[];
  }

  async addComment(
    postId: string,
    userId: string,
    body: string,
    parentId?: string | null
  ): Promise<PostCommentRow> {
    const trimmed = String(body ?? '').trim();
    if (!trimmed) throw new Error('Comment is required.');

    const post = await this.ensurePostAccess(postId, userId);
    const client = await pool.connect();
    let commentId: string | null = null;
    let parentAuthorId: string | null = null;
    const parentRef = parentId ? String(parentId) : null;

    try {
      await client.query('begin');
      if (parentRef) {
        const parent = await client.query(
          `
          select id, post_id, author_id
          from public.post_comments
          where id = $1
          limit 1
          `,
          [parentRef]
        );
        const row = parent.rows[0];
        if (!row?.id) throw new Error('PARENT_COMMENT_NOT_FOUND');
        if (row.post_id !== postId) throw new Error('PARENT_COMMENT_MISMATCH');
        parentAuthorId = row.author_id ?? null;
      }
      const insert = await client.query(
        `
        insert into public.post_comments (post_id, author_id, body, parent_id)
        values ($1, $2, $3, $4)
        returning id
        `,
        [postId, userId, trimmed, parentRef]
      );
      commentId = insert.rows[0]?.id ?? null;
      if (!commentId) throw new Error('Failed to add comment.');

      await client.query(
        `
        update public.posts
        set comment_count = comment_count + 1
        where id = $1
        `,
        [postId]
      );

      await client.query('commit');
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }

    const comment = await this.commentById(commentId, userId);
    if (!comment) throw new Error('Comment not found.');

    void emitServerEngagement({
      entityId: userId,
      eventType: EngagementEventTypes.Commented,
      payload: {
        entityId: userId,
        contentId: postId,
        authorId: post.author_id,
        strength: 0.85,
        surface: 'api',
        mediaType: post.media_type ?? null,
        countryCode: post.country_code ?? null,
        meta: { commentId },
      },
    });

    if (post.author_id !== userId) {
      try {
        await this.notifications.notifyPostComment(post.author_id, userId, postId);
      } catch {}
    }
    if (parentAuthorId && parentAuthorId !== userId) {
      try {
        await this.notifications.notifyCommentReply(parentAuthorId, userId, postId);
      } catch {}
    }

    return comment;
  }

  async likeComment(commentId: string, userId: string): Promise<PostCommentRow> {
    const { comment, post } = await this.ensureCommentAccess(commentId, userId);
    if (!(await this.commentLikesEnabled())) {
      const updated = await this.commentById(commentId, userId);
      if (!updated) throw new Error('COMMENT_NOT_FOUND');
      return updated;
    }
    const client = await pool.connect();
    let inserted = false;

    try {
      await client.query('begin');
      const { rowCount } = await client.query(
        `
        insert into public.post_comment_likes (comment_id, user_id)
        values ($1, $2)
        on conflict do nothing
        `,
        [commentId, userId]
      );
      inserted = (rowCount ?? 0) > 0;
      await client.query('commit');
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }

    const updated = await this.commentById(commentId, userId);
    if (!updated) throw new Error('COMMENT_NOT_FOUND');

    if (inserted && comment.author_id !== userId) {
      try {
        await this.notifications.notifyCommentLike(comment.author_id, userId, post.id);
      } catch {}
    }

    return updated;
  }

  async unlikeComment(commentId: string, userId: string): Promise<PostCommentRow> {
    await this.ensureCommentAccess(commentId, userId);
    if (await this.commentLikesEnabled()) {
      await pool.query(
        `
        delete from public.post_comment_likes
        where comment_id = $1 and user_id = $2
        `,
        [commentId, userId]
      );
    }

    const updated = await this.commentById(commentId, userId);
    if (!updated) throw new Error('COMMENT_NOT_FOUND');
    return updated;
  }

  async reportPost(postId: string, userId: string, reason: string): Promise<boolean> {
    const trimmed = String(reason ?? '').trim();
    if (!trimmed) throw new Error('Report reason is required.');
    await this.ensurePostAccess(postId, userId);
    await pool.query(
      `
      insert into public.post_reports (post_id, reporter_id, reason)
      values ($1, $2, $3)
      `,
      [postId, userId, trimmed]
    );
    return true;
  }

  async deletePost(postId: string, authorId: string): Promise<boolean> {
    const client = await pool.connect();
    try {
      await client.query('begin');
      const archived = await client.query(
        `
        insert into public.post_deletes (
          original_post_id,
          deleted_by,
          author_id,
          category_id,
          country_name,
          country_code,
          city_name,
          title,
          body,
          media_type,
          media_url,
          thumb_url,
          visibility,
          like_count,
          comment_count,
          created_at,
          updated_at,
          media_path,
          thumb_path
        )
        select
          p.id,
          $2,
          p.author_id,
          p.category_id,
          p.country_name,
          p.country_code,
          p.city_name,
          p.title,
          p.body,
          p.media_type,
          p.media_url,
          p.thumb_url,
          p.visibility,
          p.like_count,
          p.comment_count,
          p.created_at,
          p.updated_at,
          p.media_path,
          p.thumb_path
        from public.posts p
        where p.id = $1
          and (
            p.author_id = $2
            or (
              p.channel_id is not null
              and public.is_channel_admin_or_owner(p.channel_id, $2::uuid)
            )
          )
        returning original_post_id
        `,
        [postId, authorId]
      );

      if (!archived.rowCount) {
        await client.query('rollback');
        return false;
      }

      await client.query(
        `
        delete from public.posts
        where id = $1
          and (
            author_id = $2
            or (
              channel_id is not null
              and public.is_channel_admin_or_owner(channel_id, $2::uuid)
            )
          )
        `,
        [postId, authorId]
      );
      await client.query('commit');
      return true;
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }
  }

  private async ensurePostAccess(postId: string, viewerId: string | null): Promise<PostRow> {
    const post = await this.postByIdForViewer(postId, viewerId);
    if (!post) throw new Error('POST_FORBIDDEN');
    return post;
  }

  private async postByIdForViewer(id: string, viewerId: string | null): Promise<PostRow | null> {
    // Guard every entry point — callers sometimes pass Archive seed ids.
    if (!isUuid(id)) return null;
    const viewer = viewerId && isUuid(viewerId) ? viewerId : null;
    const savedByMe = await this.savedByMeExpr('$2::uuid');
    const savedByMeShared = await this.savedByMeSharedExpr('$2::uuid');
    const { rows } = await pool.query(
      `
      select
        p.*,
        greatest(
          coalesce(p.like_count, 0),
          (select count(*)::int from public.post_likes pl where pl.post_id = p.id)
        ) as like_count,
        (select count(*)::int from public.post_comments pc where pc.post_id = p.id) as comment_count,
        case
          when $2::uuid is not null
            and exists (
              select 1
              from public.post_likes pl
              where pl.post_id = p.id and pl.user_id = $2::uuid
            )
          then true
          else false
        end as liked_by_me,${savedByMe},
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as author,
        case
          when sp.id is null then null
          else jsonb_build_object(
            'id', sp.id,
            'author_id', sp.author_id,
            'category_id', sp.category_id,
            'country_name', sp.country_name,
            'country_code', sp.country_code,
            'city_name', sp.city_name,
            'title', sp.title,
            'body', sp.body,
            'media_type', sp.media_type,
            'media_url', sp.media_url,
            'thumb_url', sp.thumb_url,
            'visibility', sp.visibility,
            'like_count', greatest(
              coalesce(sp.like_count, 0),
              (select count(*)::int from public.post_likes spl where spl.post_id = sp.id)
            ),
            'comment_count', (select count(*)::int from public.post_comments spc where spc.post_id = sp.id),
            'liked_by_me', case
              when $2::uuid is not null
                and exists (
                  select 1
                  from public.post_likes spl
                  where spl.post_id = sp.id and spl.user_id = $2::uuid
                )
              then true
              else false
            end,${savedByMeShared}
            'created_at', sp.created_at,
            'updated_at', sp.updated_at,
            'author', jsonb_build_object(
              'user_id', spr.user_id,
              'display_name', spr.display_name,
              'username', spr.username,
              'avatar_url', spr.avatar_url,
              'country_name', spr.country_name,
              'country_code', spr.country_code
            )
          )
        end as shared_post
      from public.posts p
      left join public.profiles pr on pr.user_id = p.author_id
      left join public.posts sp on sp.id = p.shared_post_id
        and coalesce(sp.moderation_status, 'active') not in ('hidden', 'deleted')
      left join public.profiles spr on spr.user_id = sp.author_id
      where p.id = $1
        and coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted')
        and (
          p.visibility in ('public', 'country')
          or ($2::uuid is not null and p.author_id = $2::uuid)
          or (
            p.visibility = 'followers'
            and $2::uuid is not null
            and exists (
              select 1
              from public.user_follows f
              where f.follower_id = $2::uuid and f.following_id = p.author_id
            )
          )
        )
        ${await this.privateAuthorVisibleSql('$2::uuid')}
      limit 1
      `,
      [id, viewer]
    );
    return (rows[0] as PostRow) ?? null;
  }

  private async commentById(id: string, viewerId: string | null): Promise<PostCommentRow | null> {
    const likeSelect = await this.commentLikeSelectSql('$2::uuid');
    const avatar = await this.avatarSqlExpr('$2::uuid', 'pr');
    const { rows } = await pool.query(
      `
      select
        c.*,
        ${likeSelect},
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', ${avatar},
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as author
      from public.post_comments c
      left join public.profiles pr on pr.user_id = c.author_id
      where c.id = $1
      limit 1
      `,
      [id, viewerId]
    );
    return (rows[0] as PostCommentRow) ?? null;
  }

  private async ensureCommentAccess(
    commentId: string,
    viewerId: string | null
  ): Promise<{ comment: PostCommentRow; post: PostRow }> {
    const comment = await this.commentById(commentId, viewerId);
    if (!comment) throw new Error('COMMENT_NOT_FOUND');
    const post = await this.postByIdForViewer(comment.post_id, viewerId);
    if (!post) throw new Error('POST_FORBIDDEN');
    return { comment, post };
  }

  private normalizeVisibility(value?: string | null): string | null {
    if (!value) return null;
    const normalized = String(value).trim().toLowerCase();
    if (!normalized) return null;
    const allowed = new Set(['public', 'country', 'followers', 'private']);
    if (!allowed.has(normalized)) {
      throw new Error('INVALID_VISIBILITY');
    }
    return normalized;
  }

  private normalizeMediaType(value?: string | null, url?: string | null): string {
    const normalized = String(value ?? '').trim().toLowerCase();
    if (!normalized) return url ? 'image' : 'none';
    // Sparks / reels are first-class — never coerce to "none" (that hid new Sparks from profile).
    const allowed = new Set(['none', 'image', 'video', 'link', 'story', 'reel', 'spark']);
    if (!allowed.has(normalized)) return 'none';
    if (normalized === 'none') return 'none';
    if (!url) return 'none';
    // Persist as reel for spark/reel so clients can filter reliably.
    if (normalized === 'spark') return 'reel';
    return normalized;
  }

  private async resolveCategoryId(countryCode?: string | null): Promise<string> {
    const iso = (countryCode || 'GLOBAL').toUpperCase();

    const byCountry = await pool.query(
      `
      select id
      from public.categories
      where upper(coalesce(country_code, '')) = $1
      order by created_at asc
      limit 1
      `,
      [iso]
    );

    const found = byCountry.rows[0]?.id;
    if (found) return found as string;

    const global = await pool.query(
      `
      select id
      from public.categories
      where is_global = true
      order by created_at asc
      limit 1
      `
    );

    const globalId = global.rows[0]?.id;
    if (globalId) return globalId as string;

    throw new Error('No categories available. Seed public.categories first.');
  }
}
