import { pool } from '../../../db.ts';

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

type CreatePostInput = {
  title?: string | null;
  body: string;
  country_name: string;
  country_code: string;
  city_name?: string | null;
};

export class PostsService {
  async postsByCountry(code: string, limit: number): Promise<PostRow[]> {
    const iso = (code || '').toUpperCase();
    const { rows } = await pool.query(
      `
      select
        p.*,
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
      order by p.created_at desc
      limit $2
      `,
      [iso, Math.max(1, limit)]
    );

    return rows as PostRow[];
  }

  async createPost(authorId: string, input: CreatePostInput): Promise<PostRow> {
    const categoryId = await this.resolveCategoryId(input.country_code);
    const iso = (input.country_code || '').toUpperCase();

    const { rows } = await pool.query(
      `
      insert into public.posts
        (author_id, category_id, country_name, country_code, city_name, title, body)
      values
        ($1, $2, $3, $4, $5, $6, $7)
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
      ]
    );

    const createdId = rows[0]?.id;
    if (!createdId) throw new Error('Failed to create post.');

    const post = await this.postById(createdId);
    if (!post) throw new Error('Newly created post not found.');
    return post;
  }

  private async postById(id: string): Promise<PostRow | null> {
    const { rows } = await pool.query(
      `
      select
        p.*,
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
      limit 1
      `,
      [id]
    );
    return (rows[0] as PostRow) ?? null;
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
