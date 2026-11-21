/**
 * Seed / pipeline catalog visibility.
 *
 * Default: catalog is PUBLIC for everyone (seeds, LongForm Hubs, Masquerade).
 *
 * App Review thin mode is **viewer-scoped** — only `iostester@matterya.com`
 * (plus optional `APP_REVIEW_EMAILS`) sees:
 *   - few real posts (seed authors + LongForm hub catalog hidden)
 *   - empty Hubs shelves
 *   - Masquerade age re-confirm + empty spaces/posts
 *
 * Emergency global kill (hide for everyone): SEED_CATALOG_PUBLIC=false
 * Emergency Masquerade pause (everyone): MASQUERADE_PUBLIC=false
 */

function envOn(key: string): boolean {
  const v = String(process.env[key] ?? '')
    .trim()
    .toLowerCase();
  return v === '1' || v === 'true' || v === 'yes' || v === 'on';
}

function envExplicitlySet(key: string): boolean {
  const v = process.env[key];
  return v != null && String(v).trim() !== '';
}

const DEFAULT_APP_REVIEW_EMAILS = ['iostester@matterya.com'];

/** Emails that get the thin App Review experience. */
export function appReviewEmails(): Set<string> {
  const extra = String(process.env.APP_REVIEW_EMAILS ?? '')
    .split(/[,;\s]+/)
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
  return new Set([...DEFAULT_APP_REVIEW_EMAILS, ...extra]);
}

export function isAppReviewViewer(email?: string | null): boolean {
  const e = String(email ?? '')
    .trim()
    .toLowerCase();
  if (!e) return false;
  return appReviewEmails().has(e);
}

/**
 * Global seed catalog. Default **true** (public).
 * Set SEED_CATALOG_PUBLIC=false only for an emergency everyone-hide.
 */
export function seedCatalogPublic(): boolean {
  if (!envExplicitlySet('SEED_CATALOG_PUBLIC')) return true;
  return envOn('SEED_CATALOG_PUBLIC');
}

/**
 * Global Masquerade. Default **true** (public).
 * Set MASQUERADE_PUBLIC=false only for an emergency everyone-pause.
 */
export function masqueradePublic(): boolean {
  if (!envExplicitlySet('MASQUERADE_PUBLIC')) return true;
  return envOn('MASQUERADE_PUBLIC');
}

/** This viewer should see the thin Review catalog (seeds/hubs hidden). */
export function viewerSeesThinCatalog(email?: string | null): boolean {
  if (!seedCatalogPublic()) return true;
  return isAppReviewViewer(email);
}

/** Hubs LongForm empty for this viewer (fast path). */
export function hubsEmptyForViewer(email?: string | null): boolean {
  return viewerSeesThinCatalog(email);
}

/**
 * SQL AND-fragment when thin catalog applies for this viewer.
 * Expects `profiles` already joined as `profileAlias` on posts.author_id.
 */
export function seedAuthorSqlFilter(
  profileAlias = 'pr',
  viewerEmail?: string | null
): string {
  if (!viewerSeesThinCatalog(viewerEmail)) return '';
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
 * Hide pipeline Hubs LongForm catalog for thin-catalog viewers.
 */
export function seedHubCatalogSqlFilter(
  postAlias = 'p',
  viewerEmail?: string | null
): string {
  if (!viewerSeesThinCatalog(viewerEmail)) return '';
  const p = postAlias.replace(/[^a-zA-Z0-9_]/g, '') || 'p';
  return `
    and coalesce(${p}.media_path, '') not like '%/LongForm/%'
    and coalesce(${p}.media_url::text, '') not like '%/LongForm/%'
    and position('__hub_channel__|' in coalesce(${p}.body, '')) = 0
    and position('__hub_origin__|' in coalesce(${p}.body, '')) = 0
  `;
}

/** @deprecated use hubsEmptyForViewer — kept for call-site compatibility during migrate */
export function hubsCatalogPublic(): boolean {
  return seedCatalogPublic();
}
