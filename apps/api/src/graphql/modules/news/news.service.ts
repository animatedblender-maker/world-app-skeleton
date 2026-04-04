import { GraphQLError } from 'graphql';

import { pool } from '../../../db.js';
import { PostsService } from '../posts/posts.service.js';

export type ExternalNewsItem = {
  id: string;
  provider: string;
  provider_item_id: string;
  title: string;
  url: string;
  source_name?: string | null;
  published_at?: string | null;
  country_codes: string[];
  country_names: string[];
  disaster_types: string[];
  theme_names: string[];
  format?: string | null;
  language?: string | null;
  snippet?: string | null;
  image_url?: string | null;
  like_count: number;
  liked_by_me: boolean;
  comment_count: number;
  shared_post_count: number;
};

type ExternalNewsCommentRow = {
  id: string;
  news_item_id: string;
  parent_id: string | null;
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

type SerpApiNewsResult = {
  title?: string | null;
  link?: string | null;
  source?:
    | string
    | {
        name?: string | null;
        icon?: string | null;
      }
    | null;
  source_logo?: string | null;
  date?: string | null;
  snippet?: string | null;
  thumbnail?: string | null;
  image?: string | null;
  stories?: SerpApiNewsResult[] | null;
};

type SerpApiResponse = {
  news_results?: SerpApiNewsResult[] | null;
  top_stories?: SerpApiNewsResult[] | null;
};

type NewsCounts = {
  like_count: number;
  liked_by_me: boolean;
  comment_count: number;
  shared_post_count: number;
};

const SERPAPI_API_URL = process.env.SERPAPI_API_URL ?? 'https://serpapi.com/search.json';
const SERPAPI_API_KEY = (process.env.SERPAPI_API_KEY ?? '').trim();
const SERPAPI_TIMEOUT_MS = Number(process.env.SERPAPI_TIMEOUT_MS ?? 8000);
const SERPAPI_ENGINE = (process.env.SERPAPI_ENGINE ?? 'google').trim() || 'google';
const SERPAPI_QUERY = (process.env.SERPAPI_QUERY ?? 'news').trim() || 'news';
const SERPAPI_GL = (process.env.SERPAPI_GL ?? 'eg').trim().toLowerCase() || 'eg';
const SERPAPI_HL = (process.env.SERPAPI_HL ?? 'en').trim().toLowerCase() || 'en';
const SERPAPI_TBM = (process.env.SERPAPI_TBM ?? 'nws').trim().toLowerCase() || 'nws';

function ensureSerpApiConfigured(): void {
  if (!SERPAPI_API_KEY) {
    throw new GraphQLError('provider access is not configured: missing SERPAPI_API_KEY', {
      extensions: { code: 'SERVICE_NOT_CONFIGURED' },
    });
  }
}

function plainTextSnippet(raw: string | null | undefined, max = 220): string | null {
  const text = String(raw ?? '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!text) return null;
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1).trim()}…`;
}

function normalizeArticleUrl(value: string | null | undefined): string {
  const url = String(value ?? '').trim();
  return url;
}

function sourceNameFromResult(source: SerpApiNewsResult['source']): string {
  if (typeof source === 'string') {
    const value = source.trim();
    return value || 'Google News';
  }
  const value = String(source?.name ?? '').trim();
  return value || 'Google News';
}

function sourceIconFromResult(result: SerpApiNewsResult): string | null {
  if (typeof result.source === 'object' && result.source?.icon) {
    const icon = String(result.source.icon).trim();
    if (icon) return icon;
  }
  const logo = String(result.source_logo ?? '').trim();
  return logo || null;
}

function normalizeGl(value: string | null | undefined): string {
  const gl = String(value ?? '').trim().toLowerCase();
  return /^[a-z]{2}$/.test(gl) ? gl : SERPAPI_GL;
}

function countryNameFromCode(countryCode: string): string | null {
  const code = String(countryCode ?? '').trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(code)) return null;
  try {
    const display = new Intl.DisplayNames(['en'], { type: 'region' });
    return display.of(code) ?? null;
  } catch {
    return null;
  }
}

function articleIdFromUrl(value: string, gl: string): string {
  return `${normalizeGl(gl)}:${Buffer.from(value, 'utf8').toString('base64url')}`;
}

function parseArticleId(value: string): { gl: string; urlToken: string } | null {
  const trimmed = String(value ?? '').trim();
  const separator = trimmed.indexOf(':');
  if (separator <= 0) return null;
  const gl = normalizeGl(trimmed.slice(0, separator));
  const urlToken = trimmed.slice(separator + 1).trim();
  if (!urlToken) return null;
  return { gl, urlToken };
}

function mapSerpApiResult(result: SerpApiNewsResult, gl: string): ExternalNewsItem | null {
  const url = normalizeArticleUrl(result.link);
  if (!url) return null;
  const title = String(result.title ?? 'Untitled news article').trim() || 'Untitled news article';
  const normalizedGl = normalizeGl(gl);
  const id = articleIdFromUrl(url, normalizedGl);
  const sourceName = sourceNameFromResult(result.source);
  const imageUrl = String(result.thumbnail ?? result.image ?? sourceIconFromResult(result) ?? '').trim() || null;
  const countryName = countryNameFromCode(normalizedGl) ?? normalizedGl.toUpperCase();

  return {
    id,
    provider: 'serpapi',
    provider_item_id: id,
    title,
    url,
    source_name: sourceName,
    published_at: String(result.date ?? '').trim() || null,
    country_codes: [normalizedGl.toUpperCase()],
    country_names: [countryName],
    disaster_types: [],
    theme_names: ['News'],
    format: 'article',
    language: SERPAPI_HL,
    snippet: plainTextSnippet(result.snippet),
    image_url: imageUrl,
    like_count: 0,
    liked_by_me: false,
    comment_count: 0,
    shared_post_count: 0,
  };
}

function flattenSerpApiResults(items: SerpApiNewsResult[] | null | undefined): SerpApiNewsResult[] {
  const flattened: SerpApiNewsResult[] = [];
  for (const item of items ?? []) {
    const directLink = normalizeArticleUrl(item?.link);
    if (directLink) {
      flattened.push(item);
    }
    for (const story of item?.stories ?? []) {
      if (normalizeArticleUrl(story?.link)) {
        flattened.push({
          ...story,
          thumbnail: story.thumbnail ?? item.thumbnail ?? item.image ?? null,
          image: story.image ?? item.image ?? null,
        });
      }
    }
  }
  return flattened;
}

async function fetchSerpApiNews(limit: number, offset: number, gl = SERPAPI_GL): Promise<ExternalNewsItem[]> {
  ensureSerpApiConfigured();
  const safeLimit = Math.max(1, Math.min(limit || 10, 20));
  const normalizedGl = normalizeGl(gl);
  const page = Math.floor(Math.max(0, offset || 0) / safeLimit) + 1;
  const params = new URLSearchParams({
    engine: SERPAPI_ENGINE,
    q: SERPAPI_QUERY,
    gl: normalizedGl,
    hl: SERPAPI_HL,
    tbm: SERPAPI_TBM,
    api_key: SERPAPI_API_KEY,
    no_cache: 'true',
    page: String(page),
  });

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), SERPAPI_TIMEOUT_MS);

  try {
    const response = await fetch(`${SERPAPI_API_URL}?${params.toString()}`, {
      method: 'GET',
      headers: {
        Accept: 'application/json',
      },
      signal: controller.signal,
    });

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new GraphQLError(
        `SerpApi request failed (${response.status}). ${body || 'Please verify SERPAPI_API_KEY on Render.'}`.trim(),
        { extensions: { code: 'UPSTREAM_REQUEST_FAILED' } }
      );
    }

    const json = (await response.json()) as SerpApiResponse;
    const rawItems = flattenSerpApiResults([...(json.news_results ?? []), ...(json.top_stories ?? [])]);
    const items = rawItems
      .map((item) => mapSerpApiResult(item, normalizedGl))
      .filter((item): item is ExternalNewsItem => !!item);
    return items.slice(0, safeLimit);
  } catch (error: any) {
    if (error instanceof GraphQLError) throw error;
    if (error?.name === 'AbortError') {
      throw new GraphQLError('SerpApi request timed out.', {
        extensions: { code: 'UPSTREAM_TIMEOUT' },
      });
    }
    throw new GraphQLError(error?.message ?? 'Failed to load news updates.', {
      extensions: { code: 'UPSTREAM_REQUEST_FAILED' },
    });
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchSerpApiNewsById(newsItemId: string): Promise<ExternalNewsItem | null> {
  const id = String(newsItemId ?? '').trim();
  if (!id) return null;
  const parsed = parseArticleId(id);
  const items = await fetchSerpApiNews(20, 0, parsed?.gl ?? SERPAPI_GL);
  return items.find((item) => item.id === id) ?? null;
}

async function newsCountsById(newsItemIds: string[], viewerId: string | null): Promise<Map<string, NewsCounts>> {
  const ids = Array.from(new Set((newsItemIds ?? []).map((value) => String(value ?? '').trim()).filter(Boolean)));
  const counts = new Map<string, NewsCounts>();

  for (const id of ids) {
    counts.set(id, {
      like_count: 0,
      liked_by_me: false,
      comment_count: 0,
      shared_post_count: 0,
    });
  }

  if (!ids.length) return counts;

  const { rows } = await pool.query(
    `
    with ids as (
      select unnest($1::text[]) as news_item_id
    ),
    likes as (
      select news_item_id, count(*)::int as total
      from public.external_news_likes
      where news_item_id = any($1::text[])
      group by news_item_id
    ),
    comments as (
      select news_item_id, count(*)::int as total
      from public.external_news_comments
      where news_item_id = any($1::text[])
      group by news_item_id
    ),
    shares as (
      select news_item_id, count(*)::int as total
      from public.external_news_shares
      where news_item_id = any($1::text[])
      group by news_item_id
    ),
    viewer_likes as (
      select distinct news_item_id
      from public.external_news_likes
      where news_item_id = any($1::text[])
        and $2::uuid is not null
        and user_id = $2::uuid
    )
    select
      ids.news_item_id,
      coalesce(likes.total, 0) as like_count,
      coalesce(comments.total, 0) as comment_count,
      coalesce(shares.total, 0) as shared_post_count,
      (viewer_likes.news_item_id is not null) as liked_by_me
    from ids
    left join likes on likes.news_item_id = ids.news_item_id
    left join comments on comments.news_item_id = ids.news_item_id
    left join shares on shares.news_item_id = ids.news_item_id
    left join viewer_likes on viewer_likes.news_item_id = ids.news_item_id
    `,
    [ids, viewerId]
  );

  for (const row of rows) {
    counts.set(String(row.news_item_id), {
      like_count: Number(row.like_count ?? 0),
      liked_by_me: !!row.liked_by_me,
      comment_count: Number(row.comment_count ?? 0),
      shared_post_count: Number(row.shared_post_count ?? 0),
    });
  }

  return counts;
}

function withCounts(items: ExternalNewsItem[], counts: Map<string, NewsCounts>): ExternalNewsItem[] {
  return items.map((item) => {
    const row = counts.get(item.id);
    if (!row) return item;
    return {
      ...item,
      like_count: row.like_count,
      liked_by_me: row.liked_by_me,
      comment_count: row.comment_count,
      shared_post_count: row.shared_post_count,
    };
  });
}

async function profileCountryByUser(userId: string): Promise<{ country_name: string; country_code: string; city_name: string | null } | null> {
  const { rows } = await pool.query(
    `
    select country_name, country_code, city_name
    from public.profiles
    where user_id = $1
    limit 1
    `,
    [userId]
  );

  const row = rows[0];
  if (!row?.country_name || !row?.country_code) return null;

  return {
    country_name: String(row.country_name),
    country_code: String(row.country_code).toUpperCase(),
    city_name: row.city_name ?? null,
  };
}

export class NewsService {
  private posts = new PostsService();

  async countryConflictUpdates(countryCode: string, limit = 10, offset = 0, viewerId: string | null = null): Promise<ExternalNewsItem[]> {
    const items = await fetchSerpApiNews(limit, offset, countryCode);
    const counts = await newsCountsById(items.map((item) => item.id), viewerId);
    return withCounts(items, counts);
  }

  async globalConflictUpdates(limit = 10, offset = 0, viewerId: string | null = null): Promise<ExternalNewsItem[]> {
    const items = await fetchSerpApiNews(limit, offset);
    const counts = await newsCountsById(items.map((item) => item.id), viewerId);
    return withCounts(items, counts);
  }

  async externalNewsItem(newsItemId: string, viewerId: string | null = null): Promise<ExternalNewsItem | null> {
    const item = await fetchSerpApiNewsById(newsItemId);
    if (!item) return null;
    const counts = await newsCountsById([item.id], viewerId);
    return withCounts([item], counts)[0] ?? null;
  }

  async externalNewsComments(
    newsItemId: string,
    limit = 25,
    before: string | null = null
  ): Promise<ExternalNewsCommentRow[]> {
    const safeLimit = Math.max(1, Math.min(limit || 25, 100));
    const params: Array<string | number> = [newsItemId, safeLimit];
    const beforeClause = before ? `and c.created_at < $3::timestamptz` : '';
    if (before) params.push(before);

    const { rows } = await pool.query(
      `
      select
        c.id,
        c.news_item_id,
        c.parent_id,
        c.author_id,
        c.body,
        c.created_at,
        c.updated_at,
        jsonb_build_object(
          'user_id', pr.user_id,
          'display_name', pr.display_name,
          'username', pr.username,
          'avatar_url', pr.avatar_url,
          'country_name', pr.country_name,
          'country_code', pr.country_code
        ) as author
      from public.external_news_comments c
      left join public.profiles pr on pr.user_id = c.author_id
      where c.news_item_id = $1
        ${beforeClause}
      order by c.created_at asc, c.id asc
      limit $2
      `,
      params
    );

    return rows as ExternalNewsCommentRow[];
  }

  async addExternalNewsComment(
    newsItemId: string,
    userId: string,
    body: string,
    parentId: string | null = null
  ): Promise<ExternalNewsCommentRow> {
    const trimmed = String(body ?? '').trim();
    if (!trimmed) {
      throw new GraphQLError('Comment body is required.', {
        extensions: { code: 'BAD_USER_INPUT' },
      });
    }

    const item = await this.externalNewsItem(newsItemId, userId);
    if (!item) {
      throw new GraphQLError('News item not found.', {
        extensions: { code: 'NOT_FOUND' },
      });
    }

    const client = await pool.connect();
    let commentId: string | null = null;

    try {
      await client.query('begin');

      if (parentId) {
        const parent = await client.query(
          `
          select id, news_item_id
          from public.external_news_comments
          where id = $1
          limit 1
          `,
          [parentId]
        );
        const row = parent.rows[0];
        if (!row?.id) throw new Error('PARENT_COMMENT_NOT_FOUND');
        if (String(row.news_item_id) !== item.id) throw new Error('PARENT_COMMENT_MISMATCH');
      }

      const insert = await client.query(
        `
        insert into public.external_news_comments (news_item_id, author_id, body, parent_id)
        values ($1, $2, $3, $4)
        returning id
        `,
        [item.id, userId, trimmed, parentId]
      );
      commentId = insert.rows[0]?.id ?? null;
      await client.query('commit');
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }

    if (!commentId) throw new Error('Failed to create news comment.');

    const comments = await this.externalNewsComments(item.id, 1, null);
    const created = comments.find((entry) => entry.id === commentId);
    if (!created) throw new Error('Comment created but could not be loaded.');
    return created;
  }

  async likeExternalNews(newsItemId: string, userId: string): Promise<ExternalNewsItem> {
    const item = await this.externalNewsItem(newsItemId, userId);
    if (!item) {
      throw new GraphQLError('News item not found.', {
        extensions: { code: 'NOT_FOUND' },
      });
    }

    await pool.query(
      `
      insert into public.external_news_likes (news_item_id, user_id)
      values ($1, $2)
      on conflict do nothing
      `,
      [item.id, userId]
    );

    const updated = await this.externalNewsItem(item.id, userId);
    if (!updated) throw new Error('News item not found after like.');
    return updated;
  }

  async unlikeExternalNews(newsItemId: string, userId: string): Promise<ExternalNewsItem> {
    const item = await this.externalNewsItem(newsItemId, userId);
    if (!item) {
      throw new GraphQLError('News item not found.', {
        extensions: { code: 'NOT_FOUND' },
      });
    }

    await pool.query(
      `
      delete from public.external_news_likes
      where news_item_id = $1 and user_id = $2
      `,
      [item.id, userId]
    );

    const updated = await this.externalNewsItem(item.id, userId);
    if (!updated) throw new Error('News item not found after unlike.');
    return updated;
  }

  async shareExternalNewsToCountry(newsItemId: string, userId: string, body?: string | null, visibility?: string | null) {
    const item = await this.externalNewsItem(newsItemId, userId);
    if (!item) {
      throw new GraphQLError('News item not found.', {
        extensions: { code: 'NOT_FOUND' },
      });
    }

    const profileCountry = await profileCountryByUser(userId);
    if (!profileCountry) {
      throw new GraphQLError('Set your country before sharing news to the feed.', {
        extensions: { code: 'BAD_USER_INPUT' },
      });
    }

    const caption = String(body ?? '').trim();
    const sourceLine = [item.source_name || 'Google News', item.url].filter(Boolean).join(' · ');
    const postBody = [caption, sourceLine].filter(Boolean).join('\n\n') || sourceLine;
    const mediaUrl = item.image_url || null;
    const mediaType = mediaUrl ? 'image' : 'none';

    const post = await this.posts.createPost(userId, {
      title: item.title,
      body: postBody,
      country_name: profileCountry.country_name,
      country_code: profileCountry.country_code,
      city_name: profileCountry.city_name,
      visibility: visibility ?? 'country',
      media_type: mediaType,
      media_url: mediaUrl,
      thumb_url: mediaUrl,
    });

    await pool.query(
      `
      insert into public.external_news_shares (news_item_id, post_id, shared_by)
      values ($1, $2, $3)
      on conflict (post_id) do nothing
      `,
      [item.id, post.id, userId]
    );

    return post;
  }
}
