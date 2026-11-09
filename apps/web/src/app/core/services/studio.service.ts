import { Injectable } from '@angular/core';
import { environment } from '../../../envirnoments/envirnoment';
import { AuthService } from './auth.service';

export type StudioRange = '7d' | '28d' | '90d';

export type StudioChannel = {
  id: string;
  owner_user_id: string;
  name: string;
  handle: string | null;
  about: string | null;
  avatar_url: string | null;
  cover_url: string | null;
  video_count: number;
};

export type StudioVideoRow = {
  id: string;
  title: string | null;
  thumbUrl: string | null;
  mediaType: string | null;
  createdAt: string | null;
  hubSlug: string | null;
  views: number;
  watchMs: number;
  impressions: number;
  clicks: number;
  ctr: number | null;
  completes: number;
  qualityScore: number | null;
};

export type StudioDashboard = {
  range: StudioRange;
  rangeDays: number;
  channelId: string;
  kpis: {
    views: number;
    watchMs: number;
    impressions: number;
    clicks: number;
    ctr: number | null;
    avgViewDurationMs: number | null;
    avgViewPercentage: number | null;
    completes: number;
    skips: number;
    likes: number;
    comments: number;
    subscribers: number;
    videos: number;
  };
  daily: { day: string; views: number; watchMs: number; impressions: number }[];
  topVideos: StudioVideoRow[];
  note: string;
};

export type StudioVideoAnalytics = {
  range: StudioRange;
  video: StudioVideoRow;
  funnel: {
    impressions: number;
    clicks: number;
    ctr: number | null;
    views: number;
    completes: number;
    skips: number;
    likes: number;
    comments: number;
    watchMs: number;
  };
  sources: { source: string; views: number }[];
  retention: { bucket: number; reached: number }[];
  daily: { day: string; views: number; watchMs: number; impressions: number }[];
  note: string;
};

@Injectable({ providedIn: 'root' })
export class StudioService {
  constructor(private auth: AuthService) {}

  async channel(): Promise<{ hasChannel: boolean; channel: StudioChannel | null }> {
    const json = await this.get<{ ok: boolean; hasChannel: boolean; channel: StudioChannel | null }>(
      '/v1/studio/channel'
    );
    return { hasChannel: !!json.hasChannel, channel: json.channel ?? null };
  }

  async dashboard(range: StudioRange = '28d'): Promise<StudioDashboard> {
    const json = await this.get<{ ok: boolean; dashboard: StudioDashboard }>(
      '/v1/studio/dashboard',
      { range }
    );
    return json.dashboard;
  }

  async videos(
    range: StudioRange = '28d',
    opts?: { sort?: string; cursor?: string | null; limit?: number }
  ): Promise<{ videos: StudioVideoRow[]; nextCursor: string | null; range: StudioRange }> {
    const json = await this.get<{
      ok: boolean;
      videos: StudioVideoRow[];
      nextCursor: string | null;
      range: StudioRange;
    }>('/v1/studio/videos', {
      range,
      sort: opts?.sort || 'views',
      ...(opts?.cursor ? { cursor: opts.cursor } : {}),
      ...(opts?.limit != null ? { limit: String(opts.limit) } : {}),
    });
    return {
      videos: json.videos || [],
      nextCursor: json.nextCursor ?? null,
      range: json.range,
    };
  }

  async videoAnalytics(id: string, range: StudioRange = '28d'): Promise<StudioVideoAnalytics> {
    const json = await this.get<{ ok: boolean; analytics: StudioVideoAnalytics }>(
      `/v1/studio/videos/${encodeURIComponent(id)}/analytics`,
      { range }
    );
    return json.analytics;
  }

  formatWatch(ms: number): string {
    const s = Math.max(0, Math.round(ms / 1000));
    if (s < 60) return `${s}s`;
    const m = Math.floor(s / 60);
    const rem = s % 60;
    if (m < 60) return rem ? `${m}m ${rem}s` : `${m}m`;
    const h = Math.floor(m / 60);
    const rm = m % 60;
    return rm ? `${h}h ${rm}m` : `${h}h`;
  }

  formatCtr(ctr: number | null | undefined): string {
    if (ctr == null || !Number.isFinite(ctr)) return '—';
    return `${(ctr * 100).toFixed(1)}%`;
  }

  formatCount(n: number | null | undefined): string {
    const v = Number(n) || 0;
    if (v >= 1_000_000) return `${(v / 1_000_000).toFixed(1)}M`;
    if (v >= 1_000) return `${(v / 1_000).toFixed(1)}K`;
    return String(v);
  }

  private async get<T>(path: string, query: Record<string, string> = {}): Promise<T> {
    const base = (environment.apiBaseUrl || 'https://api.matterya.com').replace(/\/$/, '');
    const url = new URL(`${base}${path}`);
    for (const [k, v] of Object.entries(query)) {
      if (v != null && v !== '') url.searchParams.set(k, v);
    }
    const headers: Record<string, string> = { accept: 'application/json' };
    const token = await this.auth.getAccessToken();
    if (!token) throw new Error('Sign in to open Studio.');
    headers['authorization'] = `Bearer ${token}`;

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 20000);
    try {
      const res = await fetch(url.toString(), { headers, signal: controller.signal });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        const err = String(json?.error || `Request failed (${res.status})`);
        if (res.status === 404 && err === 'channel_required') {
          throw new Error('channel_required');
        }
        throw new Error(err);
      }
      return json as T;
    } catch (e: any) {
      if (e?.name === 'AbortError') throw new Error('Studio request timed out.');
      throw e;
    } finally {
      clearTimeout(timer);
    }
  }
}
