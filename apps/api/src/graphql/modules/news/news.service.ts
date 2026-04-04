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

type ReliefWebEntity = {
  id?: number | string;
  name?: string | null;
  shortname?: string | null;
  iso3?: string | null;
  code?: string | null;
};

type ReliefWebFields = {
  title?: string | null;
  body?: string | null;
  source?: ReliefWebEntity[] | null;
  country?: ReliefWebEntity[] | null;
  disaster_type?: ReliefWebEntity[] | null;
  theme?: ReliefWebEntity[] | null;
  format?: ReliefWebEntity[] | null;
  language?: ReliefWebEntity[] | null;
  date?: {
    original?: string | null;
    created?: string | null;
  } | null;
  file?: Array<{ url?: string | null }> | null;
};

type ReliefWebReport = {
  id?: number | string;
  href?: string | null;
  fields?: ReliefWebFields | null;
};

type ReliefWebResponse = {
  data?: ReliefWebReport[];
};

type NewsCounts = {
  like_count: number;
  liked_by_me: boolean;
  comment_count: number;
  shared_post_count: number;
};

const RELIEFWEB_API_URL = process.env.RELIEFWEB_API_URL ?? 'https://api.reliefweb.int/v2/reports';
const RELIEFWEB_APPNAME = (process.env.RELIEFWEB_APPNAME ?? '').trim();
const RELIEFWEB_TIMEOUT_MS = Number(process.env.RELIEFWEB_TIMEOUT_MS ?? 8000);
const RELIEFWEB_USER_AGENT =
  process.env.RELIEFWEB_USER_AGENT ??
  `Matterya/1.0 (${RELIEFWEB_APPNAME || 'reliefweb-client'})`;

function ensureReliefWebConfigured(): void {
  if (!RELIEFWEB_APPNAME) {
    throw new GraphQLError('provider access is not configured: missing RELIEFWEB_APPNAME', {
      extensions: { code: 'SERVICE_NOT_CONFIGURED' },
    });
  }
}

function iso2ToCountryName(countryCode: string): string | null {
  const code = String(countryCode ?? '').trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(code)) return null;
  try {
    const display = new Intl.DisplayNames(['en'], { type: 'region' });
    return display.of(code) ?? null;
  } catch {
    return null;
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

function entityNames(items: ReliefWebEntity[] | null | undefined): string[] {
  return (items ?? [])
    .map((item) => String(item?.name ?? item?.shortname ?? '').trim())
    .filter(Boolean);
}

function entityCodes(items: ReliefWebEntity[] | null | undefined): string[] {
  return (items ?? [])
    .map((item) => String(item?.iso3 ?? item?.code ?? '').trim().toUpperCase())
    .filter(Boolean);
}

function mapReport(report: ReliefWebReport): ExternalNewsItem {
  const fields = report.fields ?? {};
  const id = String(report.id ?? '').trim();
  const href = String(report.href ?? '').trim();
  const title = String(fields.title ?? 'Untitled ReliefWeb report').trim();
  const source = fields.source?.[0];
  const format = fields.format?.[0];
  const language = fields.language?.[0];

  return {
    id,
    provider: 'reliefweb',
    provider_item_id: id,
    title,
    url: href || `https://reliefweb.int/node/${id}`,
    source_name: source?.shortname || source?.name || 'ReliefWeb',
    published_at: fields.date?.original || fields.date?.created || null,
    country_codes: entityCodes(fields.country),
    country_names: entityNames(fields.country),
    disaster_types: entityNames(fields.disaster_type),
    theme_names: entityNames(fields.theme),
    format: format?.name ?? null,
    language: language?.code || language?.name || null,
    snippet: plainTextSnippet(fields.body),
    image_url: fields.file?.[0]?.url ?? null,
    like_count: 0,
    liked_by_me: false,
    comment_count: 0,
    shared_post_count: 0,
  };
}

async function fetchReliefWebReports(
  limit: number,
  offset: number,
  countryName?: string | null,
  filter?: Record<string, unknown>
): Promise<ExternalNewsItem[]> {
  ensureReliefWebConfigured();

  const payload: Record<string, unknown> = {
    limit: Math.max(1, Math.min(limit || 10, 20)),
    offset: Math.max(0, offset || 0),
    sort: ['date.original:desc'],
    fields: {
      include: [
        'title',
        'body',
        'source',
        'country',
        'disaster_type',
        'theme',
        'format',
        'language',
        'date.original',
        'date.created',
        'file.url',
      ],
    },
  };

  if (filter) {
    payload['filter'] = filter;
  } else if (countryName) {
    payload['filter'] = {
      field: 'country',
      value: [countryName],
      operator: 'OR',
    };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), RELIEFWEB_TIMEOUT_MS);

  try {
    const response = await fetch(`${RELIEFWEB_API_URL}?appname=${encodeURIComponent(RELIEFWEB_APPNAME)}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'User-Agent': RELIEFWEB_USER_AGENT,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new GraphQLError(
        `ReliefWeb request failed (${response.status}). ${body || 'Please verify RELIEFWEB_APPNAME on Render.'}`.trim(),
        { extensions: { code: 'UPSTREAM_REQUEST_FAILED' } }
      );
    }

    const json = (await response.json()) as ReliefWebResponse;
    return (json.data ?? []).map(mapReport);
  } catch (error: any) {
    if (error instanceof GraphQLError) throw error;
    if (error?.name === 'AbortError') {
      throw new GraphQLError('ReliefWeb request timed out.', {
        extensions: { code: 'UPSTREAM_TIMEOUT' },
      });
    }
    throw new GraphQLError(error?.message ?? 'Failed to load ReliefWeb updates.', {
      extensions: { code: 'UPSTREAM_REQUEST_FAILED' },
    });
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchReliefWebReportById(newsItemId: string): Promise<ExternalNewsItem | null> {
  const id = String(newsItemId ?? '').trim();
  if (!id) return null;
  const items = await fetchReliefWebReports(1, 0, null, {
    field: 'id',
    value: [id],
    operator: 'OR',
  });
  return items[0] ?? null;
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
    const countryName = iso2ToCountryName(countryCode);
    if (!countryName) return [];
    const items = await fetchReliefWebReports(limit, offset, countryName);
    const counts = await newsCountsById(items.map((item) => item.id), viewerId);
    return withCounts(items, counts);
  }

  async globalConflictUpdates(limit = 10, offset = 0, viewerId: string | null = null): Promise<ExternalNewsItem[]> {
    const items = await fetchReliefWebReports(limit, offset);
    const counts = await newsCountsById(items.map((item) => item.id), viewerId);
    return withCounts(items, counts);
  }

  async externalNewsItem(newsItemId: string, viewerId: string | null = null): Promise<ExternalNewsItem | null> {
    const item = await fetchReliefWebReportById(newsItemId);
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
    const sourceLine = [item.source_name || 'ReliefWeb', item.url].filter(Boolean).join(' · ');
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
