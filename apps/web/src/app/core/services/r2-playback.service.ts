import { Injectable } from '@angular/core';
import { environment } from '../../../envirnoments/envirnoment';
import { AuthService } from './auth.service';
import type { CountryPost } from '../models/post.model';
import { resolveMediaUrl } from '../utils/media-url.util';

type CacheEntry = { url: string; mediaUrlPayload?: string | null; cachedAt: number };

/**
 * Mirrors iOS R2PlaybackResolver — refreshes expired R2 presigns via
 * GET /v1/playback/:id and POST /v1/playback/batch.
 */
@Injectable({ providedIn: 'root' })
export class R2PlaybackService {
  private cache = new Map<string, CacheEntry>();
  private inflight = new Map<string, Promise<string | null>>();
  private readonly cacheTTL = 20 * 3600 * 1000;

  constructor(private auth: AuthService) {}

  async playURL(postID: string, fallback?: string | null): Promise<string | null> {
    const key = String(postID || '').trim();
    if (!key) return fallback || null;

    const hit = this.cache.get(key);
    if (hit && Date.now() - hit.cachedAt < this.cacheTTL) return hit.url;

    const existing = this.inflight.get(key);
    if (existing) {
      const resolved = await existing;
      return resolved || fallback || null;
    }

    const task = this.fetchAndCache(key, fallback || null);
    this.inflight.set(key, task);
    try {
      return (await task) || fallback || null;
    } finally {
      this.inflight.delete(key);
    }
  }

  /** Freshen playable URLs onto posts (thin /v1 cards often ship expired R2 presigns). */
  async freshenPosts(posts: CountryPost[], max = 12): Promise<CountryPost[]> {
    const targets = posts.filter((p) => p?.id && this.needsFreshen(p)).slice(0, max);
    if (!targets.length) return posts;

    // Prefer parallel single GET /v1/playback/:id (works anonymous).
    // Batch requires auth and returns 401 for logged-out web visitors.
    const settled = await Promise.all(
      targets.map(async (p) => {
        const url = await this.playURL(p.id, resolveMediaUrl(p.media_url || ''));
        return url ? ([p.id, url] as const) : null;
      })
    );
    const byId = new Map<string, string>();
    for (const row of settled) {
      if (row) byId.set(row[0], row[1]);
    }
    return posts.map((p) => {
      const fresh = byId.get(p.id);
      if (!fresh) return p;
      // Preserve spark identity — plain URL alone would break PostsService.isSpark().
      const keepSpark =
        this.looksLikeSparkPayload(p.media_url) ||
        ['reel', 'spark'].includes(String(p.media_type || '').toLowerCase());
      if (keepSpark) {
        return {
          ...p,
          media_type: p.media_type === 'spark' ? 'spark' : 'reel',
          media_url: JSON.stringify({
            urls: [fresh],
            types: ['video'],
            reel: true,
            kind: 'spark',
            signed_at: new Date().toISOString(),
          }),
        };
      }
      return { ...p, media_url: fresh };
    });
  }

  private looksLikeSparkPayload(mediaUrl: string | null | undefined): boolean {
    const raw = String(mediaUrl || '').trim();
    if (!raw.startsWith('{') && !raw.startsWith('[')) return false;
    try {
      const parsed = JSON.parse(raw) as any;
      return (
        parsed?.kind === 'spark' ||
        parsed?.source === 'r2_spark_share' ||
        parsed?.reel === true ||
        parsed?.spark === true
      );
    } catch {
      return false;
    }
  }

  invalidate(postID: string): void {
    const key = String(postID || '').trim();
    this.cache.delete(key);
  }

  /** Prefer cached/fresh URL for a spark card; falls back to resolveMediaUrl. */
  resolvedSrc(post: CountryPost): string {
    const hit = this.cache.get(post.id);
    if (hit && Date.now() - hit.cachedAt < this.cacheTTL) return hit.url;
    return resolveMediaUrl(post.media_url || post.thumb_url || '');
  }

  private needsFreshen(post: CountryPost): boolean {
    const raw = String(post.media_url || '').trim();
    if (!raw) return true;
    // Thin cards often ship expired Aug-era signatures — always resolve R2 JSON payloads.
    if (raw.startsWith('{') || raw.startsWith('[')) {
      try {
        const parsed = JSON.parse(raw) as any;
        if (parsed?.r2_key || parsed?.source === 'r2_spark_share' || parsed?.kind === 'spark') {
          return true;
        }
        const signedAt = Date.parse(String(parsed?.signed_at || ''));
        if (Number.isFinite(signedAt) && Date.now() - signedAt > 6 * 3600 * 1000) return true;
      } catch {
        return true;
      }
    }
    if (/X-Amz-Date=(\d{8}T\d{6}Z)/i.test(raw)) {
      const m = raw.match(/X-Amz-Date=(\d{8}T\d{6}Z)/i);
      if (m?.[1]) {
        const y = m[1].slice(0, 4);
        const mo = m[1].slice(4, 6);
        const d = m[1].slice(6, 8);
        const hh = m[1].slice(9, 11);
        const mm = m[1].slice(11, 13);
        const ss = m[1].slice(13, 15);
        const signed = Date.parse(`${y}-${mo}-${d}T${hh}:${mm}:${ss}Z`);
        if (Number.isFinite(signed) && Date.now() - signed > 6 * 3600 * 1000) return true;
      }
    }
    return false;
  }

  private async fetchAndCache(postID: string, fallback: string | null): Promise<string | null> {
    try {
      const media = await this.fetchPlaybackREST(postID);
      if (media?.url) {
        this.cache.set(postID, {
          url: media.url,
          mediaUrlPayload: media.media_url,
          cachedAt: Date.now(),
        });
        if (this.cache.size > 4000) {
          const first = this.cache.keys().next().value;
          if (first) this.cache.delete(first);
        }
        return media.url;
      }
    } catch {
      // fall through
    }
    return fallback;
  }

  private async fetchPlaybackREST(
    postID: string
  ): Promise<{ url: string; media_url?: string | null; r2_key?: string | null } | null> {
    const base = (environment.apiBaseUrl || '').replace(/\/$/, '');
    if (!base) return null;
    const headers = await this.authHeaders();
    const res = await fetch(`${base}/v1/playback/${encodeURIComponent(postID)}`, {
      headers,
      signal: AbortSignal.timeout(5000),
    });
    if (!res.ok) return null;
    const body = (await res.json()) as any;
    if (!body?.url) return null;
    return {
      url: String(body.url),
      media_url: body.media_url ?? null,
      r2_key: body.r2_key ?? null,
    };
  }

  private async batchResolve(
    postIds: string[]
  ): Promise<Map<string, { url: string; media_url?: string | null }>> {
    const out = new Map<string, { url: string; media_url?: string | null }>();
    const ids = postIds.filter(Boolean).slice(0, 12);
    if (!ids.length) return out;

    const base = (environment.apiBaseUrl || '').replace(/\/$/, '');
    if (!base) return out;

    try {
      const headers = {
        ...(await this.authHeaders()),
        'content-type': 'application/json',
      };
      const res = await fetch(`${base}/v1/playback/batch`, {
        method: 'POST',
        headers,
        body: JSON.stringify({ postIds: ids }),
        signal: AbortSignal.timeout(8000),
      });
      if (!res.ok) {
        // Fall back to single resolves for the first few.
        for (const id of ids.slice(0, 4)) {
          const one = await this.fetchAndCache(id, null);
          if (one) out.set(id, { url: one, media_url: one });
        }
        return out;
      }
      const body = (await res.json()) as any;
      const items = Array.isArray(body?.items)
        ? body.items
        : Array.isArray(body?.results)
          ? body.results
          : Array.isArray(body)
            ? body
            : [];
      for (const row of items) {
        const id = String(row?.post_id || row?.id || '').trim();
        const url = String(row?.url || '').trim();
        if (!id || !url) continue;
        const media_url = row?.media_url ? String(row.media_url) : url;
        this.cache.set(id, { url, mediaUrlPayload: media_url, cachedAt: Date.now() });
        out.set(id, { url, media_url });
      }
    } catch {
      for (const id of ids.slice(0, 4)) {
        const one = await this.fetchAndCache(id, null);
        if (one) out.set(id, { url: one, media_url: one });
      }
    }
    return out;
  }

  private async authHeaders(): Promise<Record<string, string>> {
    const headers: Record<string, string> = { accept: 'application/json' };
    try {
      const token = await this.auth.getAccessToken();
      if (token) headers['authorization'] = `Bearer ${token}`;
    } catch {
      // anonymous
    }
    return headers;
  }
}
