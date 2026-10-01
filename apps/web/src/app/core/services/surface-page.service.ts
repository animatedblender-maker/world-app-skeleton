import { Injectable } from '@angular/core';
import { environment } from '../../../envirnoments/envirnoment';
import { AuthService } from './auth.service';
import type { CountryPost } from '../models/post.model';

export type SurfacePage = {
  items: CountryPost[];
  nextCursor: string | null;
  surface: string;
};

/**
 * Mirrors iOS SurfacePageClient — thin REST pages for Home / Sparks first paint.
 * Paths: GET /v1/feed, GET /v1/sparks
 */
@Injectable({ providedIn: 'root' })
export class SurfacePageService {
  constructor(private auth: AuthService) {}

  async fetchHomeFeed(limit = 24, cursor?: string | null): Promise<SurfacePage | null> {
    return this.get('/v1/feed', {
      limit: String(Math.min(Math.max(limit, 1), 48)),
      ...(cursor ? { cursor } : {}),
    });
  }

  async fetchSparks(
    limit = 20,
    cursor?: string | null,
    slug?: string | null
  ): Promise<SurfacePage | null> {
    const q: Record<string, string> = {
      limit: String(Math.min(Math.max(limit, 1), 40)),
    };
    if (cursor) q['cursor'] = cursor;
    if (slug) q['slug'] = slug;
    return this.get('/v1/sparks', q);
  }

  private async get(path: string, query: Record<string, string>): Promise<SurfacePage | null> {
    const base = (environment.apiBaseUrl || '').replace(/\/$/, '');
    if (!base) return null;
    const url = new URL(`${base}${path}`);
    for (const [k, v] of Object.entries(query)) {
      if (v != null && v !== '') url.searchParams.set(k, v);
    }

    const headers: Record<string, string> = { accept: 'application/json' };
    try {
      const token = await this.auth.getAccessToken();
      if (token) headers['authorization'] = `Bearer ${token}`;
    } catch {
      // anonymous thin pages are allowed
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    try {
      const res = await fetch(url.toString(), { headers, signal: controller.signal });
      if (!res.ok) return null;
      const json = (await res.json()) as any;
      if (!json?.ok || !Array.isArray(json.items)) return null;
      const items = (json.items as any[])
        .map((row) => this.mapThinCard(row))
        .filter((p): p is CountryPost => !!p);
      return {
        items,
        nextCursor: typeof json.nextCursor === 'string' ? json.nextCursor : null,
        surface: typeof json.surface === 'string' ? json.surface : path,
      };
    } catch {
      return null;
    } finally {
      clearTimeout(timer);
    }
  }

  /** Same shape as iOS SurfacePageClient.mapThinCard */
  mapThinCard(row: any): CountryPost | null {
    const id = String(row?.id || '').trim();
    if (!id) return null;
    const authorId = String(row?.author_id || 'unknown');
    const created = String(row?.created_at || new Date().toISOString());
    return {
      id,
      title: row?.title ?? null,
      body: row?.body ?? '',
      media_type: row?.media_type ?? 'none',
      media_url: row?.media_url ?? null,
      thumb_url: row?.thumb_url ?? null,
      media_caption: null,
      shared_post_id: row?.shared_post_id ?? row?.origin_sid ?? null,
      shared_post: null,
      visibility: 'public',
      like_count: Number(row?.like_count ?? 0),
      comment_count: Number(row?.comment_count ?? 0),
      view_count: Number(row?.view_count ?? 0),
      liked_by_me: !!row?.liked_by_me,
      created_at: created,
      updated_at: created,
      author_id: authorId,
      country_name: row?.country_name ?? null,
      country_code: row?.country_code ?? null,
      city_name: row?.city_name ?? null,
      author: {
        user_id: authorId,
        display_name: row?.author_name ?? null,
        username: row?.author_username ?? null,
        avatar_url: row?.author_avatar ?? null,
        country_name: row?.country_name ?? null,
        country_code: row?.country_code ?? null,
      },
      external_ref_type: row?.external_ref_type ?? null,
      external_ref_id: row?.external_ref_id ?? null,
      link_url: null,
      link_title: null,
      link_source_name: null,
      link_published_at: null,
      link_image_url: null,
      link_snippet: null,
    };
  }
}
