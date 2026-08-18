/**
 * Slug-first Hubs shelves — thin cards, cursor pages.
 *
 * Clients must NOT download the full catalog. They request:
 *   GET /v1/hubs/for-you?limit=20&cursor=&session=
 *   GET /v1/hubs/shelves/:slug?limit=20&cursor=
 *
 * Each item is a thin card (id, slug, title, poster, play URL, author).
 * Full post bodies / comments load only on open.
 */
import { pool } from '../db.js';
import { freshenMediaUrlString } from '../media/r2-playback.js';

export const HUB_PARENT_SLUGS = [
  'comedy',
  'music',
  'travel',
  'nature',
  'food',
  'sports',
  'tech',
  'fitness',
  'film',
  'culture',
  'history',
  'education',
  'animals',
  'cars',
  'news',
  'fashion',
  'gaming',
  'kids',
  'social',
  'daily',
] as const;

export type HubParentSlug = (typeof HUB_PARENT_SLUGS)[number];

const KEYWORD_BUCKETS: { category: HubParentSlug; words: string[] }[] = [
  { category: 'comedy', words: ['comedy', 'funny', 'humor', 'humour', 'joke', 'sketch', 'laugh', 'gag', 'parody', 'satire', 'slapstick', 'standup', 'sitcom', 'prank'] },
  { category: 'music', words: ['music', 'song', 'jazz', 'blues', 'concert', 'orchestra', 'band', 'singer', 'piano', 'guitar', 'opera', 'symphony', 'choir', 'melody', 'soundtrack', 'anthem', 'hymn'] },
  { category: 'travel', words: ['travel', 'trip', 'tour', 'voyage', 'journey', 'city', 'paris', 'london', 'tokyo', 'vista', 'abroad', 'cruise', 'railway', 'train', 'airport', 'hotel'] },
  { category: 'nature', words: ['nature', 'forest', 'wildlife', 'mountain', 'river', 'ocean', 'sea', 'lake', 'garden', 'flower', 'landscape', 'earth', 'weather', 'storm', 'volcano', 'glacier', 'timelapse'] },
  { category: 'food', words: ['food', 'recipe', 'cook', 'kitchen', 'breakfast', 'dinner', 'coffee', 'restaurant', 'farm', 'bread', 'fruit', 'vegetable', 'meal'] },
  { category: 'sports', words: ['sport', 'football', 'baseball', 'basketball', 'soccer', 'tennis', 'golf', 'olympics', 'race', 'racing', 'boxing', 'wrestling', 'athletic', 'stadium'] },
  { category: 'tech', words: ['tech', 'computer', 'robot', 'electronic', 'telephone', 'engineering', 'invention', 'space', 'rocket', 'satellite', 'digital'] },
  { category: 'fitness', words: ['fitness', 'exercise', 'workout', 'yoga', 'gym', 'posture', 'aerobics', 'strength'] },
  { category: 'film', words: ['movie', 'cinema', 'trailer', 'cartoon', 'animation', 'animated', 'feature', 'disney', 'film', 'commercial', 'silent film'] },
  { category: 'culture', words: ['culture', 'art', 'museum', 'dance', 'ballet', 'theatre', 'theater', 'architecture', 'literature', 'poetry'] },
  { category: 'history', words: ['history', 'historical', 'war', 'wwii', 'ww2', 'civil war', 'newsreel', 'archival', 'vintage'] },
  { category: 'education', words: ['education', 'school', 'classroom', 'lesson', 'howto', 'how to', 'tutorial', 'instruction', 'learn', 'teaching'] },
  { category: 'animals', words: ['animal', 'dog', 'cat', 'pet', 'bird', 'horse', 'zoo', 'wildlife', 'creature', 'puppy', 'kitten'] },
  { category: 'cars', words: ['car', 'auto', 'automobile', 'motor', 'vehicle', 'truck', 'honda', 'ford', 'chevrolet'] },
  { category: 'news', words: ['news', 'broadcast', 'reporter', 'headline', 'bulletin', 'newscast', 'anchor'] },
  { category: 'fashion', words: ['fashion', 'style', 'clothing', 'dress', 'runway', 'model', 'wardrobe', 'beauty'] },
  { category: 'gaming', words: ['game', 'gaming', 'arcade', 'video game', 'nintendo', 'atari'] },
  { category: 'kids', words: ['kids', 'children', 'child', 'nursery', 'story time', 'babies'] },
  { category: 'social', words: ['people', 'family', 'community', 'street', 'crowd', 'party', 'wedding', 'social', 'friends'] },
  { category: 'daily', words: ['daily', 'home', 'house', 'routine', 'morning', 'evening', 'housework', 'domestic'] },
];

export type ThinShelfCard = {
  id: string;
  slug: string;
  title: string | null;
  body: string | null;
  media_type: string;
  media_url: string | null;
  thumb_url: string | null;
  like_count: number;
  comment_count: number;
  created_at: string;
  country_code: string | null;
  country_name: string | null;
  author_id: string;
  author_name: string | null;
  author_username: string | null;
  author_avatar: string | null;
  /** Share → origin post id for comments (hub/spark stamps or DB shared_post_id). */
  shared_post_id: string | null;
  /** Alias of shared_post_id for clients that read origin_sid. */
  origin_sid: string | null;
};

export type ShelfPage = {
  slug: string;
  items: ThinShelfCard[];
  nextCursor: string | null;
  count: number;
};

export type ForYouPage = {
  surface: 'hubs_for_you';
  items: ThinShelfCard[];
  nextCursor: string | null;
  slugsUsed: string[];
  count: number;
  session: string;
};

type RawPostRow = {
  id: string;
  title: string | null;
  body: string | null;
  media_type: string;
  media_url: string | null;
  thumb_url: string | null;
  like_count: number;
  comment_count: number;
  created_at: Date | string;
  country_code: string | null;
  country_name: string | null;
  author_id: string;
  hub_slug: string | null;
  shared_post_id: string | null;
  author_name: string | null;
  author_username: string | null;
  author_avatar: string | null;
};

/** Extract origin post id from hub/spark share stamps before body scrub. */
function originSidFromBody(body: string | null | undefined): string | null {
  if (!body) return null;
  const hub = body.match(/__hub_origin__\|(?:[^|\n]*\|)*sid=([^|\n]+)/i);
  if (hub?.[1]?.trim()) return hub[1].trim();
  const spark = body.match(/__spark_share__\|(?:[^|\n]*\|)*sid=([^|\n]+)/i);
  if (spark?.[1]?.trim()) return spark[1].trim();
  return null;
}

/** Whether posts.hub_slug exists (migration may lag deploy). */
let hubSlugColumnReady: boolean | null = null;

async function hasHubSlugColumn(): Promise<boolean> {
  if (hubSlugColumnReady != null) return hubSlugColumnReady;
  try {
    const { rows } = await pool.query<{ exists: boolean }>(
      `select exists (
         select 1 from information_schema.columns
         where table_schema = 'public'
           and table_name = 'posts'
           and column_name = 'hub_slug'
       ) as exists`
    );
    hubSlugColumnReady = Boolean(rows[0]?.exists);
  } catch {
    hubSlugColumnReady = false;
  }
  return hubSlugColumnReady;
}

export function normalizeParentSlug(raw: string | null | undefined): HubParentSlug {
  const s = String(raw ?? '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, '_');
  if (!s) return 'daily';
  if ((HUB_PARENT_SLUGS as readonly string[]).includes(s)) return s as HubParentSlug;
  // persona → parent (music_jazz → music)
  const parent = s.split('_')[0];
  if ((HUB_PARENT_SLUGS as readonly string[]).includes(parent)) {
    return parent as HubParentSlug;
  }
  return 'daily';
}

/** Same idea as iOS HubCategoryClassifier — cheap keyword scores. */
export function classifyHubSlug(input: {
  title?: string | null;
  body?: string | null;
  seedSlug?: string | null;
  creator?: string | null;
}): HubParentSlug {
  // Explicit stored slug wins (migration / publisher).
  const rawSeed = String(input.seedSlug ?? '').trim();
  if (rawSeed) return normalizeParentSlug(rawSeed);

  const blob = [input.title ?? '', input.body ?? '', input.creator ?? '']
    .join(' ')
    .toLowerCase();

  const scores = new Map<string, number>();
  for (const bucket of KEYWORD_BUCKETS) {
    let score = 0;
    for (const word of bucket.words) {
      if (blob.includes(word)) score += word.length >= 6 ? 3 : 2;
    }
    if (score > 0) scores.set(bucket.category, (scores.get(bucket.category) ?? 0) + score);
  }

  let best: string | null = null;
  let bestScore = 0;
  for (const [k, v] of scores) {
    if (v > bestScore) {
      best = k;
      bestScore = v;
    }
  }
  if (best && bestScore >= 2) return best as HubParentSlug;
  return 'daily';
}

function encodeCursor(createdAt: string, id: string): string {
  return Buffer.from(`${createdAt}|${id}`, 'utf8').toString('base64url');
}

function decodeCursor(cursor: string | null | undefined): { createdAt: string; id: string } | null {
  if (!cursor) return null;
  try {
    const raw = Buffer.from(String(cursor), 'base64url').toString('utf8');
    const pipe = raw.indexOf('|');
    if (pipe <= 0) return null;
    const createdAt = raw.slice(0, pipe);
    const id = raw.slice(pipe + 1);
    if (!createdAt || !id) return null;
    return { createdAt, id };
  } catch {
    return null;
  }
}

function toIso(v: Date | string): string {
  if (v instanceof Date) return v.toISOString();
  const d = new Date(v);
  return Number.isFinite(d.getTime()) ? d.toISOString() : String(v);
}

/** LongForm/<Country>/<youtubeId>/video.mp4 → YouTube CDN poster (shelves had null thumbs). */
/** Re-presign media_url on shelf pages so clients never open a 403 public r2.dev link. */
async function freshenCardMedia(items: ThinShelfCard[]): Promise<ThinShelfCard[]> {
  if (!items.length) return items;
  const concurrency = 6;
  const out: ThinShelfCard[] = new Array(items.length);
  let idx = 0;
  async function worker() {
    while (idx < items.length) {
      const i = idx++;
      const card = items[i];
      const fresh = await freshenMediaUrlString(card.media_url);
      out[i] = fresh && fresh !== card.media_url ? { ...card, media_url: fresh } : card;
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, () => worker()));
  return out;
}

function synthesizeThumbFromMedia(mediaUrl: string | null | undefined): string | null {
  if (!mediaUrl) return null;
  const raw = String(mediaUrl);
  const patterns = [
    /[Ll]ong[Ff]orm\/[^/"'\\]+\/([A-Za-z0-9_-]{6,20})(?:\/|\.mp4|"|'|\?|$)/,
    /[Ll]ong[Ff]orm%2F[^/%]+%2F([A-Za-z0-9_-]{6,20})/,
  ];
  for (const re of patterns) {
    const m = raw.match(re);
    if (!m?.[1]) continue;
    const id = m[1];
    // TikTok spark folders are long pure digit ids — not YouTube posters.
    if (id.length >= 15 && /^\d+$/.test(id)) continue;
    if (id.length >= 6 && id.length <= 20) {
      return `https://i.ytimg.com/vi/${id}/hqdefault.jpg`;
    }
  }
  return null;
}

function rowToCard(row: RawPostRow, slug: HubParentSlug): ThinShelfCard {
  // Capture origin BEFORE stripping stamps — feed comments need this.
  const stampSid = originSidFromBody(row.body);
  const dbShared =
    row.shared_post_id && String(row.shared_post_id).trim()
      ? String(row.shared_post_id).trim()
      : null;
  const originSid =
    stampSid && stampSid !== row.id
      ? stampSid
      : dbShared && dbShared !== row.id
        ? dbShared
        : null;

  // Strip internal markers from body for thin cards (keep short).
  let body = row.body ?? '';
  if (body.includes('__')) {
    body = body
      .split('\n')
      .filter((line) => !line.trim().startsWith('__'))
      .join('\n')
      .trim();
  }
  if (body.length > 180) body = body.slice(0, 177) + '…';

  const thumb =
    (row.thumb_url && String(row.thumb_url).trim()) ||
    synthesizeThumbFromMedia(row.media_url) ||
    null;

  return {
    id: row.id,
    slug,
    title: row.title,
    body: body || null,
    media_type: row.media_type || 'video',
    media_url: row.media_url,
    thumb_url: thumb,
    like_count: Number(row.like_count) || 0,
    comment_count: Number(row.comment_count) || 0,
    created_at: toIso(row.created_at),
    country_code: row.country_code,
    country_name: row.country_name,
    author_id: row.author_id,
    author_name: row.author_name,
    author_username: row.author_username,
    author_avatar: row.author_avatar,
    shared_post_id: originSid,
    origin_sid: originSid,
  };
}

async function queryVideoPage(opts: {
  limit: number;
  cursor?: string | null;
  /** When hub_slug column exists, push filter into SQL. */
  sqlSlug?: string | null;
}): Promise<RawPostRow[]> {
  const limit = Math.min(Math.max(opts.limit || 40, 1), 120);
  const cur = decodeCursor(opts.cursor);
  const hasCol = await hasHubSlugColumn();

  const slugSelect = hasCol ? 'p.hub_slug' : 'null::text as hub_slug';
  const params: unknown[] = [];
  // Hubs shelves = long-form first. Keep reel/spark out of thin Hubs pages
  // (Sparks have their own surface). Still allow video rows that are long-form.
  let where = `
    p.visibility = 'public'
    and lower(coalesce(p.media_type, '')) = 'video'
    and p.media_url is not null
    and length(trim(p.media_url)) > 8
    and lower(coalesce(p.body, '')) not like '%__story__%'
    and lower(coalesce(p.body, '')) not like '%__spark__%'
    and lower(coalesce(p.media_type, '')) not in ('story', 'moment', 'reel', 'spark')
  `;

  if (hasCol && opts.sqlSlug) {
    params.push(normalizeParentSlug(opts.sqlSlug));
    where += ` and (
      lower(coalesce(p.hub_slug, '')) = $${params.length}
      or lower(coalesce(p.hub_slug, '')) like $${params.length} || '\\_%'
    )`;
  }

  if (cur) {
    params.push(cur.createdAt, cur.id);
    where += ` and (p.created_at, p.id) < ($${params.length - 1}::timestamptz, $${params.length}::uuid)`;
  }

  params.push(limit);
  const sql = `
    select
      p.id,
      p.title,
      p.body,
      p.media_type,
      p.media_url,
      p.thumb_url,
      p.like_count,
      p.comment_count,
      p.created_at,
      p.country_code,
      p.country_name,
      p.author_id,
      p.shared_post_id,
      ${slugSelect},
      pr.display_name as author_name,
      pr.username as author_username,
      pr.avatar_url as author_avatar
    from public.posts p
    left join public.profiles pr on pr.user_id = p.author_id
    where ${where}
    order by p.created_at desc, p.id desc
    limit $${params.length}
  `;

  const { rows } = await pool.query<RawPostRow>(sql, params);
  return rows;
}

function classifyRow(row: RawPostRow): HubParentSlug {
  return classifyHubSlug({
    title: row.title,
    body: row.body,
    seedSlug: row.hub_slug,
    creator: row.author_name ?? row.author_username,
  });
}

/**
 * One shelf page for a parent slug (chip).
 * Scans video posts with cursor until `limit` matches (or stream ends).
 */
export async function fetchShelfPage(input: {
  slug: string;
  limit?: number;
  cursor?: string | null;
}): Promise<ShelfPage> {
  const slug = normalizeParentSlug(input.slug);
  const want = Math.min(Math.max(Number(input.limit) || 20, 1), 40);
  const hasCol = await hasHubSlugColumn();

  const items: ThinShelfCard[] = [];
  let cursor = input.cursor ?? null;
  let guard = 0;
  // SQL filter only helps when hub_slug is filled. If column exists but is empty,
  // SQL returns zero rows forever — fall back to classify scan (pre-migration path).
  let useSqlSlug = hasCol;
  let didClassifyFallback = false;

  while (items.length < want && guard < 8) {
    guard += 1;
    // Over-fetch so classification still fills the page when SQL can't filter.
    const batchSize = useSqlSlug ? want * 2 : Math.max(want * 4, 48);
    const rows = await queryVideoPage({
      limit: batchSize,
      cursor,
      sqlSlug: useSqlSlug ? slug : null,
    });
    if (rows.length === 0) {
      if (useSqlSlug && !didClassifyFallback && items.length === 0 && !input.cursor) {
        // Column present but unfilled / wrong density — classify path.
        useSqlSlug = false;
        didClassifyFallback = true;
        cursor = null;
        guard = 0;
        continue;
      }
      cursor = null;
      break;
    }

    for (const row of rows) {
      const rowSlug = classifyRow(row);
      cursor = encodeCursor(toIso(row.created_at), row.id);
      if (rowSlug !== slug) continue;
      items.push(rowToCard(row, rowSlug));
      if (items.length >= want) break;
    }

    // SQL path returned rows but none matched parent after classify → also fall back once.
    if (
      useSqlSlug &&
      !didClassifyFallback &&
      items.length === 0 &&
      !input.cursor &&
      guard >= 2
    ) {
      useSqlSlug = false;
      didClassifyFallback = true;
      cursor = null;
      guard = 0;
      continue;
    }

    if (rows.length < batchSize) break;
  }

  const nextCursor =
    items.length >= want && cursor
      ? cursor
      : items.length > 0 && cursor
        ? cursor
        : null;

  // Live signed media_url so iOS never opens a 403 public r2.dev link from shelves.
  const liveItems = await freshenCardMedia(items);
  return {
    slug,
    items: liveItems,
    nextCursor: items.length > 0 ? nextCursor : null,
    count: liveItems.length,
  };
}

/**
 * For you — round-robin parent slugs, unviewed-agnostic on server
 * (client still demotes viewed). Thin page only.
 */
export async function fetchForYouPage(input: {
  limit?: number;
  cursor?: string | null;
  session?: string | null;
}): Promise<ForYouPage> {
  const want = Math.min(Math.max(Number(input.limit) || 20, 1), 40);
  const session =
    String(input.session ?? '').trim().slice(0, 64) ||
    `s${Date.now().toString(36)}`;

  // Rotate slug order by session hash for variety across opens.
  let order = [...HUB_PARENT_SLUGS];
  let seed = 0;
  for (let i = 0; i < session.length; i++) seed = (seed * 31 + session.charCodeAt(i)) >>> 0;
  if (order.length > 1) {
    const rot = seed % order.length;
    order = [...order.slice(rot), ...order.slice(0, rot)];
  }

  // Pull a modest candidate window once, then RR.
  const batch = await queryVideoPage({
    limit: Math.min(want * 6, 100),
    cursor: input.cursor,
  });

  const buckets = new Map<string, ThinShelfCard[]>();
  let lastCursor: string | null = null;
  for (const row of batch) {
    const slug = classifyRow(row);
    lastCursor = encodeCursor(toIso(row.created_at), row.id);
    const list = buckets.get(slug) ?? [];
    list.push(rowToCard(row, slug));
    buckets.set(slug, list);
  }

  const queues = new Map<string, ThinShelfCard[]>();
  for (const s of order) {
    const q = buckets.get(s);
    if (q?.length) queues.set(s, [...q]);
  }
  // Unknown slugs (shouldn't happen) at end.
  for (const [s, q] of buckets) {
    if (!queues.has(s) && q.length) queues.set(s, [...q]);
  }

  const items: ThinShelfCard[] = [];
  const slugsUsed = new Set<string>();
  let progressed = true;
  while (items.length < want && progressed) {
    progressed = false;
    for (const s of order) {
      const q = queues.get(s);
      if (!q?.length) continue;
      const next = q.shift()!;
      items.push(next);
      slugsUsed.add(s);
      progressed = true;
      if (items.length >= want) break;
    }
  }

  const liveItems = await freshenCardMedia(items);
  return {
    surface: 'hubs_for_you',
    items: liveItems,
    nextCursor: lastCursor,
    slugsUsed: [...slugsUsed],
    count: liveItems.length,
    session,
  };
}

/** Neighbor parent slug for warm (next in hub order). */
export function neighborSlug(slug: string): HubParentSlug {
  const s = normalizeParentSlug(slug);
  const i = HUB_PARENT_SLUGS.indexOf(s);
  if (i < 0) return 'daily';
  return HUB_PARENT_SLUGS[(i + 1) % HUB_PARENT_SLUGS.length];
}

export type SurfacePage = {
  surface: string;
  items: ThinShelfCard[];
  nextCursor: string | null;
  count: number;
};

/**
 * Home feed thin page — all public posts (text/image/video), cursor by created_at.
 * Client ranks; server only pages cheap rows.
 */
export async function fetchHomeFeedPage(input: {
  limit?: number;
  cursor?: string | null;
}): Promise<SurfacePage> {
  const want = Math.min(Math.max(Number(input.limit) || 24, 1), 48);
  const cur = decodeCursor(input.cursor);
  const hasCol = await hasHubSlugColumn();
  const slugSelect = hasCol ? 'p.hub_slug' : 'null::text as hub_slug';
  const params: unknown[] = [];
  let where = `
    p.visibility = 'public'
    and lower(coalesce(p.media_type, '')) not in ('story', 'moment')
    and lower(coalesce(p.body, '')) not like '%__story__%'
  `;
  if (cur) {
    params.push(cur.createdAt, cur.id);
    where += ` and (p.created_at, p.id) < ($${params.length - 1}::timestamptz, $${params.length}::uuid)`;
  }
  params.push(want);
  const sql = `
    select
      p.id, p.title, p.body, p.media_type, p.media_url, p.thumb_url,
      p.like_count, p.comment_count, p.created_at, p.country_code, p.country_name,
      p.author_id, p.shared_post_id, ${slugSelect},
      pr.display_name as author_name, pr.username as author_username, pr.avatar_url as author_avatar
    from public.posts p
    left join public.profiles pr on pr.user_id = p.author_id
    where ${where}
    order by p.created_at desc, p.id desc
    limit $${params.length}
  `;
  const { rows } = await pool.query<RawPostRow>(sql, params);
  const items = rows.map((row) => rowToCard(row, classifyRow(row)));
  const last = rows[rows.length - 1];
  const nextCursor = last
    ? encodeCursor(toIso(last.created_at), last.id)
    : null;
  return {
    surface: 'home_for_you',
    items,
    nextCursor: items.length >= want ? nextCursor : null,
    count: items.length,
  };
}

/**
 * Sparks thin page — reels/sparks only, optional slug filter.
 */
export async function fetchSparksPage(input: {
  limit?: number;
  cursor?: string | null;
  slug?: string | null;
}): Promise<SurfacePage> {
  const want = Math.min(Math.max(Number(input.limit) || 20, 1), 40);
  const focus = input.slug ? normalizeParentSlug(input.slug) : null;
  const cur = decodeCursor(input.cursor);
  const hasCol = await hasHubSlugColumn();
  const slugSelect = hasCol ? 'p.hub_slug' : 'null::text as hub_slug';
  const params: unknown[] = [];
  let where = `
    p.visibility = 'public'
    and lower(coalesce(p.media_type, '')) in ('reel', 'spark', 'video')
    and p.media_url is not null
    and length(trim(p.media_url)) > 8
    and lower(coalesce(p.body, '')) not like '%__story__%'
    and (
      lower(coalesce(p.media_type, '')) in ('reel', 'spark')
      or lower(coalesce(p.body, '')) like '%__spark__%'
    )
  `;
  if (hasCol && focus) {
    params.push(focus);
    where += ` and (
      lower(coalesce(p.hub_slug, '')) = $${params.length}
      or lower(coalesce(p.hub_slug, '')) like $${params.length} || '\\_%'
    )`;
  }
  if (cur) {
    params.push(cur.createdAt, cur.id);
    where += ` and (p.created_at, p.id) < ($${params.length - 1}::timestamptz, $${params.length}::uuid)`;
  }
  // Over-fetch when classifying in memory for slug focus.
  params.push(focus && !hasCol ? want * 4 : want);
  const sql = `
    select
      p.id, p.title, p.body, p.media_type, p.media_url, p.thumb_url,
      p.like_count, p.comment_count, p.created_at, p.country_code, p.country_name,
      p.author_id, p.shared_post_id, ${slugSelect},
      pr.display_name as author_name, pr.username as author_username, pr.avatar_url as author_avatar
    from public.posts p
    left join public.profiles pr on pr.user_id = p.author_id
    where ${where}
    order by p.created_at desc, p.id desc
    limit $${params.length}
  `;
  const { rows } = await pool.query<RawPostRow>(sql, params);
  const items: ThinShelfCard[] = [];
  let lastCursor: string | null = null;
  for (const row of rows) {
    const slug = classifyRow(row);
    lastCursor = encodeCursor(toIso(row.created_at), row.id);
    if (focus && slug !== focus) continue;
    // Prefer short/reel-ish; still accept tagged sparks.
    items.push(rowToCard(row, slug));
    if (items.length >= want) break;
  }
  return {
    surface: focus ? `sparks:${focus}` : 'sparks',
    items,
    nextCursor: lastCursor,
    count: items.length,
  };
}
