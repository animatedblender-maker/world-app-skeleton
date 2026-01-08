import { pool } from '../../../db.js';
import { NotificationsService } from '../notifications/notifications.service.js';

type PostRow = {
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
  created_at: string;
  updated_at: string;
  author: {
    user_id: string;
    display_name: string | null;
    username: string | null;
    avatar_url: string | null;
    country_name: string | null;
    country_code: string | null;
  } | null;
};

type PostCommentRow = {
  id: string;
  post_id: string;
  author_id: string;
  body: string;
  created_at: string;
  updated_at: string;
  author: {
    user_id: string;
    display_name: string | null;
    username: string | null;
    avatar_url: string | null;
    country_name: string | null;
    country_code: string | null;
  } | null;
};

type PostLikeRow = {
  user_id: string;
  created_at: string;
  user: {
    user_id: string;
    display_name: string | null;
    username: string | null;
    avatar_url: string | null;
    country_name: string | null;
    country_code: string | null;
  } | null;
};

type CreatePostInput = {
  title?: string | null;
  body: string;
  country_name: string;
  country_code: string;
  city_name?: string | null;
  visibility?: string | null;
};

export class PostsService {
  private notifications = new NotificationsService();

  async postsByCountry(code: string, limit: number, viewerId: string | null): Promise<PostRow[]> {
    const iso = (code || '').toUpperCase();
    const { rows } = await pool.query(
      `
      select
        p.*,
        (select count(*)::int from public.post_likes pl where pl.post_id = p.id) as like_count,
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
        end as liked_by_me,
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as author
      from public.posts p
      left join public.profiles pr on pr.user_id = p.author_id
      where upper(coalesce(p.country_code, '')) = $1
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
      order by p.created_at asc, p.id asc
      limit $2
      `,
      [iso, Math.max(1, limit), viewerId]
    );

    return rows as PostRow[];
  }

  async postsByAuthor(authorId: string, limit: number, viewerId: string | null): Promise<PostRow[]> {
    const isOwner = !!viewerId && viewerId === authorId;
    if (isOwner) {
      const { rows } = await pool.query(
        `
        select
          p.*,
          (select count(*)::int from public.post_likes pl where pl.post_id = p.id) as like_count,
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
          end as liked_by_me,
          jsonb_build_object(
            'user_id', pr.user_id,
            'display_name', pr.display_name,
            'username', pr.username,
            'avatar_url', pr.avatar_url,
            'country_name', pr.country_name,
            'country_code', pr.country_code
          ) as author
        from public.posts p
        left join public.profiles pr on pr.user_id = p.author_id
        where p.author_id = $1
        order by p.created_at desc
        limit $3
        `,
        [authorId, viewerId, Math.max(1, limit)]
      );

      return rows as PostRow[];
    }

    const { rows } = await pool.query(
      `
      select
        p.*,
        (select count(*)::int from public.post_likes pl where pl.post_id = p.id) as like_count,
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
        end as liked_by_me,
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as author
      from public.posts p
      left join public.profiles pr on pr.user_id = p.author_id
      where p.author_id = $1
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

    return rows as PostRow[];
  }

  async postById(postId: string, viewerId: string | null): Promise<PostRow | null> {
    if (!postId) return null;
    return await this.postByIdForViewer(postId, viewerId);
  }

  async createPost(authorId: string, input: CreatePostInput): Promise<PostRow> {
    const categoryId = await this.resolveCategoryId(input.country_code);
    const iso = (input.country_code || '').toUpperCase();
    const visibility = this.normalizeVisibility(input.visibility) ?? 'public';

    const { rows } = await pool.query(
      `
      insert into public.posts
        (author_id, category_id, country_name, country_code, city_name, title, body, visibility)
      values
        ($1, $2, $3, $4, $5, $6, $7, $8)
      returning id
      `,
      [
        authorId,
        categoryId,
        input.country_name,
        iso,
        input.city_name ?? null,
        input.title?.trim() || null,
        input.body.trim(),
        visibility,
      ]
    );

    const createdId = rows[0]?.id;
    if (!createdId) throw new Error('Failed to create post.');

    const post = await this.postByIdForViewer(createdId, authorId);
    if (!post) throw new Error('Newly created post not found.');
    return post;
  }

  async updatePost(postId: string, authorId: string, input: { title?: string | null; body?: string | null; visibility?: string | null }): Promise<PostRow> {
    const visibility = this.normalizeVisibility(input.visibility);
    const { rows } = await pool.query(
      `
      update public.posts
      set
        title = coalesce($3, title),
        body = coalesce($4, body),
        visibility = coalesce($5, visibility),
        updated_at = now()
      where id = $1 and author_id = $2
      returning id
      `,
      [
        postId,
        authorId,
        input.title?.trim() ?? null,
        input.body?.trim() ?? null,
        visibility,
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
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as user
      from public.post_likes pl
      left join public.profiles pr on pr.user_id = pl.user_id
      where pl.post_id = $1
      order by pl.created_at desc
      limit $2
      `,
      [postId, safeLimit]
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
    const safeLimit = Math.max(1, Math.min(100, limit || 20));
    const params: Array<string | number> = [postId, safeLimit];
    const beforeClause = before ? `and c.created_at < $3::timestamptz` : '';
    if (before) params.push(before);

    const { rows } = await pool.query(
      `
      select
        c.*,
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
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

  async addComment(postId: string, userId: string, body: string): Promise<PostCommentRow> {
    const trimmed = String(body ?? '').trim();
    if (!trimmed) throw new Error('Comment is required.');

    const post = await this.ensurePostAccess(postId, userId);
    const client = await pool.connect();
    let commentId: string | null = null;

    try {
      await client.query('begin');
      const insert = await client.query(
        `
        insert into public.post_comments (post_id, author_id, body)
        values ($1, $2, $3)
        returning id
        `,
        [postId, userId, trimmed]
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

    const comment = await this.commentById(commentId);
    if (!comment) throw new Error('Comment not found.');

    if (post.author_id !== userId) {
      try {
        await this.notifications.notifyPostComment(post.author_id, userId, postId);
      } catch {}
    }

    return comment;
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
        where p.id = $1 and p.author_id = $2
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
        where id = $1 and author_id = $2
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
    const { rows } = await pool.query(
      `
      select
        p.*,
        (select count(*)::int from public.post_likes pl where pl.post_id = p.id) as like_count,
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
        end as liked_by_me,
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as author
      from public.posts p
      left join public.profiles pr on pr.user_id = p.author_id
      where p.id = $1
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
      limit 1
      `,
      [id, viewerId]
    );
    return (rows[0] as PostRow) ?? null;
  }

  private async commentById(id: string): Promise<PostCommentRow | null> {
    const { rows } = await pool.query(
      `
      select
        c.*,
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as author
      from public.post_comments c
      left join public.profiles pr on pr.user_id = c.author_id
      where c.id = $1
      limit 1
      `,
      [id]
    );
    return (rows[0] as PostCommentRow) ?? null;
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
