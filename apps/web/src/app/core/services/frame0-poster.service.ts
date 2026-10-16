import { Injectable } from '@angular/core';
import { environment } from '../../../envirnoments/envirnoment';
import { AuthService } from './auth.service';

/**
 * Web port of iOS Frame0PosterResolver / Frame0PosterCache.
 * Prefetches signed Frame 0 webp URLs via GET /v1/poster/:id and POST /v1/poster/batch.
 * Feed scroll hot path: thumbs + Frame0 only — never AV.
 */
@Injectable({ providedIn: 'root' })
export class Frame0PosterService {
  private cache = new Map<string, { url: string; cachedAt: number }>();
  private inflight = new Map<string, Promise<string | null>>();
  private readonly ttlMs = 6 * 3600 * 1000;

  constructor(private auth: AuthService) {}

  /** Sync cache read for first paint. */
  url(postId: string): string | null {
    const key = String(postId || '').trim();
    if (!key) return null;
    const hit = this.cache.get(key);
    if (!hit) return null;
    if (Date.now() - hit.cachedAt >= this.ttlMs) {
      this.cache.delete(key);
      return null;
    }
    return hit.url;
  }

  store(postId: string, url: string): void {
    const key = String(postId || '').trim();
    const u = String(url || '').trim();
    if (!key || !u) return;
    this.cache.set(key, { url: u, cachedAt: Date.now() });
    if (this.cache.size > 4000) {
      const first = this.cache.keys().next().value;
      if (first) this.cache.delete(first);
    }
  }

  storeBatch(map: Record<string, string>): void {
    for (const [id, url] of Object.entries(map || {})) {
      this.store(id, url);
    }
  }

  async resolve(postId: string): Promise<string | null> {
    const key = String(postId || '').trim();
    if (!key) return null;
    const cached = this.url(key);
    if (cached) return cached;

    const existing = this.inflight.get(key);
    if (existing) return existing;

    const task = this.fetchOne(key);
    this.inflight.set(key, task);
    try {
      return await task;
    } finally {
      this.inflight.delete(key);
    }
  }

  /** Prefetch Frame0 for a window of posts (chunks of 24). Fire-and-forget safe. */
  async prefetch(postIds: string[]): Promise<void> {
    const ids = [...new Set(postIds.map((id) => String(id || '').trim()).filter(Boolean))].filter(
      (id) => !this.url(id)
    );
    if (!ids.length) return;

    const base = (environment.apiBaseUrl || '').replace(/\/$/, '');
    if (!base) return;

    for (let i = 0; i < ids.length; i += 24) {
      const chunk = ids.slice(i, i + 24);
      try {
        const headers: Record<string, string> = {
          accept: 'application/json',
          'content-type': 'application/json',
          ...(await this.authHeaders()),
        };
        const res = await fetch(`${base}/v1/poster/batch`, {
          method: 'POST',
          headers,
          body: JSON.stringify({ postIds: chunk }),
          signal: AbortSignal.timeout(8000),
        });
        if (!res.ok) {
          // Batch may reject non-uuid spark ids — fall back to singles for a few.
          await Promise.all(chunk.slice(0, 4).map((id) => this.resolve(id).catch(() => null)));
          continue;
        }
        const body = (await res.json()) as any;
        const posters = (body?.posters || {}) as Record<string, string>;
        this.storeBatch(posters);
        // Warm browser image cache for strip/feed first paint.
        for (const url of Object.values(posters)) {
          if (url) {
            const img = new Image();
            img.decoding = 'async';
            img.src = url;
          }
        }
      } catch {
        // best-effort
      }
    }
  }

  private async fetchOne(postId: string): Promise<string | null> {
    const base = (environment.apiBaseUrl || '').replace(/\/$/, '');
    if (!base) return null;
    try {
      const res = await fetch(`${base}/v1/poster/${encodeURIComponent(postId)}`, {
        headers: { accept: 'application/json', ...(await this.authHeaders()) },
        signal: AbortSignal.timeout(5000),
      });
      if (!res.ok) return null;
      const body = (await res.json()) as any;
      const url = String(body?.url || '').trim();
      if (!url) return null;
      this.store(postId, url);
      return url;
    } catch {
      return null;
    }
  }

  private async authHeaders(): Promise<Record<string, string>> {
    const headers: Record<string, string> = {};
    try {
      const token = await this.auth.getAccessToken();
      if (token) headers['authorization'] = `Bearer ${token}`;
    } catch {
      // anonymous ok
    }
    return headers;
  }
}
