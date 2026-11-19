/**
 * Public seed / pipeline catalog kill switch (App Review).
 *
 * SEED_CATALOG_PUBLIC=false (default) →
 *   - hide seed/harness authors
 *   - hide LongForm / hub-catalog pipeline videos (even when owned by real team accounts)
 * Rows stay in DB. After Accept: SEED_CATALOG_PUBLIC=true on Render — no app update.
 *
 * MASQUERADE_PUBLIC=false (default) →
 *   - /v1/anonymous returns soft-offline (no spaces, no posts)
 *   - features.anonymous=false
 * After Accept: MASQUERADE_PUBLIC=true on Render.
 */

function envOn(key: string): boolean {
  const v = String(process.env[key] ?? '')
    .trim()
    .toLowerCase();
  return v === '1' || v === 'true' || v === 'yes' || v === 'on';
}

export function seedCatalogPublic(): boolean {
  return envOn('SEED_CATALOG_PUBLIC');
}

/** Masquerade public surfaces. Default off for App Review. */
export function masqueradePublic(): boolean {
  return envOn('MASQUERADE_PUBLIC');
}

/**
 * SQL AND-fragment when seeds are hidden.
 * Expects `profiles` already joined as `profileAlias` on posts.author_id.
 * Returns empty string when catalog is public.
 */
export function seedAuthorSqlFilter(profileAlias = 'pr'): string {
  if (seedCatalogPublic()) return '';
  const a = profileAlias.replace(/[^a-zA-Z0-9_]/g, '') || 'pr';
  return `
    and ${a}.user_id is not null
    and coalesce(${a}.email, '') not ilike '%@seed.matterya.internal'
    and coalesce(${a}.email, '') not ilike '%@matterya.dev'
    and coalesce(${a}.email, '') not ilike 'ios.test%@gmail.com'
    and coalesce(${a}.email, '') not ilike 'flutter_test%@%'
    and coalesce(${a}.email, '') not ilike 'android_crash_test%@%'
    and coalesce(${a}.email, '') not ilike 'iostester@%'
    and coalesce(${a}.bio, '') is distinct from 'Matterya seed profile'
  `;
}

/**
 * Hide pipeline Hubs LongForm catalog (R2 LongForm paths + __hub_* body stamps).
 * Team accounts often own these packs — author filter alone is not enough.
 * postAlias defaults to `p`.
 */
export function seedHubCatalogSqlFilter(postAlias = 'p'): string {
  if (seedCatalogPublic()) return '';
  const p = postAlias.replace(/[^a-zA-Z0-9_]/g, '') || 'p';
  return `
    and coalesce(${p}.media_path, '') not like '%/LongForm/%'
    and coalesce(${p}.media_url::text, '') not like '%/LongForm/%'
    and position('__hub_channel__|' in coalesce(${p}.body, '')) = 0
    and position('__hub_origin__|' in coalesce(${p}.body, '')) = 0
  `;
}

/** True when Hubs public catalog should be empty (fast path — skip 7s scans). */
export function hubsCatalogPublic(): boolean {
  return seedCatalogPublic();
}
