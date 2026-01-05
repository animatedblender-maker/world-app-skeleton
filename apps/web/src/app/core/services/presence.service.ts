import { Injectable } from '@angular/core';
import { supabase } from '../../supabase/supabase.client';
import type { CountryModel } from '../../data/countries.service';
import type { ConnectionPoint } from '../../globe/globe.service';

type PresenceRow = {
  user_id: string;
  country_code: string | null;
  country_name: string | null;
  city_name: string | null;
  last_seen_at: string;
  is_online: boolean;
};

type ProfileRow = {
  user_id: string;
  country_code: string | null;
  country_name: string;
};

type PresenceSnapshot = {
  points: ConnectionPoint[];
  onlineIds: Array<string>;
  totalUsers: number;
  onlineUsers: number;
};

@Injectable({ providedIn: 'root' })
export class PresenceService {
  private countries: CountryModel[] = [];

  private heartbeatTimer: any = null;
  private readonly HEARTBEAT_MS = 25_000;

  private meId: string | null = null;

  // local caches
  private profilesById = new Map<string, ProfileRow>();
  private presenceById = new Map<string, PresenceRow>();

  private onUpdateCb: ((snap: PresenceSnapshot) => void) | null = null;

  private channel: any = null;
  private currentCountryCode: string | null = null;
  private currentCountryName: string | null = null;
  private currentCityName: string | null = null;

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

    // who am I
    const { data: authData } = await supabase.auth.getUser();
    this.meId = authData.user?.id ?? null;

    this.currentCountryCode = opts.meCountryCode ?? null;
    this.currentCountryName = opts.meCountryName ?? null;
    this.currentCityName = opts.meCityName ?? null;

    // 1) Initial pull: all profiles => all dots
    await this.fetchAllProfiles();

    // 2) Initial pull: presence => who is online right now
    await this.fetchPresenceSnapshot();

    // 3) If I’m logged in, mark me online
    if (this.meId) {
      await this.upsertMyPresence(true);
    }

    // 4) Subscribe to realtime changes in user_presence
    this.channel = supabase
      .channel('worldapp-presence-db')
      .on(
        'postgres_changes',
        { event: '*', schema: 'public', table: 'user_presence' },
        (payload: any) => {
          const row = (payload.new || payload.old) as PresenceRow | undefined;
          if (!row?.user_id) return;

          if (payload.eventType === 'DELETE') {
            this.presenceById.delete(row.user_id);
          } else {
            this.presenceById.set(row.user_id, row);
          }

          this.emit();
        }
      )
      .subscribe();

    // 5) Heartbeat keeps me online + updates last_seen
    if (this.meId) {
      let tick = 0;
      this.heartbeatTimer = setInterval(async () => {
        tick++;

        try {
          await this.upsertMyPresence(true);
          opts.onHeartbeat?.(`heartbeat ✓ (${tick})`);
        } catch (e: any) {
          opts.onHeartbeat?.(`heartbeat ✗ (${e?.message ?? e})`);
        }
      }, this.HEARTBEAT_MS);

      // Best-effort "offline" when tab closes
      window.addEventListener('beforeunload', this.beforeUnloadHandler);
      window.addEventListener('visibilitychange', this.visibilityHandler);
    }

    // first emit
    this.emit();
  }

  stop(): void {
    if (this.heartbeatTimer) clearInterval(this.heartbeatTimer);
    this.heartbeatTimer = null;

    try {
      if (this.channel) supabase.removeChannel(this.channel);
    } catch {}
    this.channel = null;

    this.onUpdateCb = null;

    window.removeEventListener('beforeunload', this.beforeUnloadHandler);
    window.removeEventListener('visibilitychange', this.visibilityHandler);
  }

  async setMyLocation(countryCode: string | null, countryName: string | null, cityName?: string | null) {
    this.currentCountryCode = countryCode ?? null;
    this.currentCountryName = countryName ?? null;
    this.currentCityName = cityName ?? null;

    if (this.meId) {
      await this.upsertMyPresence(true);
      this.emit();
    }
  }

  // -------------------------
  // Internal fetch
  // -------------------------

  private async fetchAllProfiles(): Promise<void> {
    // You can tighten this later (pagination, limiting, etc.)
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

  private async fetchPresenceSnapshot(): Promise<void> {
    const { data, error } = await supabase
      .from('user_presence')
      .select('user_id,country_code,country_name,city_name,last_seen_at,is_online');

    if (error) throw error;

    this.presenceById.clear();
    for (const row of (data || []) as PresenceRow[]) {
      if (!row?.user_id) continue;
      this.presenceById.set(row.user_id, row);
    }
  }

  private async upsertMyPresence(isOnline: boolean): Promise<void> {
    if (!this.meId) return;

    const payload: Partial<PresenceRow> & { user_id: string } = {
      user_id: this.meId,
      is_online: !!isOnline,
      last_seen_at: new Date().toISOString(),
      country_code: this.currentCountryCode ?? null,
      country_name: this.currentCountryName ?? null,
      city_name: this.currentCityName ?? null,
    };

    const { error } = await supabase
      .from('user_presence')
      .upsert(payload, { onConflict: 'user_id' });

    if (error) throw error;

    // keep local in sync
    const existing = this.presenceById.get(this.meId);
    this.presenceById.set(this.meId, {
      user_id: this.meId,
      country_code: payload.country_code ?? existing?.country_code ?? null,
      country_name: payload.country_name ?? existing?.country_name ?? null,
      city_name: payload.city_name ?? existing?.city_name ?? null,
      last_seen_at: payload.last_seen_at!,
      is_online: payload.is_online ?? true,
    } as PresenceRow);
  }

  // -------------------------
  // Emit => points + online ids
  // -------------------------

  private emit(): void {
    if (!this.onUpdateCb) return;

    // build a dot per profile (all users)
    const points: ConnectionPoint[] = [];
    const onlineIds: string[] = [];

    for (const [userId, prof] of this.profilesById.entries()) {
      const cc = (prof.country_code || '').trim();

      const center = this.centerForCountryCode(cc);
      if (!center) continue;

      // jitter so multiple users in same country don’t stack perfectly
      const j = this.jitterForUser(userId, cc);
      const lat = center.lat + j.lat;
      const lng = center.lng + j.lng;

      const baseColor = this.colorForUser(userId);

      points.push({
        id: userId,
        lat,
        lng,
        color: baseColor,
        radius: 3.5,
      });

      const pres = this.presenceById.get(userId);
      if (pres?.is_online) onlineIds.push(userId);
    }

    this.onUpdateCb({
      points,
      onlineIds,
      totalUsers: points.length,
      onlineUsers: onlineIds.length,
    });
  }

  private centerForCountryCode(code: string): { lat: number; lng: number } | null {
    if (!code) return null;

    // your CountriesService sets `code` to ISO_A2 / etc.
    const c = this.countries.find((x) => (x.code || '').toUpperCase() === code.toUpperCase());
    if (!c) return null;

    return { lat: c.center.lat, lng: c.center.lng };
  }

  private jitterForUser(userId: string, countryCode: string): { lat: number; lng: number } {
    // stable pseudo-random per user+country
    const seed = this.hash(userId + '|' + countryCode);
    const a = (seed % 1000) / 1000; // 0..1
    const b = ((seed / 1000) % 1000) / 1000;

    // small offsets (degrees) so it looks “floating”
    const lat = (a - 0.5) * 1.6; // +/- 0.8 deg
    const lng = (b - 0.5) * 1.6;

    return { lat, lng };
  }

  private colorForUser(userId: string): string {
    // mystical cyan base, slightly varied
    const h = this.hash(userId) % 360;
    // keep it “blue-ish” range but not identical
    const hue = 160 + (h % 80); // 160..239
    return `hsla(${hue}, 90%, 70%, 0.85)`;
  }

  private hash(s: string): number {
    let h = 2166136261;
    for (let i = 0; i < s.length; i++) {
      h ^= s.charCodeAt(i);
      h = Math.imul(h, 16777619);
    }
    return Math.abs(h);
  }

  // -------------------------
  // unload / visibility handlers
  // -------------------------

  private beforeUnloadHandler = () => {
    // best-effort: mark offline (may not always run)
    this.upsertMyPresence(false).catch(() => {});
  };

  private visibilityHandler = () => {
    if (document.visibilityState === 'hidden') {
      this.upsertMyPresence(false).catch(() => {});
    } else {
      this.upsertMyPresence(true).catch(() => {});
    }
  };
}
