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

export type StudioEarnChecklistItem = {
  id: string;
  label: string;
  met: boolean;
  detail: string;
};

export type StudioEarnPayoutRow = {
  id: string;
  amountUsd: number;
  currency: 'USD';
  state: string;
  createdAt: string;
  paidAt: string | null;
};

export type StudioEarnLedgerRow = {
  id: string;
  entryType: string;
  amountUsd: number;
  currency: 'USD';
  memo: string;
  createdAt: string;
};

export type StudioEarn = {
  range: StudioRange;
  rangeDays: number;
  channelId: string;
  payoutsLive: boolean;
  status:
    | 'preview'
    | 'on_track'
    | 'ready_when_live'
    | 'pending_review'
    | 'approved'
    | 'live'
    | 'hold';
  statusLabel: string;
  statusDetail: string;
  checklist: StudioEarnChecklistItem[];
  monetization: {
    state: string;
    canApply: boolean;
    appliedAt: string | null;
    minPayoutUsd: number;
  };
  balance: {
    currency: 'USD';
    availableUsd: number;
    pendingUsd: number;
    lifetimeEarnedUsd: number;
    lifetimePaidUsd: number;
  };
  payouts: StudioEarnPayoutRow[];
  ledger: StudioEarnLedgerRow[];
  metrics: {
    views: number;
    impressions: number;
    watchMs: number;
    watchHours: number;
    videos: number;
    promotedVideos: number;
    subscribers: number;
  };
  estimate: {
    currency: 'USD';
    estimatedRevenueUsd: number;
    rpmUsd: number;
    basis: 'impressions' | 'views';
    label: string;
    disclaimer: string;
  };
  promotion: {
    disclosedCount: number;
    note: string;
  };
  ads: {
    path: string;
    label: string;
    detail: string;
  };
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

  async earn(range: StudioRange = '28d'): Promise<StudioEarn> {
    const json = await this.get<{ ok: boolean; earn: StudioEarn }>('/v1/studio/earn', { range });
    return json.earn;
  }

  async applyEarn(): Promise<StudioEarn['monetization']> {
    const json = await this.post<{ ok: boolean; monetization: StudioEarn['monetization'] }>(
      '/v1/studio/earn/apply'
    );
    return json.monetization;
  }

  async requestPayout(opts?: {
    amountUsd?: number;
    idempotencyKey?: string;
  }): Promise<StudioEarnPayoutRow> {
    const json = await this.post<{ ok: boolean; payout: StudioEarnPayoutRow }>(
      '/v1/studio/earn/payout',
      {
        ...(opts?.amountUsd != null ? { amountUsd: opts.amountUsd } : {}),
        ...(opts?.idempotencyKey ? { idempotencyKey: opts.idempotencyKey } : {}),
      }
    );
    return json.payout;
  }

  formatMoneyUsd(n: number | null | undefined): string {
    const v = Number(n) || 0;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      maximumFractionDigits: 2,
    }).format(v);
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
    return this.request<T>('GET', path, undefined, query);
  }

  private async post<T>(path: string, body: Record<string, unknown> = {}): Promise<T> {
    return this.request<T>('POST', path, body);
  }

  private async request<T>(
    method: 'GET' | 'POST',
    path: string,
    body?: Record<string, unknown>,
    query: Record<string, string> = {}
  ): Promise<T> {
    const base = (environment.apiBaseUrl || 'https://api.matterya.com').replace(/\/$/, '');
    const url = new URL(`${base}${path}`);
    for (const [k, v] of Object.entries(query)) {
      if (v != null && v !== '') url.searchParams.set(k, v);
    }
    const headers: Record<string, string> = { accept: 'application/json' };
    const token = await this.auth.getAccessToken();
    if (!token) throw new Error('Sign in to open Studio.');
    headers['authorization'] = `Bearer ${token}`;
    if (method === 'POST') headers['content-type'] = 'application/json';

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 20000);
    try {
      const res = await fetch(url.toString(), {
        method,
        headers,
        signal: controller.signal,
        ...(method === 'POST' ? { body: JSON.stringify(body ?? {}) } : {}),
      });
      const json = await res.json().catch(() => ({}));
      if (!res.ok) {
        const err = String(json?.error || json?.reason || `Request failed (${res.status})`);
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
