/**
 * MIND §1 — Purpose / product surfaces (Phase 1 catalog).
 * What MIND powers today, with Matterya routes and ledger keys.
 */

export type MindSurfaceCatalogEntry = {
  id: string;
  label: string;
  purpose: string;
  http: string;
  ledgerSurface: string | null;
  client: string;
  namespace: 'public' | 'masquerade';
};

export const MIND_SURFACE_CATALOG: MindSurfaceCatalogEntry[] = [
  {
    id: 'home_for_you',
    label: 'Home · For You',
    purpose: 'Primary personalized feed: ShortForm, hubs, images woven with no-repeat.',
    http: 'GET /v1/feed',
    ledgerSurface: 'home_for_you',
    client: 'iOS Home / web feed',
    namespace: 'public',
  },
  {
    id: 'hubs_for_you',
    label: 'Hubs · For You',
    purpose: 'Cross-hub discovery across comedy/music/travel/… parent shelves.',
    http: 'GET /v1/hubs/for-you',
    ledgerSurface: 'hubs_for_you',
    client: 'iOS Hubs / web hubs',
    namespace: 'public',
  },
  {
    id: 'hubs_shelf',
    label: 'Hubs · Shelf',
    purpose: 'Slug-first shelf paging for a single hub parent.',
    http: 'GET /v1/hubs/shelves/:slug',
    ledgerSurface: null,
    client: 'iOS Hubs shelf rails',
    namespace: 'public',
  },
  {
    id: 'sparks',
    label: 'Sparks',
    purpose: 'Short-form spark surface (cursor / shares; ledger optional).',
    http: 'GET /v1/sparks',
    ledgerSurface: null,
    client: 'iOS Sparks',
    namespace: 'public',
  },
  {
    id: 'masquerade_for_you',
    label: 'Masquerade · For You',
    purpose: 'Anonymous 18+ discovery in rooms; isolated from public preference memory.',
    http: 'GET /v1/anonymous/feed',
    ledgerSurface: 'masquerade_for_you',
    client: 'iOS Masquerade',
    namespace: 'masquerade',
  },
  {
    id: 'search_hybrid',
    label: 'Search · Hybrid',
    purpose: 'Keyword + Voyage semantic retrieval for Public posts (MIND-020).',
    http: 'GET /v1/search',
    ledgerSurface: null,
    client: 'iOS / web Search',
    namespace: 'public',
  },
  {
    id: 'world_country',
    label: 'World · Country',
    purpose: 'Country-scoped discovery with soft MIND rank (MIND-022); geoprivacy: country tag only.',
    http: 'GET /v1/world/country/:code',
    ledgerSurface: null,
    client: 'iOS / web Globe',
    namespace: 'public',
  },
  {
    id: 'people_discovery',
    label: 'People · Discover',
    purpose: 'Suggested creators from public signals only (MIND-021).',
    http: 'GET /v1/people/suggest',
    ledgerSurface: null,
    client: 'iOS / web Search people',
    namespace: 'public',
  },
  {
    id: 'creator_insights',
    label: 'Creator · Insights',
    purpose: 'Owner-only organic engagement rollups (MIND-025).',
    http: 'GET /v1/creator/insights',
    ledgerSurface: null,
    client: 'Creator dashboard',
    namespace: 'public',
  },
];

export const MIND_PURPOSE_BLURB =
  'MIND is Matterya’s shared discovery layer: eligible unseen content in, ranked pages out, with a durable delivery ledger, diversity, and a hard Public vs Masquerade boundary.';
