import { Injectable } from '@angular/core';
import { supabase } from '../../supabase/supabase.client';
import type { CountryModel } from '../../data/countries.service';
import type { ConnectionPoint } from '../../globe/globe.service';

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

@Injectable({ providedIn: 'root' })
export class PresenceService {
  private countries: CountryModel[] = [];
  private channel: any = null;

  private profilesById = new Map<string, ProfileRow>();

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
  private readonly RENDER_MS = 250;

  // totals refresh (new registrations)
  private refreshProfilesTimer: any = null;
  private readonly PROFILES_REFRESH_MS = 120_000;

  // Dot styling for all presence points.
  private readonly DOT_COLOR = 'rgba(0,255,209,0.92)';

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

    // totals
    await this.fetchAllProfiles();

    // online (accurate)
    await this.startRealtimePresence();

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

    try {
      if (this.channel) supabase.removeChannel(this.channel);
    } catch {}
    this.channel = null;

    this.onUpdateCb = null;
    this.onHeartbeatCb = null;

    this.onlineMetaById.clear();
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
    const { data, error } = await supabase
      .from('profiles')
      .select('user_id,country_code,country_name,city_name');

    if (error) throw error;

    this.profilesById.clear();
    for (const row of (data || []) as ProfileRow[]) {
      if (!row?.user_id) continue;
      this.profilesById.set(row.user_id, row);
    }
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

    // totals from profiles
    for (const [, prof] of this.profilesById.entries()) {
      const cc = String(prof.country_code ?? '').trim().toUpperCase();
      if (!cc) continue;
      byCountry[cc] ??= { total: 0, online: 0 };
      byCountry[cc].total += 1;
    }

    const onlineIds = Array.from(this.onlineMetaById.keys());

    // dots for online only
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

      const cityName = meta?.city_name ?? prof?.city_name ?? null;
      const pos = this.approximatePoint(country, userId, cityName);

      points.push({
        id: userId,
        lat: pos.lat,
        lng: pos.lng,
        cc,
        color: this.DOT_COLOR,
        radius: 3.6,
      });
    }

    this.onUpdateCb({
      points,
      onlineIds,
      totalUsers: this.profilesById.size,
      onlineUsers: onlineIds.length,
      byCountry,
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
