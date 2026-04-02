import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { pool } from '../../../db.js';
import { ReliefWebClient, type ReliefWebNormalizedReport } from '../../../external/reliefweb.client.js';
import { PostsService } from '../posts/posts.service.js';

type ExternalNewsItemRow = {
  id: string;
  provider: string;
  provider_item_id: string;
  title: string;
  url: string;
  source_name: string | null;
  published_at: string | null;
  country_codes: string[];
  country_names: string[];
  disaster_types: string[];
  theme_names: string[];
  format: string | null;
  language: string | null;
  snippet: string | null;
  image_url: string | null;
  comment_count: number;
  shared_post_count: number;
  last_seen_at: string | null;
};

type ExternalNewsCommentRow = {
  id: string;
  news_item_id: string;
  parent_id: string | null;
  author_id: string;
  body: string;
  created_at: string;
  updated_at: string;
  author: any;
};

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const COUNTRIES_GEOJSON = path.resolve(__dirname, '../../data/countries50m.geojson');
const CACHE_TTL_MS = 15 * 60 * 1000;

let countryNameMapPromise: Promise<Map<string, string>> | null = null;

export class NewsService {
  private reliefweb = new ReliefWebClient();
  private posts = new PostsService();

  async getCountryConflictUpdates(
    countryCode: string,
    limit: number,
    offset: number
  ): Promise<ExternalNewsItemRow[]> {
    const iso2 = this.normalizeCountryCode(countryCode);
    if (!iso2) throw new Error('country_code is required');

    const cached = await this.listCountryCache(iso2, limit, offset);
    if (cached.length && !this.isCacheStale(cached)) {
      return cached;
    }

    try {
      await this.refreshCountryConflictUpdates(iso2);
    } catch (error) {
      if (cached.length) return cached;
      throw error;
    }

    return await this.listCountryCache(iso2, limit, offset);
  }

  async getGlobalConflictUpdates(limit: number, offset: number): Promise<ExternalNewsItemRow[]> {
    const cached = await this.listGlobalCache(limit, offset);
    if (cached.length && !this.isCacheStale(cached)) {
      return cached;
    }

    try {
      await this.refreshGlobalConflictUpdates();
    } catch (error) {
      if (cached.length) return cached;
      throw error;
    }

    return await this.listGlobalCache(limit, offset);
  }

  async getExternalNewsComments(
    newsItemId: string,
    limit: number,
    before?: string | null
  ): Promise<ExternalNewsCommentRow[]> {
    const safeLimit = Math.max(1, Math.min(100, Number(limit || 25)));
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
        and c.deleted_at is null
        ${beforeClause}
      order by c.created_at asc, c.id asc
      limit $2
      `,
      params
    );

    return rows as ExternalNewsCommentRow[];
  }

  async addExternalNewsComment(
    userId: string,
    newsItemId: string,
    body: string,
    parentId?: string | null
  ): Promise<ExternalNewsCommentRow> {
    const trimmed = String(body ?? '').trim();
    if (!trimmed) throw new Error('Comment is required.');

    await this.ensureNewsItemExists(newsItemId);
    const parentRef = String(parentId ?? '').trim() || null;

    if (parentRef) {
      const { rows } = await pool.query(
        `
        select id, news_item_id
        from public.external_news_comments
        where id = $1
        limit 1
        `,
        [parentRef]
      );
      const parent = rows[0];
      if (!parent?.id) throw new Error('PARENT_COMMENT_NOT_FOUND');
      if (parent.news_item_id !== newsItemId) throw new Error('PARENT_COMMENT_MISMATCH');
    }

    const { rows } = await pool.query(
      `
      insert into public.external_news_comments (news_item_id, parent_id, author_id, body)
      values ($1, $2, $3, $4)
      returning id
      `,
      [newsItemId, parentRef, userId, trimmed]
    );

    const commentId = rows[0]?.id;
    if (!commentId) throw new Error('Failed to add comment.');

    const comment = await this.commentById(commentId);
    if (!comment) throw new Error('Comment not found.');
    return comment;
  }

  async shareExternalNewsToCountry(
    userId: string,
    newsItemId: string,
    body?: string | null,
    visibility = 'country'
  ) {
    const newsItem = await this.getNewsItemById(newsItemId);
    if (!newsItem) throw new Error('News item not found.');

    const { rows } = await pool.query(
      `
      select country_name, country_code, city_name
      from public.profiles
      where user_id = $1
      limit 1
      `,
      [userId]
    );

    const profile = rows[0];
    if (!profile?.country_name || !profile?.country_code) {
      throw new Error('Profile country is required before sharing.');
    }

    const baseBody = String(body ?? '').trim();
    const titleLine = newsItem.title.trim();
    const sourceLine = newsItem.source_name ? `Source: ${newsItem.source_name}` : 'Source: ReliefWeb';
    const lines = [
      baseBody,
      titleLine,
      sourceLine,
      newsItem.url,
    ].filter(Boolean);

    return await this.posts.createPost(userId, {
      body: lines.join('\n'),
      title: null,
      country_name: String(profile.country_name),
      country_code: String(profile.country_code),
      city_name: profile.city_name ?? null,
      visibility,
      media_type: 'none',
      media_url: null,
      thumb_url: null,
      external_ref_type: 'news',
      external_ref_id: newsItem.id,
      link_url: newsItem.url,
      link_title: newsItem.title,
      link_source_name: newsItem.source_name,
      link_published_at: newsItem.published_at,
      link_image_url: newsItem.image_url,
      link_snippet: newsItem.snippet,
    });
  }

  async refreshCountryConflictUpdates(countryCode: string): Promise<ExternalNewsItemRow[]> {
    const iso2 = this.normalizeCountryCode(countryCode);
    if (!iso2) throw new Error('country_code is required');

    const countryName = await this.countryNameForIso2(iso2);
    const fetched = await this.reliefweb.fetchLatestReports({
      limit: Number(process.env.RELIEFWEB_COUNTRY_FETCH_LIMIT ?? 120),
      offset: 0,
    });

    const filtered = fetched.filter((row) => this.matchesCountry(row, iso2, countryName)).slice(0, 24);
    await this.upsertReports(filtered);

    return await this.listCountryCache(iso2, 10, 0);
  }

  async refreshGlobalConflictUpdates(): Promise<ExternalNewsItemRow[]> {
    const fetched = await this.reliefweb.fetchLatestReports({
      limit: Number(process.env.RELIEFWEB_GLOBAL_FETCH_LIMIT ?? 60),
      offset: 0,
    });
    await this.upsertReports(fetched);
    return await this.listGlobalCache(10, 0);
  }

  private async listCountryCache(
    countryCode: string,
    limit: number,
    offset: number
  ): Promise<ExternalNewsItemRow[]> {
    const safeLimit = Math.max(1, Math.min(50, Number(limit || 10)));
    const safeOffset = Math.max(0, Number(offset || 0));
    const { rows } = await pool.query(
      `
      select
        n.id,
        n.provider,
        n.provider_item_id,
        n.title,
        n.url,
        n.source_name,
        n.published_at,
        n.country_codes,
        n.country_names,
        n.disaster_types,
        n.theme_names,
        n.format,
        n.language,
        n.snippet,
        n.image_url,
        n.last_seen_at,
        (
          select count(*)::int
          from public.external_news_comments c
          where c.news_item_id = n.id and c.deleted_at is null
        ) as comment_count,
        (
          select count(*)::int
          from public.posts p
          where p.external_ref_type = 'news' and p.external_ref_id = n.id
        ) as shared_post_count
      from public.external_news_items n
      where $1 = any(n.country_codes)
      order by coalesce(n.published_at, n.updated_at, n.created_at) desc, n.id desc
      limit $2
      offset $3
      `,
      [countryCode, safeLimit, safeOffset]
    );
    return rows as ExternalNewsItemRow[];
  }

  private async listGlobalCache(limit: number, offset: number): Promise<ExternalNewsItemRow[]> {
    const safeLimit = Math.max(1, Math.min(50, Number(limit || 10)));
    const safeOffset = Math.max(0, Number(offset || 0));
    const { rows } = await pool.query(
      `
      select
        n.id,
        n.provider,
        n.provider_item_id,
        n.title,
        n.url,
        n.source_name,
        n.published_at,
        n.country_codes,
        n.country_names,
        n.disaster_types,
        n.theme_names,
        n.format,
        n.language,
        n.snippet,
        n.image_url,
        n.last_seen_at,
        (
          select count(*)::int
          from public.external_news_comments c
          where c.news_item_id = n.id and c.deleted_at is null
        ) as comment_count,
        (
          select count(*)::int
          from public.posts p
          where p.external_ref_type = 'news' and p.external_ref_id = n.id
        ) as shared_post_count
      from public.external_news_items n
      order by coalesce(n.published_at, n.updated_at, n.created_at) desc, n.id desc
      limit $1
      offset $2
      `,
      [safeLimit, safeOffset]
    );
    return rows as ExternalNewsItemRow[];
  }

  private isCacheStale(rows: ExternalNewsItemRow[]): boolean {
    const latest = rows[0]?.last_seen_at ? new Date(rows[0].last_seen_at).getTime() : 0;
    if (!latest) return true;
    return Date.now() - latest > CACHE_TTL_MS;
  }

  private async upsertReports(reports: ReliefWebNormalizedReport[]): Promise<void> {
    if (!reports.length) return;
    const client = await pool.connect();
    try {
      await client.query('begin');
      for (const report of reports) {
        await client.query(
          `
          insert into public.external_news_items (
            provider,
            provider_item_id,
            title,
            url,
            source_name,
            published_at,
            country_codes,
            country_names,
            disaster_types,
            theme_names,
            format,
            language,
            snippet,
            image_url,
            raw,
            last_seen_at,
            updated_at
          )
          values (
            'reliefweb',
            $1,
            $2,
            $3,
            $4,
            $5,
            $6,
            $7,
            $8,
            $9,
            $10,
            $11,
            $12,
            $13,
            $14::jsonb,
            now(),
            now()
          )
          on conflict (provider, provider_item_id)
          do update set
            title = excluded.title,
            url = excluded.url,
            source_name = excluded.source_name,
            published_at = excluded.published_at,
            country_codes = excluded.country_codes,
            country_names = excluded.country_names,
            disaster_types = excluded.disaster_types,
            theme_names = excluded.theme_names,
            format = excluded.format,
            language = excluded.language,
            snippet = excluded.snippet,
            image_url = excluded.image_url,
            raw = excluded.raw,
            last_seen_at = now(),
            updated_at = now()
          `,
          [
            report.provider_item_id,
            report.title,
            report.url,
            report.source_name,
            report.published_at,
            report.country_codes,
            report.country_names,
            report.disaster_types,
            report.theme_names,
            report.format,
            report.language,
            report.snippet,
            report.image_url,
            JSON.stringify(report.raw ?? {}),
          ]
        );
      }
      await client.query('commit');
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }
  }

  private async getNewsItemById(newsItemId: string) {
    const { rows } = await pool.query(
      `
      select
        id,
        title,
        url,
        source_name,
        published_at,
        snippet,
        image_url
      from public.external_news_items
      where id = $1
      limit 1
      `,
      [newsItemId]
    );
    return rows[0] ?? null;
  }

  private async ensureNewsItemExists(newsItemId: string): Promise<void> {
    const item = await this.getNewsItemById(newsItemId);
    if (!item?.id) throw new Error('News item not found.');
  }

  private async commentById(commentId: string): Promise<ExternalNewsCommentRow | null> {
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
      where c.id = $1
      limit 1
      `,
      [commentId]
    );
    return (rows[0] as ExternalNewsCommentRow) ?? null;
  }

  private async countryNameForIso2(iso2: string): Promise<string | null> {
    const map = await this.loadCountryNameMap();
    return map.get(iso2) ?? null;
  }

  private matchesCountry(
    report: ReliefWebNormalizedReport,
    iso2: string,
    countryName: string | null
  ): boolean {
    const byCode = report.country_codes.some((value) => value === iso2);
    if (byCode) return true;
    if (!countryName) return false;
    const target = countryName.trim().toLowerCase();
    return report.country_names.some((value) => value.trim().toLowerCase() === target);
  }

  private normalizeCountryCode(value: string | null | undefined): string | null {
    const raw = String(value ?? '').trim().toUpperCase();
    return /^[A-Z]{2}$/.test(raw) ? raw : null;
  }

  private async loadCountryNameMap(): Promise<Map<string, string>> {
    if (!countryNameMapPromise) {
      countryNameMapPromise = (async () => {
        const map = new Map<string, string>();
        const raw = await readFile(COUNTRIES_GEOJSON, 'utf8');
        const json = JSON.parse(raw);
        const features = Array.isArray(json?.features) ? json.features : [];
        for (const feature of features) {
          const props = feature?.properties ?? {};
          const iso2 = String(props?.ISO_A2 ?? props?.ISO_A2_EH ?? '').trim().toUpperCase();
          const name = String(props?.NAME ?? props?.ADMIN ?? '').trim();
          if (/^[A-Z]{2}$/.test(iso2) && name) {
            map.set(iso2, name);
          }
        }
        return map;
      })();
    }
    return await countryNameMapPromise;
  }
}
