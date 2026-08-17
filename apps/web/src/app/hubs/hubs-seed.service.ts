import { Injectable } from '@angular/core';
import type { CountryPost, PostAuthor } from '../core/models/post.model';

export type HubVideoMeta = {
  hubSlug: string;
  attribution: string;
  license: string | null;
  licenseURL: string | null;
  itemURL: string | null;
  creator: string | null;
  durationSeconds: number | null;
};

/**
 * Internet Archive / hub_videos.jsonl loader — ports iOS HubVideoSeedService.
 *
 * Gated by ARCHIVE_CONTENT_ENABLED (mirrors iOS AppConfig.archiveContentEnabled).
 * When false, all APIs return empty and the JSONL is never fetched — code stays for re-enable.
 */
@Injectable({ providedIn: 'root' })
export class HubsSeedService {
  /**
   * Flip to `true` to restore Internet Archive seed catalog in Hubs/Sparks.
   * Keep in sync with iOS `AppConfig.archiveContentEnabled`.
   */
  static readonly ARCHIVE_CONTENT_ENABLED = false;

  static readonly sparkMaxDurationSeconds = 60;
  static readonly hubOrder = [
    'social',
    'travel',
    'nature',
    'music',
    'food',
    'sports',
    'tech',
    'fitness',
    'film',
    'culture',
    'daily',
  ] as const;

  private videos: CountryPost[] = [];
  private videosByID = new Map<string, CountryPost>();
  private videosByHub = new Map<string, CountryPost[]>();
  private sparkVideos: CountryPost[] = [];
  private attributions = new Map<string, HubVideoMeta>();
  private loadPromise: Promise<void> | null = null;

  static channelDisplayName(hubSlug: string, isSpark = false): string {
    const slug = (hubSlug || '').trim().toLowerCase();
    const titled = (() => {
      switch (slug) {
        case 'social':
          return 'Social';
        case 'travel':
          return 'Travel';
        case 'nature':
          return 'Nature';
        case 'music':
          return 'Music';
        case 'food':
          return 'Food';
        case 'sports':
          return 'Sports';
        case 'tech':
          return 'Tech';
        case 'fitness':
          return 'Fitness';
        case 'film':
          return 'Film';
        case 'culture':
          return 'Culture';
        case 'daily':
          return 'Daily';
        case '':
          return isSpark ? 'Sparks' : 'Hubs';
        default:
          return slug
            .split('_')
            .map((p) => (p ? p[0].toUpperCase() + p.slice(1) : p))
            .join(' ');
      }
    })();
    return isSpark ? `${titled} Sparks` : titled;
  }

  async allVideos(): Promise<CountryPost[]> {
    if (!HubsSeedService.ARCHIVE_CONTENT_ENABLED) return [];
    await this.loadIfNeeded();
    return this.videos.slice();
  }

  async longFormVideos(perHubCap = 8): Promise<CountryPost[]> {
    if (!HubsSeedService.ARCHIVE_CONTENT_ENABLED) return [];
    await this.loadIfNeeded();
    const long = this.videos.filter((p) => !this.isReel(p));
    if (perHubCap <= 0) return long;
    const counts = new Map<string, number>();
    const out: CountryPost[] = [];
    for (const post of long) {
      const slug = (post.external_ref_id || 'daily').toLowerCase();
      const n = counts.get(slug) ?? 0;
      if (n >= perHubCap) continue;
      counts.set(slug, n + 1);
      out.push(post);
    }
    return out;
  }

  async sparkSeedVideos(limit?: number, shuffleSeed?: number): Promise<CountryPost[]> {
    if (!HubsSeedService.ARCHIVE_CONTENT_ENABLED) return [];
    await this.loadIfNeeded();
    let result = this.sparkVideos.slice();
    if (shuffleSeed != null) {
      result = this.seededShuffle(result, shuffleSeed);
    }
    if (limit != null && limit >= 0) {
      result = result.slice(0, limit);
    }
    return result;
  }

  async videosForHub(slug: string): Promise<CountryPost[]> {
    if (!HubsSeedService.ARCHIVE_CONTENT_ENABLED) return [];
    await this.loadIfNeeded();
    return (this.videosByHub.get(slug.toLowerCase()) ?? []).slice();
  }

  async postById(id: string): Promise<CountryPost | null> {
    if (!HubsSeedService.ARCHIVE_CONTENT_ENABLED) return null;
    await this.loadIfNeeded();
    return this.videosByID.get(id) ?? null;
  }

  async metaForPost(id: string): Promise<HubVideoMeta | null> {
    await this.loadIfNeeded();
    return this.attributions.get(id) ?? null;
  }

  isHubSeedVideo(post: CountryPost | null | undefined): boolean {
    if (!post) return false;
    if (String(post.external_ref_type || '').toLowerCase() === 'hub') return true;
    return this.videosByID.has(post.id);
  }

  hubSlug(post: CountryPost | null | undefined): string | null {
    if (!post) return null;
    if (String(post.external_ref_type || '').toLowerCase() === 'hub') {
      return (post.external_ref_id || '').toLowerCase() || null;
    }
    return null;
  }

  private async loadIfNeeded(): Promise<void> {
    if (!HubsSeedService.ARCHIVE_CONTENT_ENABLED) return;
    if (this.videos.length) return;
    if (!this.loadPromise) {
      this.loadPromise = this.loadFromPublic().finally(() => {
        if (!this.videos.length) this.loadPromise = null;
      });
    }
    await this.loadPromise;
  }

  private async loadFromPublic(): Promise<void> {
    if (!HubsSeedService.ARCHIVE_CONTENT_ENABLED) return;
    const urls = [
      '/hub_video_seed/hub_videos.jsonl',
      // fallback if base href / deploy path differs
      'hub_video_seed/hub_videos.jsonl',
    ];
    for (const url of urls) {
      try {
        // Prefer revalidation over force-cache so a failed first paint doesn't stick empty.
        const res = await fetch(url, { cache: 'default' });
        if (!res.ok) continue;
        const text = await res.text();
        if (!text.trim() || text.trim().startsWith('<!')) continue;
        const batch: CountryPost[] = [];
        for (const line of text.split('\n')) {
          const trimmed = line.trim();
          if (!trimmed) continue;
          try {
            const json = JSON.parse(trimmed) as Record<string, unknown>;
            const mapped = this.mapRow(json);
            if (!mapped) continue;
            batch.push(mapped.post);
            this.attributions.set(mapped.post.id, mapped.meta);
          } catch {
            // skip bad line
          }
        }
        if (batch.length) {
          this.apply(batch);
          return;
        }
      } catch {
        // try next url
      }
    }
  }

  private apply(batch: CountryPost[]): void {
    if (!batch.length) return;
    this.videos = batch;
    this.videosByID = new Map(batch.map((p) => [p.id, p]));
    this.videosByHub = new Map();
    this.sparkVideos = [];
    for (const post of batch) {
      const slug = (post.external_ref_id || 'daily').toLowerCase();
      const list = this.videosByHub.get(slug) ?? [];
      list.push(post);
      this.videosByHub.set(slug, list);
      if (this.isReel(post)) this.sparkVideos.push(post);
    }
  }

  private mapRow(row: Record<string, unknown>): { post: CountryPost; meta: HubVideoMeta } | null {
    const id = String(row['id'] || '').trim();
    if (!id) return null;
    const hubSlug = String(row['hub_slug'] || 'daily').toLowerCase();
    const titleRaw = row['title'] != null ? String(row['title']).trim() : null;
    const bodyRaw = row['body'] != null ? String(row['body']).trim() : '';
    const media = (row['media'] as Record<string, unknown> | undefined) || undefined;
    const mediaURL = media?.['url'] != null ? String(media['url']).trim() : '';
    if (!mediaURL) return null;
    const lowerURL = mediaURL.toLowerCase();
    if (lowerURL.includes('video_ts') || lowerURL.endsWith('.vob') || lowerURL.endsWith('.iso')) {
      return null;
    }
    const thumb = media?.['thumb_url'] != null ? String(media['thumb_url']) : null;
    const creator =
      row['creator'] != null && String(row['creator']).trim()
        ? String(row['creator']).trim()
        : null;
    const license = row['license'] != null ? String(row['license']) : null;
    const licenseURL = row['license_url'] != null ? String(row['license_url']) : null;
    const itemURL = row['item_url'] != null ? String(row['item_url']) : null;
    const attribution =
      row['attribution'] != null && String(row['attribution']).trim()
        ? String(row['attribution']).trim()
        : `"${titleRaw || 'Untitled'}" by ${creator || 'Internet Archive'} — Internet Archive — ${license || ''} — ${itemURL || ''}`;

    const duration = this.parseDurationSeconds(media?.['duration']);
    const tags = Array.isArray(row['tags']) ? (row['tags'] as string[]) : [];
    const taggedSpark = tags.some((t) => {
      const s = String(t).toLowerCase();
      return s === 'spark' || s === 'short';
    });
    const isSpark =
      (duration != null && duration > 0 && duration <= HubsSeedService.sparkMaxDurationSeconds) ||
      taggedSpark;
    const mediaType = isSpark ? 'reel' : 'video';

    const authorID = isSpark ? `hub_spark_${hubSlug}` : `hub_${hubSlug}`;
    const displayName =
      creator && creator.length ? creator : isSpark ? 'Sparks' : 'Internet Archive';
    const author: PostAuthor = {
      user_id: authorID,
      display_name: displayName,
      username: isSpark ? `sparks_${hubSlug}` : hubSlug,
      avatar_url: null,
      country_name: null,
      country_code: null,
    };

    const now = new Date().toISOString();
    let bodyOut: string;
    if (isSpark) {
      const base = bodyRaw || titleRaw || 'Spark';
      bodyOut = base.includes('__spark__|') ? base : `__spark__|${base}`;
    } else {
      bodyOut = bodyRaw || attribution;
    }

    // Deterministic pseudo engagement so shelves don't look empty.
    const likeCount = this.pseudoCount(id, 12, 480);
    const viewCount = this.pseudoCount(id + 'v', 80, 24000);
    const commentCount = this.pseudoCount(id + 'c', 0, 40);

    const post: CountryPost = {
      id,
      title: titleRaw,
      body: bodyOut,
      media_type: mediaType,
      media_url: mediaURL,
      thumb_url: thumb,
      media_caption: attribution,
      visibility: 'public',
      like_count: likeCount,
      comment_count: commentCount,
      view_count: viewCount,
      liked_by_me: false,
      created_at: now,
      updated_at: now,
      author_id: authorID,
      country_name: null,
      country_code: null,
      city_name: null,
      author,
      link_url: itemURL,
      link_title: 'Internet Archive',
      external_ref_type: 'hub',
      external_ref_id: hubSlug,
    };

    const meta: HubVideoMeta = {
      hubSlug,
      attribution,
      license,
      licenseURL,
      itemURL,
      creator,
      durationSeconds: duration,
    };
    return { post, meta };
  }

  private parseDurationSeconds(raw: unknown): number | null {
    if (raw == null) return null;
    if (typeof raw === 'number' && raw > 0) return raw;
    if (typeof raw === 'string') {
      const t = raw.trim();
      if (!t) return null;
      const asNum = Number(t);
      if (Number.isFinite(asNum) && asNum > 0) return asNum;
      const parts = t.split(':');
      if (parts.length === 2) {
        const m = Number(parts[0]);
        const s = Number(parts[1]);
        if (Number.isFinite(m) && Number.isFinite(s)) return m * 60 + s;
      }
      if (parts.length === 3) {
        const h = Number(parts[0]);
        const m = Number(parts[1]);
        const s = Number(parts[2]);
        if (Number.isFinite(h) && Number.isFinite(m) && Number.isFinite(s)) {
          return h * 3600 + m * 60 + s;
        }
      }
    }
    return null;
  }

  private isReel(post: CountryPost): boolean {
    const media = String(post.media_type || '').toLowerCase();
    if (media === 'reel' || media === 'spark') return true;
    return String(post.body || '').includes('__spark__|');
  }

  private pseudoCount(seed: string, min: number, max: number): number {
    let h = 2166136261;
    for (let i = 0; i < seed.length; i++) {
      h ^= seed.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    const u = (h >>> 0) / 0xffffffff;
    return Math.floor(min + u * (max - min));
  }

  private seededShuffle<T>(arr: T[], seed: number): T[] {
    const out = arr.slice();
    let state = seed === 0 ? 0x9e3779b97f4a7c15 : seed >>> 0;
    const next = () => {
      state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
      return state / 0x100000000;
    };
    for (let i = out.length - 1; i > 0; i--) {
      const j = Math.floor(next() * (i + 1));
      [out[i], out[j]] = [out[j], out[i]];
    }
    return out;
  }
}
