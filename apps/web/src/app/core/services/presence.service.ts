import { Injectable } from '@angular/core';
import { Subscription } from 'rxjs';
import { supabase } from '../../supabase/supabase.client';
import type { CountryModel } from '../../data/countries.service';
import type { ConnectionPoint } from '../../globe/globe.service';
import { FakeDataService } from './fake-data.service';
import { PresenceOverridesService, type PresenceOverridesMap } from './presence-overrides.service';
import type { Profile } from './profile.service';

type ProfileRow = {
  user_id: string;
  country_code: string | null;
  country_name: string | null;
  city_name: string | null;
};

export type PresenceSnapshot = {
  points: ConnectionPoint[];
  onlineIds: Array<string>;
  totalUsers: number;
  onlineUsers: number;
  byCountry: Record<string, { total: number; online: number }>;
};

type PresenceMeta = {
  user_id?: string;
  country_code?: string | null;
  country_name?: string | null;
  city_name?: string | null;
  ts?: number; // epoch ms
};

function normalizeLng180(lng: number): number {
  if (!Number.isFinite(lng)) return 0;
  let x = lng;
  while (x > 180) x -= 360;
  while (x < -180) x += 360;
  return x;
}

function clamp(v: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, v));
}

function mulberry32(seed: number) {
  let a = seed >>> 0;
  return () => {
    a |= 0;
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

@Injectable({ providedIn: 'root' })
export class PresenceService {
  constructor(
    private fakeData: FakeDataService,
    private overridesService: PresenceOverridesService
  ) {}

  private countries: CountryModel[] = [];
  private channel: any = null;

  private profilesById = new Map<string, ProfileRow>();

  private fakeProfiles: Profile[] = [];
  private fakeOnlineIds: string[] = [];
  private fakeOnlinePoints: ConnectionPoint[] = [];
  private fakeOnlineByCountry: Record<string, number> = {};
  private overridesByCountry: PresenceOverridesMap = {};
  private overridesSub: Subscription | null = null;

  // ✅ online truth comes from realtime presence state
  private onlineMetaById = new Map<string, PresenceMeta>();

  private onUpdateCb: ((snap: PresenceSnapshot) => void) | null = null;
  private onHeartbeatCb: ((txt: string) => void) | null = null;

  private meId: string | null = null;

  private currentCountryCode: string | null = null;
  private currentCountryName: string | null = null;
  private currentCityName: string | null = null;

  // UI updates
  private renderTimer: any = null;
  private readonly RENDER_MS = 800;

  // totals refresh (new registrations)
  private refreshProfilesTimer: any = null;
  private readonly PROFILES_REFRESH_MS = 120_000;

  // fake online refresh
  private fakeOnlineTimer: any = null;
  private readonly FAKE_ONLINE_REFRESH_MS = 30_000;
  private readonly FAKE_ONLINE_MIN = 0.4;
  private readonly FAKE_ONLINE_MAX = 0.65;
  private readonly FAKE_ONLINE_WAVE_SECONDS = 180;
  private readonly MAX_FAKE_POINTS = 3500;
  private readonly MAX_TOTAL_POINTS = 4200;

  private baseTotalsByCountry: Record<string, number> = {};
  private baseTotalUsers = 0;

  // Dot styling for all presence points.
  private readonly DOT_COLOR = 'rgba(0,255,209,0.92)';

  async start(opts: {
    countries: CountryModel[];
    meCountryCode?: string | null;
    meCountryName?: string | null;
    meCityName?: string | null;
    loadProfiles?: boolean;
    onUpdate: (snap: PresenceSnapshot) => void;
    onHeartbeat?: (txt: string) => void;
  }): Promise<void> {
    this.stop();

    this.countries = opts.countries || [];
    this.onUpdateCb = opts.onUpdate;
    this.onHeartbeatCb = opts.onHeartbeat ?? null;

    const { data: authData } = await supabase.auth.getUser();
    this.meId = authData.user?.id ?? null;

    this.currentCountryCode = opts.meCountryCode ?? null;
    this.currentCountryName = opts.meCountryName ?? null;
    this.currentCityName = opts.meCityName ?? null;

    // totals
    await this.fakeData.ensureInitialized(this.countries);
    if (opts.loadProfiles !== false) {
      await this.fetchAllProfiles();
    } else {
      this.profilesById.clear();
      await this.injectFakeProfiles();
    }

    // online (accurate)
    await this.startRealtimePresence();

    this.startFakeOnline();
    this.startOverridesWatcher();

    // periodic UI refresh
    this.renderTimer = setInterval(() => this.emit(), this.RENDER_MS);

    // periodic totals refresh
    this.refreshProfilesTimer = setInterval(() => {
      this.fetchAllProfiles().then(() => this.emit()).catch(() => {});
    }, this.PROFILES_REFRESH_MS);

    this.emit();
  }

  stop(): void {
    if (this.renderTimer) clearInterval(this.renderTimer);
    this.renderTimer = null;

    if (this.refreshProfilesTimer) clearInterval(this.refreshProfilesTimer);
    this.refreshProfilesTimer = null;

    if (this.fakeOnlineTimer) clearInterval(this.fakeOnlineTimer);
    this.fakeOnlineTimer = null;

    try {
      if (this.channel) supabase.removeChannel(this.channel);
    } catch {}
    this.channel = null;

    this.onUpdateCb = null;
    this.onHeartbeatCb = null;

    this.onlineMetaById.clear();
    this.fakeOnlineIds = [];
    this.fakeOnlinePoints = [];
    this.fakeOnlineByCountry = {};
    this.overridesByCountry = {};
    if (this.overridesSub) {
      this.overridesSub.unsubscribe();
      this.overridesSub = null;
    }
  }

  async setMyLocation(countryCode: string | null, countryName: string | null, cityName?: string | null) {
    this.currentCountryCode = countryCode ?? null;
    this.currentCountryName = countryName ?? null;
    this.currentCityName = cityName ?? null;

    await this.trackMe();
    this.emit();
  }

  // -------------------------
  // Totals
  // -------------------------
  private async fetchAllProfiles(): Promise<void> {
    let rows: ProfileRow[] = [];
    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('user_id,country_code,country_name,city_name');
      if (!error && data) rows = data as ProfileRow[];
    } catch {}

    this.profilesById.clear();
    for (const row of rows) {
      if (!row?.user_id) continue;
      this.profilesById.set(row.user_id, row);
    }

    await this.injectFakeProfiles();
  }

  private async injectFakeProfiles(): Promise<void> {
    this.fakeProfiles = await this.fakeData.getProfiles(this.countries);
    for (const prof of this.fakeProfiles) {
      if (!prof?.user_id) continue;
      this.profilesById.set(prof.user_id, {
        user_id: prof.user_id,
        country_code: prof.country_code ?? null,
        country_name: prof.country_name ?? null,
        city_name: prof.city_name ?? null,
      });
    }
    this.rebuildTotalsCache();
  }

  private rebuildTotalsCache(): void {
    const totals: Record<string, number> = {};
    for (const [, prof] of this.profilesById.entries()) {
      const cc = String(prof.country_code ?? '').trim().toUpperCase();
      if (!cc) continue;
      totals[cc] = (totals[cc] ?? 0) + 1;
    }
    this.baseTotalsByCountry = totals;
    this.baseTotalUsers = this.profilesById.size;
  }

  private startFakeOnline(): void {
    if (this.fakeOnlineTimer) return;
    void this.refreshFakeOnline();
    this.fakeOnlineTimer = setInterval(() => {
      void this.refreshFakeOnline();
    }, this.FAKE_ONLINE_REFRESH_MS);
  }

  private computeFakeOnlineRatio(): number {
    const now = Date.now();
    const phase = (now / 1000) * ((2 * Math.PI) / this.FAKE_ONLINE_WAVE_SECONDS);
    const wave = (Math.sin(phase) + 1) / 2;
    const base = this.FAKE_ONLINE_MIN + (this.FAKE_ONLINE_MAX - this.FAKE_ONLINE_MIN) * wave;
    const jitterSeed = Math.floor(now / 60000) + 77;
    const jitter = (mulberry32(jitterSeed)() - 0.5) * 0.05;
    return clamp(base + jitter, this.FAKE_ONLINE_MIN, this.FAKE_ONLINE_MAX);
  }

  private async refreshFakeOnline(): Promise<void> {
    if (!this.fakeProfiles.length) {
      await this.injectFakeProfiles();
    }
    if (!this.fakeProfiles.length) return;

    const ratio = this.computeFakeOnlineRatio();
    const seed = Math.floor(Date.now() / this.FAKE_ONLINE_REFRESH_MS) + 911;
    const rnd = mulberry32(seed);

    const onlineIds: string[] = [];
    const onlinePoints: ConnectionPoint[] = [];
    const byCountry: Record<string, number> = {};

    for (const prof of this.fakeProfiles) {
      if (rnd() > ratio) continue;
      const cc = String(prof.country_code ?? '').trim().toUpperCase();
      if (!cc) continue;
      const country = this.countryForCode(cc);
      if (!country) continue;

      onlineIds.push(prof.user_id);
      byCountry[cc] = (byCountry[cc] ?? 0) + 1;

      const pos = this.approximatePoint(country, prof.user_id, prof.city_name ?? null);
      onlinePoints.push({
        id: prof.user_id,
        lat: pos.lat,
        lng: pos.lng,
        cc,
        color: this.DOT_COLOR,
        radius: 1.4,
      });
    }

    if (!onlineIds.length) {
      const fallback = this.fakeProfiles[0];
      if (fallback?.country_code) {
        const cc = String(fallback.country_code).trim().toUpperCase();
        const country = this.countryForCode(cc);
        if (country) {
          onlineIds.push(fallback.user_id);
          byCountry[cc] = 1;
          const pos = this.approximatePoint(country, fallback.user_id, fallback.city_name ?? null);
          onlinePoints.push({
            id: fallback.user_id,
            lat: pos.lat,
            lng: pos.lng,
            cc,
            color: this.DOT_COLOR,
            radius: 1.4,
          });
        }
      }
    }

    if (onlinePoints.length > this.MAX_FAKE_POINTS) {
      const step = Math.ceil(onlinePoints.length / this.MAX_FAKE_POINTS);
      const sampled: ConnectionPoint[] = [];
      for (let i = 0; i < onlinePoints.length; i += step) {
        sampled.push(onlinePoints[i]);
      }
      this.fakeOnlinePoints = sampled;
    } else {
      this.fakeOnlinePoints = onlinePoints;
    }

    this.fakeOnlineIds = onlineIds;
    this.fakeOnlineByCountry = byCountry;
    this.emit();
  }

  // -------------------------
  // Online (Realtime Presence)
  // -------------------------
  private async startRealtimePresence(): Promise<void> {
    if (!this.meId) {
      this.onHeartbeatCb?.('presence: no user session');
      return;
    }

    this.channel = supabase.channel('worldapp-online', {
      config: { presence: { key: this.meId } },
    });

    this.channel
      .on('presence', { event: 'sync' }, () => {
        this.rebuildOnlineMapFromState();
        this.onHeartbeatCb?.('presence: sync ✓');
        this.emit();
      })
      .on('presence', { event: 'join' }, () => {
        this.rebuildOnlineMapFromState();
        this.onHeartbeatCb?.('presence: join ✓');
        this.emit();
      })
      .on('presence', { event: 'leave' }, () => {
        this.rebuildOnlineMapFromState();
        this.onHeartbeatCb?.('presence: leave ✓');
        this.emit();
      });

    const { error } = await this.channel.subscribe(async (status: any) => {
      this.onHeartbeatCb?.(`presence: ${String(status)}`);
      if (status === 'SUBSCRIBED') {
        await this.trackMe();
        this.rebuildOnlineMapFromState();
        this.emit();
      }
    });

    if (error) throw error;
  }

  private async trackMe(): Promise<void> {
    if (!this.channel || !this.meId) return;

    const myProf = this.profilesById.get(this.meId);

    const meta: PresenceMeta = {
      user_id: this.meId,
      country_code: this.currentCountryCode ?? myProf?.country_code ?? null,
      country_name: this.currentCountryName ?? myProf?.country_name ?? null,
      city_name: this.currentCityName ?? null,
      ts: Date.now(),
    };

    await this.channel.track(meta);
  }

  private rebuildOnlineMapFromState(): void {
    if (!this.channel) return;

    const state = this.channel.presenceState?.() ?? {};
    this.onlineMetaById.clear();

    for (const key of Object.keys(state)) {
      const metas: PresenceMeta[] = Array.isArray(state[key]) ? state[key] : [];
      if (!metas.length) continue;

      let best = metas[0];
      for (const m of metas) {
        if ((m?.ts ?? 0) > (best?.ts ?? 0)) best = m;
      }

      const userId = String(best.user_id ?? key);
      this.onlineMetaById.set(userId, best);
    }
  }

  // -------------------------
  // Emit snapshot
  // -------------------------
  private emit(): void {
    if (!this.onUpdateCb) return;

    const byCountry: Record<string, { total: number; online: number }> = {};
    for (const [cc, total] of Object.entries(this.baseTotalsByCountry)) {
      byCountry[cc] = { total, online: 0 };
    }

    for (const [cc, count] of Object.entries(this.fakeOnlineByCountry)) {
      byCountry[cc] ??= { total: 0, online: 0 };
      byCountry[cc].online += count;
    }

    const onlineIds = [...this.fakeOnlineIds];

    // dots for online only
    let points: ConnectionPoint[] = [...this.fakeOnlinePoints];

    for (const userId of this.onlineMetaById.keys()) {
      const meta = this.onlineMetaById.get(userId);
      const prof = this.profilesById.get(userId);

      const cc = String(meta?.country_code ?? prof?.country_code ?? '').trim().toUpperCase();
      if (!cc) continue;

      const country = this.countryForCode(cc);
      if (!country) continue;

      byCountry[cc] ??= { total: 0, online: 0 };
      byCountry[cc].online += 1;

      const cityName = meta?.city_name ?? prof?.city_name ?? null;
      const pos = this.approximatePoint(country, userId, cityName);

      points.push({
        id: userId,
        lat: pos.lat,
        lng: pos.lng,
        cc,
        color: this.DOT_COLOR,
        radius: 1.6,
      });
      onlineIds.push(userId);
    }

    let totalUsers = this.baseTotalUsers || this.profilesById.size;
    let onlineUsers = onlineIds.length;

    for (const [rawCode, override] of Object.entries(this.overridesByCountry)) {
      const cc = String(rawCode ?? '').trim().toUpperCase();
      if (!cc) continue;

      const existing = byCountry[cc] ?? { total: 0, online: 0 };
      const next = { ...existing };

      if (Number.isFinite(override?.total)) {
        totalUsers += (override.total as number) - existing.total;
        next.total = override.total as number;
      }
      if (Number.isFinite(override?.online)) {
        onlineUsers += (override.online as number) - existing.online;
        next.online = override.online as number;
      }

      if (Number.isFinite(next.total) && Number.isFinite(next.online) && next.online > next.total) {
        onlineUsers -= next.online - next.total;
        next.online = next.total;
      }

      byCountry[cc] = next;
    }

    if (points.length > this.MAX_TOTAL_POINTS) {
      const step = Math.ceil(points.length / this.MAX_TOTAL_POINTS);
      points = points.filter((_, idx) => idx % step === 0);
    }

    this.onUpdateCb({
      points,
      onlineIds,
      totalUsers,
      onlineUsers,
      byCountry,
    });
  }

  private startOverridesWatcher(): void {
    if (this.overridesSub) return;
    this.overridesByCountry = this.overridesService.getOverrides();
    this.overridesSub = this.overridesService.observe().subscribe((next) => {
      this.overridesByCountry = next || {};
      this.emit();
    });
  }

  private countryForCode(code: string): CountryModel | null {
    const cc = String(code ?? '').trim().toUpperCase();
    if (!cc) return null;
    return this.countries.find((x) => String(x.code ?? '').toUpperCase() === cc) || null;
  }

  private approximatePoint(
    country: CountryModel,
    userId: string,
    cityName: string | null
  ): { lat: number; lng: number } {
    const pool = country.pointPool || [];
    if (!pool.length) return { lat: country.center.lat, lng: normalizeLng180(country.center.lng) };

    const seed = this.hash(`${userId}|${country.code ?? country.name}|${cityName ?? ''}`);
    const idx = Math.abs(seed) % pool.length;
    const pick = pool[idx];
    return { lat: pick.lat, lng: normalizeLng180(pick.lng) };
  }

  private hash(s: string): number {
    let h = 2166136261;
    for (let i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return Math.abs(h);
  }
}
