// apps/api/src/graphql/modules/presence/presence.service.ts
import { pool } from '../../../db.js';

export type AuthedUser = {
  id: string;
  email?: string;
  role?: string;
};

export type GlobalStats = {
  totalUsers: number;
  onlineNow: number;
  ttlSeconds: number;
  computedAt: string;
};

export type CountryStats = {
  iso: string;
  name: string | null;
  totalUsers: number;
  onlineNow: number;
  ttlSeconds: number;
  computedAt: string;
};

export type HeartbeatResult = {
  ok: boolean;
  ttlSeconds: number;
  lastSeen: string;
};

export class PresenceService {
  // ✅ "Online" definition: is_online=true and last_seen_at within TTL
  private readonly ttlSeconds = Number(process.env.PRESENCE_TTL_SECONDS ?? 70);

  getTTL(): number {
    return this.ttlSeconds;
  }

  private nowIso(): string {
    return new Date().toISOString();
  }

  async globalStats(): Promise<GlobalStats> {
    const ttl = this.ttlSeconds;

    // total users = profiles count
    const totalQ = await pool.query<{ n: string }>(
      `select count(*)::text as n from public.profiles`
    );

    // online = presence rows fresh within TTL
    const onlineQ = await pool.query<{ n: string }>(
      `
      select count(*)::text as n
      from public.user_presence
      where is_online = true
        and last_seen_at > (now() - ($1 || ' seconds')::interval)
      `,
      [ttl]
    );

    return {
      totalUsers: Number(totalQ.rows?.[0]?.n ?? 0),
      onlineNow: Number(onlineQ.rows?.[0]?.n ?? 0),
      ttlSeconds: ttl,
      computedAt: this.nowIso(),
    };
  }

  async countryStats(iso: string): Promise<CountryStats> {
    const ttl = this.ttlSeconds;
    const want = String(iso || '').trim().toUpperCase();

    // total in country = profiles with country_code = ISO
    const totalQ = await pool.query<{ n: string; country_name: string | null }>(
      `
      select
        count(*)::text as n,
        max(country_name) as country_name
      from public.profiles
      where upper(coalesce(country_code,'')) = $1
      `,
      [want]
    );

    // online in country = presence fresh within TTL & country_code match
    const onlineQ = await pool.query<{ n: string }>(
      `
      select count(*)::text as n
      from public.user_presence
      where is_online = true
        and last_seen_at > (now() - ($1 || ' seconds')::interval)
        and upper(coalesce(country_code,'')) = $2
      `,
      [ttl, want]
    );

    return {
      iso: want,
      name: totalQ.rows?.[0]?.country_name ?? null,
      totalUsers: Number(totalQ.rows?.[0]?.n ?? 0),
      onlineNow: Number(onlineQ.rows?.[0]?.n ?? 0),
      ttlSeconds: ttl,
      computedAt: this.nowIso(),
    };
  }

  async heartbeat(user: AuthedUser, iso?: string | null): Promise<HeartbeatResult> {
    const ttl = this.ttlSeconds;
    const lastSeen = this.nowIso();

    // pull user's current profile location (preferred)
    const profQ = await pool.query<{
      country_code: string | null;
      country_name: string | null;
      city_name: string | null;
    }>(
      `
      select country_code, country_name, city_name
      from public.profiles
      where user_id = $1
      limit 1
      `,
      [user.id]
    );

    const prof = profQ.rows?.[0];

    // allow iso override (some clients only know ISO)
    const countryCode = (iso ?? prof?.country_code ?? null);
    const countryName = prof?.country_name ?? null;
    const cityName = prof?.city_name ?? null;

    await pool.query(
      `
      insert into public.user_presence (user_id, country_code, country_name, city_name, is_online, last_seen_at)
      values ($1, $2, $3, $4, true, $5)
      on conflict (user_id) do update set
        country_code = excluded.country_code,
        country_name = excluded.country_name,
        city_name    = excluded.city_name,
        is_online    = true,
        last_seen_at = excluded.last_seen_at
      `,
      [user.id, countryCode, countryName, cityName, lastSeen]
    );

    return { ok: true, ttlSeconds: ttl, lastSeen };
  }

  async setOffline(user: AuthedUser): Promise<boolean> {
    await pool.query(
      `
      update public.user_presence
      set is_online = false,
          last_seen_at = now()
      where user_id = $1
      `,
      [user.id]
    );

    return true;
  }
}
