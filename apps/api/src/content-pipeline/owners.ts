import { createHash } from 'node:crypto';
import { pool } from '../db.js';
import type { ProfileOwner } from './types.js';
import { FOCUS_COUNTRIES } from './r2.js';

/**
 * Real profile owners only — never invent users.
 * Empty country pool → caller must skip the pack (no orphans).
 */
export async function loadOwnersByCountry(): Promise<Map<string, ProfileOwner[]>> {
  const codes = FOCUS_COUNTRIES.map((c) => c.code);
  const { rows } = await pool.query<{
    user_id: string;
    country_code: string | null;
    country_name: string | null;
    city_name: string | null;
  }>(
    `
    select user_id, country_code, country_name, city_name
    from public.profiles
    where country_code = any($1::text[])
      and user_id is not null
    `,
    [codes]
  );

  const map = new Map<string, ProfileOwner[]>();
  for (const code of codes) map.set(code, []);

  for (const row of rows) {
    const code = (row.country_code || '').toUpperCase();
    if (!map.has(code)) continue;
    map.get(code)!.push({
      userId: row.user_id,
      countryCode: code,
      countryName: row.country_name,
      cityName: row.city_name,
    });
  }
  return map;
}

/** Stable pick so re-runs assign the same author to the same pack. */
export function pickOwner(pool: ProfileOwner[], mediaPath: string): ProfileOwner | null {
  if (!pool.length) return null;
  const h = createHash('sha256').update(mediaPath).digest();
  const idx = h.readUInt32BE(0) % pool.length;
  return pool[idx]!;
}

/** Different sharer when possible; falls back to same owner if only one profile. */
export function pickSharer(
  pool: ProfileOwner[],
  authorId: string,
  seed: string
): ProfileOwner | null {
  if (!pool.length) return null;
  const others = pool.filter((p) => p.userId !== authorId);
  const use = others.length ? others : pool;
  const h = createHash('sha256').update(`share:${seed}`).digest();
  const idx = h.readUInt32BE(0) % use.length;
  return use[idx]!;
}

export async function defaultCategoryId(): Promise<string | null> {
  const { rows } = await pool.query<{ id: string }>(
    `select id from public.categories order by slug nulls last limit 1`
  );
  return rows[0]?.id ?? null;
}
