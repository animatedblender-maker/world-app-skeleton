import { Injectable } from '@angular/core';
import { supabase } from '../../supabase/supabase.client';
import type { CountryModel } from '../../data/countries.service';
import type { ConnectionPoint } from '../../globe/globe.service';

type ProfileRow = {
  user_id: string;
  country_code: string | null;
  country_name: string | null;
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

type Motion = {
  cc: string;
  lat: number;
  lng: number;
  vLat: number;
  vLng: number;
  lastMs: number;
};

@Injectable({ providedIn: 'root' })
export class PresenceService {
  private countries: CountryModel[] = [];

  private channel: any = null;

  private profilesById = new Map<string, ProfileRow>();
  private onlineMetaById = new Map<string, PresenceMeta>(); // from realtime presence
  private motions = new Map<string, Motion>();

  private onUpdateCb: ((snap: PresenceSnapshot) => void) | null = null;
  private onHeartbeatCb: ((txt: string) => void) | null = null;

  private meId: string | null = null;

  private currentCountryCode: string | null = null;
  private currentCountryName: string | null = null;
  private currentCityName: string | null = null;

  // Smooth motion render (not for “online correctness”, only for floating)
  private renderTimer: any = null;
  private readonly RENDER_MS = 60;

  // Refresh totals occasionally (new registrations). Not required for online correctness.
  private refreshProfilesTimer: any = null;
  private readonly PROFILES_REFRESH_MS = 120_000;

  // ✅ all dots neon green
  private readonly DOT_COLOR = 'rgba(0,255,180,0.95)';

  async start(opts: {
    countries: CountryModel[];
    meCountryCode?: string | null;
    meCountryName?: string | null;
    meCityName?: string | null;
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

    // 1) Load profiles once (for totals + fallback country mapping)
    await this.fetchAllProfiles();

    // 2) Start realtime Presence channel (instant online/offline)
    await this.startRealtimePresence();

    // 3) Smooth floating animation tick
    this.renderTimer = setInterval(() => this.emit(), this.RENDER_MS);

    // 4) Occasionally refresh totals (new signups)
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

    try {
      if (this.channel) supabase.removeChannel(this.channel);
    } catch {}
    this.channel = null;

    this.onUpdateCb = null;
    this.onHeartbeatCb = null;

    this.onlineMetaById.clear();
    this.motions.clear();
  }

  async setMyLocation(countryCode: string | null, countryName: string | null, cityName?: string | null) {
    this.currentCountryCode = countryCode ?? null;
    this.currentCountryName = countryName ?? null;
    this.currentCityName = cityName ?? null;

    // update my presence payload immediately (so country online counts update instantly)
    await this.trackMe();
    this.emit();
  }

  // -------------------------
  // Profiles (totals)
  // -------------------------

  private async fetchAllProfiles(): Promise<void> {
    const { data, error } = await supabase
      .from('profiles')
      .select('user_id,country_code,country_name');

    if (error) throw error;

    this.profilesById.clear();
    for (const row of (data || []) as ProfileRow[]) {
      if (!row?.user_id) continue;
      this.profilesById.set(row.user_id, row);
    }
  }

  // -------------------------
  // Presence (online)
  // -------------------------

  private async startRealtimePresence(): Promise<void> {
    if (!this.meId) {
      this.onHeartbeatCb?.('presence: no user session');
      return;
    }

    // Key = user_id (so each user has one presence identity)
    this.channel = supabase.channel('worldapp-online', {
      config: { presence: { key: this.meId } },
    });

    this.channel
      .on('presence', { event: 'sync' }, () => {
        this.rebuildOnlineMapFromState();
        this.onHeartbeatCb?.('presence: sync ✓');
        this.emit();
      })
      .on('presence', { event: 'join' }, (payload: any) => {
        // join payload contains newPresences
        this.rebuildOnlineMapFromState();
        this.onHeartbeatCb?.('presence: join ✓');
        this.emit();
      })
      .on('presence', { event: 'leave' }, (payload: any) => {
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

    // fall back to profile values if not provided yet
    const myProf = this.profilesById.get(this.meId);

    const meta: PresenceMeta = {
      user_id: this.meId,
      country_code: (this.currentCountryCode ?? myProf?.country_code ?? null),
      country_name: (this.currentCountryName ?? myProf?.country_name ?? null),
      city_name: (this.currentCityName ?? null),
      ts: Date.now(),
    };

    // track overwrites the meta for this key
    await this.channel.track(meta);
  }

  private rebuildOnlineMapFromState(): void {
    if (!this.channel) return;

    // state: { [key: string]: PresenceMeta[] }
    const state = this.channel.presenceState?.() ?? {};
    this.onlineMetaById.clear();

    for (const key of Object.keys(state)) {
      const metas: PresenceMeta[] = Array.isArray(state[key]) ? state[key] : [];
      if (!metas.length) continue;

      // take the newest meta
      let best = metas[0];
      for (const m of metas) {
        if ((m?.ts ?? 0) > (best?.ts ?? 0)) best = m;
      }

      const userId = String(best.user_id ?? key);
      this.onlineMetaById.set(userId, best);
    }
  }

  // -------------------------
  // Emit Snapshot (stats + dots)
  // -------------------------

  private emit(): void {
    if (!this.onUpdateCb) return;

    // totals per country from all profiles
    const byCountry: Record<string, { total: number; online: number }> = {};
    for (const [, prof] of this.profilesById.entries()) {
      const cc = String(prof.country_code ?? '').trim().toUpperCase();
      if (!cc) continue;
      byCountry[cc] ??= { total: 0, online: 0 };
      byCountry[cc].total += 1;
    }

    // online from realtime presence (instant)
    const onlineIds = Array.from(this.onlineMetaById.keys());

    // dots ONLY for online users
    const now = Date.now();
    const points: ConnectionPoint[] = [];

    for (const userId of onlineIds) {
      const meta = this.onlineMetaById.get(userId);
      const prof = this.profilesById.get(userId);

      const cc = String(meta?.country_code ?? prof?.country_code ?? '').trim().toUpperCase();
      if (!cc) continue;

      const country = this.countryForCode(cc);
      if (!country) continue;

      byCountry[cc] ??= { total: 0, online: 0 };
      byCountry[cc].online += 1;

      const m = this.stepMotion(userId, country, cc, now);

      points.push({
        id: userId,
        lat: m.lat,
        lng: m.lng,
        color: this.DOT_COLOR, // ✅ neon green for all
        radius: 3.5,
      });
    }

    // cleanup motions for users who went offline
    const onlineSet = new Set(onlineIds);
    for (const [uid] of this.motions.entries()) {
      if (!onlineSet.has(uid)) this.motions.delete(uid);
    }

    this.onUpdateCb({
      points,
      onlineIds,
      totalUsers: this.profilesById.size,
      onlineUsers: onlineIds.length,
      byCountry,
    });
  }

  // -------------------------
  // Floating / bounded motion
  // -------------------------

  private stepMotion(userId: string, country: any, cc: string, now: number): Motion {
    const existing = this.motions.get(userId);

    const pool: Array<{ lat: number; lng: number }> = Array.isArray(country.pointPool) ? country.pointPool : [];
    const hasPool = pool.length > 0;

    const contains = (lat: number, lng: number) => {
      // if CountriesService gave you a precomputed “contains” helper, use it.
      // otherwise, fallback to “always true” (won’t break, just won’t bound)
      return typeof country.containsPoint === 'function'
        ? !!country.containsPoint(lat, lng)
        : true;
    };

    const pickStart = (seed: number) => {
      if (!hasPool) return { lat: country.center?.lat ?? 0, lng: country.center?.lng ?? 0 };
      const idx = Math.abs(seed) % pool.length;
      return pool[idx];
    };

    if (!existing || existing.cc !== cc) {
      const seed = this.hash(userId + '|' + cc);
      const start = pickStart(seed);

      const vSeed = this.hash('v|' + userId + '|' + cc);
      const base = 0.010 + ((vSeed % 1000) / 1000) * 0.020; // small
      const dirA = ((vSeed >> 0) & 1) ? 1 : -1;
      const dirB = ((vSeed >> 1) & 1) ? 1 : -1;

      const m: Motion = {
        cc,
        lat: start.lat,
        lng: start.lng,
        vLat: base * 0.65 * dirA,
        vLng: base * 1.0 * dirB,
        lastMs: now,
      };

      this.motions.set(userId, m);
      return m;
    }

    const dt = Math.min(0.25, Math.max(0.016, (now - existing.lastMs) / 1000));
    existing.lastMs = now;

    // gentle drift curve so it looks alive
    const wobSeed = this.hash('w|' + userId) % 1000;
    const wob = Math.sin((now / 700) + wobSeed) * 0.0018;

    let nextLat = existing.lat + (existing.vLat + wob) * dt;
    let nextLng = existing.lng + (existing.vLng - wob) * dt;

    // keep bounded if we can
    if (contains(nextLat, nextLng)) {
      existing.lat = nextLat;
      existing.lng = nextLng;
      existing.vLat = existing.vLat + wob * 0.1;
      existing.vLng = existing.vLng - wob * 0.1;
      return existing;
    }

    // bounce off boundary
    existing.vLat = -existing.vLat;
    existing.vLng = -existing.vLng;

    nextLat = existing.lat + existing.vLat * dt;
    nextLng = existing.lng + existing.vLng * dt;

    if (contains(nextLat, nextLng)) {
      existing.lat = nextLat;
      existing.lng = nextLng;
      return existing;
    }

    // worst-case snap to a valid start point
    const snap = pickStart(this.hash('snap|' + userId + '|' + cc));
    existing.lat = snap.lat;
    existing.lng = snap.lng;
    return existing;
  }

  private countryForCode(code: string): CountryModel | null {
    const cc = String(code ?? '').trim().toUpperCase();
    if (!cc) return null;
    return this.countries.find((x) => String(x.code ?? '').toUpperCase() === cc) || null;
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
