import { createHash, randomBytes } from 'node:crypto';
import { pool } from '../db.js';
import { createAuthUser, supabaseAdminConfigured } from '../supabase-admin.js';
import { pipelineLog } from './log.js';
import type { ProfileOwner } from './types.js';
import { FOCUS_COUNTRIES } from './r2.js';

const SEED_EMAIL_DOMAIN = 'seed.matterya.internal';
/** Minimum owners per focus country so packs are never skipped for empty pools. */
const MIN_OWNERS_PER_COUNTRY = 24;

/** Compact country-appropriate first/last pairs — used only when a country pool is empty. */
const SEED_NAMES: Record<string, Array<{ first: string; last: string }>> = {
  US: [
    { first: 'Jordan', last: 'Hayes' },
    { first: 'Taylor', last: 'Brooks' },
    { first: 'Casey', last: 'Morgan' },
    { first: 'Riley', last: 'Parker' },
    { first: 'Avery', last: 'Quinn' },
    { first: 'Cameron', last: 'Blake' },
    { first: 'Harper', last: 'Reed' },
    { first: 'Drew', last: 'Sullivan' },
    { first: 'Skyler', last: 'Bennett' },
    { first: 'Reese', last: 'Callahan' },
    { first: 'Logan', last: 'Ellis' },
    { first: 'Parker', last: 'Nash' },
  ],
  DE: [
    { first: 'Lukas', last: 'Weber' },
    { first: 'Mia', last: 'Fischer' },
    { first: 'Jonas', last: 'Bauer' },
    { first: 'Emma', last: 'Hoffmann' },
    { first: 'Noah', last: 'Koch' },
    { first: 'Lea', last: 'Schröder' },
    { first: 'Felix', last: 'Neumann' },
    { first: 'Sophie', last: 'Schwarz' },
    { first: 'Paul', last: 'Zimmermann' },
    { first: 'Clara', last: 'Krüger' },
    { first: 'Ben', last: 'Hartmann' },
    { first: 'Lina', last: 'Werner' },
  ],
  EG: [
    { first: 'Omar', last: 'Hassan' },
    { first: 'Nour', last: 'Ibrahim' },
    { first: 'Youssef', last: 'Ali' },
    { first: 'Sara', last: 'Mahmoud' },
    { first: 'Karim', last: 'Farouk' },
    { first: 'Layla', last: 'Said' },
    { first: 'Ahmed', last: 'Mostafa' },
    { first: 'Mona', last: 'Khaled' },
    { first: 'Tarek', last: 'Nabil' },
    { first: 'Hana', last: 'Adel' },
    { first: 'Ziad', last: 'Samir' },
    { first: 'Dina', last: 'Fathy' },
  ],
  AL: [
    { first: 'Arben', last: 'Krasniqi' },
    { first: 'Elira', last: 'Hoxha' },
    { first: 'Driton', last: 'Berisha' },
    { first: 'Anisa', last: 'Gashi' },
    { first: 'Blerim', last: 'Kola' },
    { first: 'Era', last: 'Dervishi' },
    { first: 'Ilir', last: 'Meta' },
    { first: 'Teuta', last: 'Shehu' },
    { first: 'Gent', last: 'Leka' },
    { first: 'Mira', last: 'Basha' },
    { first: 'Endrit', last: 'Ajazi' },
    { first: 'Lira', last: 'Cela' },
  ],
};

/**
 * Load real profile owners by focus country.
 * Empty pools are filled by `ensureOwnersByCountry` — never invent orphan posts.
 */
export async function loadOwnersByCountry(): Promise<Map<string, ProfileOwner[]>> {
  const codes = FOCUS_COUNTRIES.map((c) => c.code);
  const { rows } = await pool.query<{
    user_id: string;
    country_code: string | null;
    country_name: string | null;
    city_name: string | null;
    display_name: string | null;
    username: string | null;
  }>(
    `
    select user_id, country_code, country_name, city_name, display_name, username
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
      displayName: row.display_name,
      username: row.username,
    });
  }
  return map;
}

/**
 * Ensure every focus country has enough owners so packs are never skipped.
 * Creates confirmed seed auth users + profiles when a country pool is thin/empty.
 */
export async function ensureOwnersByCountry(
  minPerCountry: number = MIN_OWNERS_PER_COUNTRY
): Promise<Map<string, ProfileOwner[]>> {
  let map = await loadOwnersByCountry();

  for (const country of FOCUS_COUNTRIES) {
    const existing = map.get(country.code) ?? [];
    if (existing.length >= minPerCountry) continue;

    const need = minPerCountry - existing.length;
    pipelineLog(
      `Owners thin for ${country.code} (${existing.length}/${minPerCountry}) — creating ${need} seed profile(s)…`,
      'warn'
    );

    if (!supabaseAdminConfigured()) {
      pipelineLog(
        `Cannot create seed owners for ${country.code}: SUPABASE_SERVICE_ROLE_KEY / SUPABASE_URL missing`,
        'error'
      );
      continue;
    }

    const created = await createSeedOwnersForCountry(country, need, existing);
    if (created.length) {
      pipelineLog(`Created ${created.length} seed owner(s) for ${country.code}`, 'ok');
    }
  }

  map = await loadOwnersByCountry();
  for (const country of FOCUS_COUNTRIES) {
    const n = map.get(country.code)?.length ?? 0;
    pipelineLog(`Owners ${country.code}: ${n}`, n > 0 ? 'ok' : 'error');
  }
  return map;
}

async function createSeedOwnersForCountry(
  country: { folder: string; code: string; name: string },
  need: number,
  existing: ProfileOwner[]
): Promise<ProfileOwner[]> {
  const names = SEED_NAMES[country.code] ?? SEED_NAMES.US!;
  const usedUsernames = new Set(
    existing.map((o) => (o.username || '').toLowerCase()).filter(Boolean)
  );
  const out: ProfileOwner[] = [];

  for (let i = 0; i < need; i++) {
    const pick = names[i % names.length]!;
    const suffix = randomBytes(3).toString('hex');
    let username = slugUsername(`${pick.first}_${pick.last}_${suffix}`);
    while (usedUsernames.has(username.toLowerCase())) {
      username = slugUsername(`${pick.first}_${pick.last}_${randomBytes(3).toString('hex')}`);
    }
    usedUsernames.add(username.toLowerCase());

    const displayName = `${pick.first} ${pick.last}`;
    const email = `seed.${country.code.toLowerCase()}.${Date.now()}.${suffix}@${SEED_EMAIL_DOMAIN}`;
    const password = `Mt!${randomBytes(12).toString('base64url')}`;

    try {
      const user = await createAuthUser({
        email,
        password,
        emailConfirm: true,
        userMetadata: {
          display_name: displayName,
          username,
          country_code: country.code,
          country_name: country.name,
        },
      });

      // Trigger may insert Unknown — force focus country + name.
      await pool.query(
        `
        insert into public.profiles (
          user_id, email, display_name, username, country_name, country_code, bio
        )
        values ($1::uuid, $2, $3, $4, $5, $6, $7)
        on conflict (user_id) do update set
          email = excluded.email,
          display_name = excluded.display_name,
          username = coalesce(excluded.username, public.profiles.username),
          country_name = excluded.country_name,
          country_code = excluded.country_code,
          updated_at = now()
        `,
        [
          user.id,
          email,
          displayName,
          username,
          country.name,
          country.code,
          'Matterya seed profile',
        ]
      );

      out.push({
        userId: user.id,
        countryCode: country.code,
        countryName: country.name,
        cityName: null,
        displayName,
        username,
      });
    } catch (err: any) {
      pipelineLog(
        `Seed owner create failed (${country.code}): ${err?.message ?? err}`,
        'error'
      );
    }
  }

  return out;
}

function slugUsername(raw: string): string {
  return raw
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^\w]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 24) || `seed_${randomBytes(4).toString('hex')}`;
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
