/**
 * Public seed / pipeline catalog kill switch.
 *
 * SEED_CATALOG_PUBLIC=false (default) → Feed / Sparks / Hubs hide authors that are
 * pipeline seeds (`@seed.matterya.internal`) or harness accounts. Rows stay in DB.
 * After App Store acceptance, set SEED_CATALOG_PUBLIC=true on Render — no app update.
 */

export function seedCatalogPublic(): boolean {
  const v = String(process.env.SEED_CATALOG_PUBLIC ?? '')
    .trim()
    .toLowerCase();
  return v === '1' || v === 'true' || v === 'yes' || v === 'on';
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
