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
import { freshenMediaUrlString, freshenThumbUrlString } from '../media/r2-playback.js';
import {
  adultContentSqlFilter,
  rebrandCompetitorNames,
  textLooksNsfw,
  viewerIsUnder18,
} from '../moderation/nsfw.js';
import {
  canonicalVideoKey,
  loadCommittedBatch,
  loadDeliveredCanonicalKeys,
  orderRowsByIds,
  reserveDeliveryBatch,
} from './delivery.service.js';
import { rankCandidates } from './rank.service.js';

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
  /** Present when API selects it — R2 sync bumps this so feed can float updates. */
  updated_at?: string;
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
  /** 18+ / NSFW — hidden from under-18 accounts. */
  is_adult?: boolean;
  moderation_status?: string | null;
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
  batchId?: string | null;
  deliveryPolicy?: 'ledger' | 'cursor';
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
  updated_at?: Date | string | null;
  /** greatest(updated_at, created_at) when selected for home feed ranking. */
  feed_at?: Date | string | null;
  country_code: string | null;
  country_name: string | null;
  author_id: string;
  hub_slug: string | null;
  shared_post_id: string | null;
  author_name: string | null;
  author_username: string | null;
  author_avatar: string | null;
  moderation_status?: string | null;
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

/** Re-presign media_url + Frame 0 thumb_url (+ nested posters) so clients never open dead/403 R2 links. */
async function freshenCardMedia(items: ThinShelfCard[]): Promise<ThinShelfCard[]> {
  if (!items.length) return items;
  // Higher concurrency — feed pages were spending multi-seconds on serial-ish R2 re-sign.
  const concurrency = 12;
  const out: ThinShelfCard[] = new Array(items.length);
  let idx = 0;
  async function worker() {
    while (idx < items.length) {
      const i = idx++;
      const card = items[i];
      let next = card;
      const fresh = await freshenMediaUrlString(card.media_url);
      if (fresh) {
        next = { ...next, media_url: fresh };
      }
      // Live Frame 0: re-presign thumb, or mint from media_url pack key when missing.
      const liveThumb = await freshenThumbUrlString(next.thumb_url, null, next.media_url);
      if (liveThumb) {
        next = { ...next, thumb_url: liveThumb };
      }
      // Nested media_url.posters ladder often still carries Aug-expired embeds — refresh in place.
      const withPosters = await freshenEmbeddedPosters(next.media_url);
      if (withPosters) {
        next = { ...next, media_url: withPosters };
      }
      out[i] = next;
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, items.length) }, () => worker()));
  return out;
}

/** Re-sign media_url JSON `posters.{256|512|1080}` when present (expired embeds → 403 on device). */
async function freshenEmbeddedPosters(mediaUrl: string | null | undefined): Promise<string | null> {
  if (!mediaUrl) return null;
  const raw = String(mediaUrl).trim();
  if (!raw.startsWith('{')) return null;
  try {
    const obj = JSON.parse(raw) as Record<string, unknown>;
    const posters = obj.posters;
    if (!posters || typeof posters !== 'object') return null;
    const nextPosters: Record<string, string> = {
      ...(posters as Record<string, string>),
    };
    let changed = false;
    for (const key of ['1080', '512', '256'] as const) {
      const cur = nextPosters[key];
      if (!cur) continue;
      const live = await freshenThumbUrlString(cur, null, raw);
      if (live && live !== cur) {
        nextPosters[key] = live;
        changed = true;
      }
    }
    if (!changed) return null;
    obj.posters = nextPosters;
    obj.signed_at = new Date().toISOString();
    return JSON.stringify(obj);
  } catch {
    return null;
  }
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

  const createdIso = toIso(row.created_at);
  // Real updated_at only — never map feed_at here (that made every bumped post show "Edited").
  const updatedIso =
    row.updated_at != null ? toIso(row.updated_at) : createdIso;
  const status = String(row.moderation_status ?? 'active').toLowerCase();
  const isAdult =
    status === 'sensitive' || textLooksNsfw(row.title, row.body, body);
  return {
    id: row.id,
    slug,
    title: rebrandCompetitorNames(row.title),
    body: rebrandCompetitorNames(body || null),
    // Preserve none/text/image — defaulting to 'video' hid written posts on thin cards.
    media_type: row.media_type || 'none',
    media_url: row.media_url,
    thumb_url: thumb,
    like_count: Number(row.like_count) || 0,
    comment_count: Number(row.comment_count) || 0,
    created_at: createdIso,
    updated_at: updatedIso,
    country_code: row.country_code,
    country_name: row.country_name,
    author_id: row.author_id,
    author_name: row.author_name,
    author_username: row.author_username,
    author_avatar: row.author_avatar,
    shared_post_id: originSid,
    origin_sid: originSid,
    is_adult: isAdult,
    moderation_status: status,
  };
}

async function queryVideoPage(opts: {
  limit: number;
  cursor?: string | null;
  /** When hub_slug column exists, push filter into SQL. */
  sqlSlug?: string | null;
}): Promise<RawPostRow[]> {
  // Cap high enough for For-you over-fetch (want*10) while classify fills sparse chips.
  const limit = Math.min(Math.max(opts.limit || 40, 1), 200);
  const cur = decodeCursor(opts.cursor);
  const hasCol = await hasHubSlugColumn();

  const slugSelect = hasCol ? 'p.hub_slug' : 'null::text as hub_slug';
  const params: unknown[] = [];
  // Hubs shelves = long-form video. Keep reel/spark out (Sparks have their own surface).
  // Index-friendly created_at walk — same fix as home feed (greatest() scanned multi-seconds).
  let where = `
    p.visibility = 'public'
    and p.media_type = 'video'
    and p.media_url is not null
    and length(trim(p.media_url)) > 8
    and coalesce(p.body, '') not ilike '%__story__%'
    and coalesce(p.body, '') not ilike '%__spark__%'
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
      p.updated_at,
      p.created_at as feed_at,
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

  try {
    const timed = await Promise.race([
      pool.query<RawPostRow>(sql, params),
      new Promise<'timeout'>((resolve) => setTimeout(() => resolve('timeout'), 7000)),
    ]);
    if (timed === 'timeout') {
      console.error('[hubs] queryVideoPage timed out after 7s');
      return [];
    }
    return timed.rows;
  } catch (err: any) {
    console.error('[hubs] queryVideoPage failed', err?.message ?? err);
    return [];
  }
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
  const want = Math.min(Math.max(Number(input.limit) || 36, 1), 48);
  const hasCol = await hasHubSlugColumn();

  const items: ThinShelfCard[] = [];
  const seen = new Set<string>();
  let cursor = input.cursor ?? null;
  let guard = 0;
  // SQL filter only helps when hub_slug is filled. If column exists but is empty,
  // SQL returns zero rows forever — fall back to classify scan (pre-migration path).
  let useSqlSlug = hasCol;
  let didClassifyFallback = false;

  while (items.length < want && guard < 16) {
    guard += 1;
    // Over-fetch so classification still fills chips when hub_slug is sparse/unfilled.
    const batchSize = useSqlSlug ? Math.max(want * 4, 64) : Math.max(want * 8, 120);
    const rows = await queryVideoPage({
      limit: batchSize,
      cursor,
      sqlSlug: useSqlSlug ? slug : null,
    });
    if (rows.length === 0) {
      if (useSqlSlug && !didClassifyFallback && items.length < want && !input.cursor) {
        // Column present but thin/unfilled for this chip — classify path over the library.
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
      if (seen.has(row.id)) continue;
      seen.add(row.id);
      items.push(rowToCard(row, rowSlug));
      if (items.length >= want) break;
    }

    // SQL hub_slug filter returned a thin chip → classify-scan the broader library once.
    if (
      useSqlSlug &&
      !didClassifyFallback &&
      items.length < want &&
      !input.cursor &&
      guard >= 1
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
  viewerUserId?: string | null;
  idempotencyKey?: string | null;
}): Promise<ForYouPage> {
  const want = Math.min(Math.max(Number(input.limit) || 36, 1), 48);
  const session =
    String(input.session ?? '').trim().slice(0, 64) ||
    `s${Date.now().toString(36)}`;
  const viewerId = input.viewerUserId ? String(input.viewerUserId).trim() : '';
  const idem =
    String(input.idempotencyKey ?? '').trim().slice(0, 128) || null;

  if (viewerId && idem) {
    const prior = await loadCommittedBatch(viewerId, 'hubs_for_you', idem);
    if (prior?.videoIds.length) {
      const rows = await loadRawPostsByIds(prior.videoIds);
      const items = orderRowsByIds(rows, prior.videoIds).map((row) =>
        rowToCard(row, classifyRow(row))
      );
      const liveItems = await freshenCardMedia(items);
      return {
        surface: 'hubs_for_you',
        items: liveItems,
        nextCursor: input.cursor ?? null,
        slugsUsed: [...new Set(liveItems.map((i) => i.slug))],
        count: liveItems.length,
        session,
        batchId: prior.batchId,
        deliveryPolicy: 'ledger',
      };
    }
  }

  // Rotate slug order by session hash for variety across opens.
  let order = [...HUB_PARENT_SLUGS];
  let seed = 0;
  for (let i = 0; i < session.length; i++) seed = (seed * 31 + session.charCodeAt(i)) >>> 0;
  if (order.length > 1) {
    const rot = seed % order.length;
    order = [...order.slice(rot), ...order.slice(0, rot)];
  }

  // Large candidate window so round-robin can fill dense pages from the R2 long-form library.
  const batch = await queryVideoPage({
    limit: Math.min(want * (viewerId ? 14 : 10), 220),
    cursor: input.cursor,
  });

  const buckets = new Map<string, RawPostRow[]>();
  let lastCursor: string | null = null;
  for (const row of batch) {
    const slug = classifyRow(row);
    lastCursor = encodeCursor(toIso(row.created_at), row.id);
    const list = buckets.get(slug) ?? [];
    list.push(row);
    buckets.set(slug, list);
  }

  const queues = new Map<string, RawPostRow[]>();
  for (const s of order) {
    const q = buckets.get(s);
    if (q?.length) queues.set(s, [...q]);
  }
  for (const [s, q] of buckets) {
    if (!queues.has(s) && q.length) queues.set(s, [...q]);
  }

  const woven: RawPostRow[] = [];
  const slugsUsed = new Set<string>();
  let progressed = true;
  const candidateWant = viewerId ? Math.min(want * 3, 96) : want;
  while (woven.length < candidateWant && progressed) {
    progressed = false;
    for (const s of order) {
      const q = queues.get(s);
      if (!q?.length) continue;
      const next = q.shift()!;
      woven.push(next);
      slugsUsed.add(s);
      progressed = true;
      if (woven.length >= candidateWant) break;
    }
  }

  let servedRows = woven.slice(0, want);
  let batchId: string | null = null;
  let deliveryPolicy: 'ledger' | 'cursor' = 'cursor';

  if (viewerId && woven.length) {
    const delivered = await loadDeliveredCanonicalKeys(viewerId, 'hubs_for_you');
    let eligible = woven.filter((row) => !delivered.has(canonicalVideoKey(row)));
    eligible = dedupeHomeMediaRows(eligible);

    if (eligible.length) {
      let rankedIds = eligible.map((r) => r.id);
      try {
        const ranked = await rankCandidates({
          entityId: viewerId,
          surface: 'hubs_for_you',
          candidateIds: rankedIds,
          sessionId: session,
          limit: Math.min(eligible.length, want * 2),
        });
        if (ranked.items.length) rankedIds = ranked.items.map((i) => i.id);
      } catch (err: any) {
        console.warn('[hubs/for-you] rankCandidates failed', err?.message ?? err);
      }

      const byId = new Map(eligible.map((r) => [r.id, r]));
      const rankedRows = rankedIds
        .map((id) => byId.get(id))
        .filter((r): r is RawPostRow => !!r);

      const reserved = await reserveDeliveryBatch({
        userId: viewerId,
        surface: 'hubs_for_you',
        idempotencyKey:
          idem || `hubs:${session}:${Date.now()}:${Math.random().toString(36).slice(2, 8)}`,
        candidates: rankedRows.map((r) => ({
          id: r.id,
          canonicalKey: canonicalVideoKey(r),
        })),
        limit: want,
      });

      if (reserved && reserved.videoIds.length) {
        servedRows = orderRowsByIds(rankedRows, reserved.videoIds);
        batchId = reserved.batchId;
        deliveryPolicy = 'ledger';
      } else {
        servedRows = rankedRows.slice(0, want);
      }
    } else {
      servedRows = [];
    }
  }

  const items = servedRows.map((row) => rowToCard(row, classifyRow(row)));
  const liveItems = await freshenCardMedia(items);
  return {
    surface: 'hubs_for_you',
    items: liveItems,
    nextCursor: lastCursor,
    slugsUsed: [...slugsUsed],
    count: liveItems.length,
    session,
    batchId,
    deliveryPolicy,
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
  batchId?: string | null;
  deliveryPolicy?: 'ledger' | 'cursor';
};

/** Four-lane cursor: spark / hub / image / text page independently on Home. */
type HomeLaneCursor = { createdAt: string; id: string } | null;
type HomeFeedCursor = {
  spark: HomeLaneCursor;
  hub: HomeLaneCursor;
  image: HomeLaneCursor;
  text: HomeLaneCursor;
};

function encodeHomeFeedCursor(cur: HomeFeedCursor): string | null {
  const lanes: HomeLaneCursor[] = [cur.spark, cur.hub, cur.image, cur.text];
  if (lanes.every((l) => !l)) return null;
  // v3|sparkAt|sparkId|hubAt|hubId|imageAt|imageId|textAt|textId
  const parts = ['v3'];
  for (const lane of lanes) {
    parts.push(lane?.createdAt ?? '-', lane?.id ?? '-');
  }
  return Buffer.from(parts.join('|'), 'utf8').toString('base64url');
}

function laneFromParts(at: string | undefined, id: string | undefined): HomeLaneCursor {
  if (!at || !id || at === '-' || id === '-') return null;
  return { createdAt: at, id };
}

function decodeHomeFeedCursor(cursor: string | null | undefined): HomeFeedCursor {
  const empty: HomeFeedCursor = { spark: null, hub: null, image: null, text: null };
  if (!cursor) return empty;
  try {
    const raw = Buffer.from(String(cursor), 'base64url').toString('utf8');
    if (raw.startsWith('v3|')) {
      const parts = raw.split('|');
      // v3 + 8 fields
      if (parts.length >= 9) {
        return {
          spark: laneFromParts(parts[1], parts[2]),
          hub: laneFromParts(parts[3], parts[4]),
          image: laneFromParts(parts[5], parts[6]),
          text: laneFromParts(parts[7], parts[8]),
        };
      }
    }
    if (raw.startsWith('v2|')) {
      const parts = raw.split('|');
      // v2 media+text → map media→spark, text→image (compat while clients refresh).
      if (parts.length >= 5) {
        return {
          spark: laneFromParts(parts[1], parts[2]),
          hub: null,
          image: laneFromParts(parts[3], parts[4]),
          text: null,
        };
      }
    }
  } catch {
    /* fall through to legacy */
  }
  const legacy = decodeCursor(cursor);
  return { ...empty, spark: legacy };
}

type HomeLaneKind = 'spark' | 'hub' | 'image' | 'text';

function isHomeImageRow(row: RawPostRow): boolean {
  const mt = String(row.media_type ?? '')
    .trim()
    .toLowerCase();
  return mt === 'image' || mt === 'photo' || mt === 'gif';
}

function isHomeTextRow(row: RawPostRow): boolean {
  const mt = String(row.media_type ?? '')
    .trim()
    .toLowerCase();
  if (mt === 'none' || mt === 'text') return true;
  if (mt === 'image' || mt === 'photo' || mt === 'gif') return false;
  if (mt === 'video' || mt === 'reel' || mt === 'spark' || mt === 'story' || mt === 'moment') {
    return false;
  }
  const media = row.media_url;
  if (media == null || String(media).trim() === '') {
    const body = String(row.body ?? '').trim();
    const title = String(row.title ?? '').trim();
    return body.length > 0 || title.length > 0;
  }
  return false;
}

/** ShortForm / spark stamps — never LongForm hubs. */
function mediaLooksSpark(row: RawPostRow): boolean {
  const mt = String(row.media_type ?? '')
    .trim()
    .toLowerCase();
  if (mt === 'reel' || mt === 'spark') return true;
  const body = String(row.body ?? '').toLowerCase();
  if (body.includes('__spark__') || body.includes('__spark_share__')) return true;
  const blob = `${row.media_url ?? ''}`.toLowerCase();
  if (blob.includes('/longform/')) return false;
  if (blob.includes('/shortform/')) return true;
  return false;
}

/** LongForm / hub stamps — never Sparks ShortForm. */
function mediaLooksHub(row: RawPostRow): boolean {
  const body = String(row.body ?? '').toLowerCase();
  if (body.includes('__spark__') || body.includes('__spark_share__')) return false;
  if (body.includes('__hub_origin__') || body.includes('__hub_channel__')) return true;
  const blob = `${row.media_url ?? ''}`.toLowerCase();
  if (blob.includes('/shortform/')) return false;
  if (blob.includes('/longform/')) return true;
  return false;
}

const HOME_FEED_SELECT = (slugSelect: string) => `
      p.id, p.title, p.body, p.media_type, p.media_url, p.thumb_url,
      p.like_count, p.comment_count, p.created_at, p.updated_at,
      p.created_at as feed_at,
      p.country_code, p.country_name,
      p.author_id, p.shared_post_id, ${slugSelect},
      coalesce(p.moderation_status, 'active') as moderation_status,
      pr.display_name as author_name, pr.username as author_username, pr.avatar_url as author_avatar
`;

async function fetchHomeLaneRows(opts: {
  kind: HomeLaneKind;
  limit: number;
  cursor: HomeLaneCursor;
  slugSelect: string;
  under18: boolean;
}): Promise<RawPostRow[]> {
  const want = Math.min(Math.max(opts.limit, 1), 32);
  const params: unknown[] = [];
  const adult = adultContentSqlFilter(opts.under18, 'p');
  let where = `
    p.visibility = 'public'
    and coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted')
    and coalesce(p.body, '') not ilike '%__story__%'
    ${adult}
  `;

  if (opts.kind === 'spark') {
    where += `
      and p.media_type in ('video', 'reel', 'spark')
      and p.media_url is not null
      and length(trim(p.media_url)) > 8
      and coalesce(p.media_path, '') not like '%/LongForm/%'
      and p.media_url::text not ilike '%/LongForm/%'
      and (
        p.media_type in ('reel', 'spark')
        or coalesce(p.media_path, '') like '%/ShortForm/%'
        or p.media_url::text ilike '%/ShortForm/%'
        or coalesce(p.body, '') ilike '%__spark__%'
      )
    `;
  } else if (opts.kind === 'hub') {
    where += `
      and p.media_type = 'video'
      and p.media_url is not null
      and length(trim(p.media_url)) > 8
      and coalesce(p.body, '') not ilike '%__spark__%'
      and (
        coalesce(p.media_path, '') like '%/LongForm/%'
        or p.media_url::text ilike '%/LongForm/%'
        or coalesce(p.body, '') ilike '%__hub_origin__%'
        or coalesce(p.body, '') ilike '%__hub_channel__%'
      )
    `;
  } else if (opts.kind === 'image') {
    // Over-fetch a bit — caller dedupes near-identical media/captions.
    where += `
      and lower(coalesce(p.media_type, '')) in ('image', 'photo', 'gif')
      and p.media_url is not null
      and length(trim(p.media_url)) > 4
      and coalesce(p.body, '') not ilike '%__spark__%'
      and coalesce(p.body, '') not ilike '%__hub_origin__%'
    `;
  } else {
    // Pure text / status posts — never video or image cards.
    // Drop DE/AT forum corpus from Home (German/Austrian written source).
    where += `
      and lower(coalesce(p.media_type, '')) not in ('story', 'moment', 'video', 'reel', 'spark', 'image', 'photo', 'gif')
      and coalesce(p.body, '') not ilike '%__spark__%'
      and coalesce(p.body, '') not ilike '%__hub_origin__%'
      and upper(coalesce(p.country_code, '')) not in ('DE', 'AT')
      and (
        lower(coalesce(p.media_type, '')) in ('none', 'text')
        or (
          (p.media_url is null or length(trim(coalesce(p.media_url, ''))) < 4)
          and (
            length(trim(coalesce(p.body, ''))) > 0
            or length(trim(coalesce(p.title, ''))) > 0
          )
        )
      )
    `;
  }

  if (opts.cursor) {
    params.push(opts.cursor.createdAt, opts.cursor.id);
    where += ` and (p.created_at, p.id) < ($${params.length - 1}::timestamptz, $${params.length}::uuid)`;
  }
  params.push(want);
  const sql = `
    select ${HOME_FEED_SELECT(opts.slugSelect)}
    from public.posts p
    left join public.profiles pr on pr.user_id = p.author_id
    where ${where}
    order by p.created_at desc, p.id desc
    limit $${params.length}
  `;
  const { rows } = await pool.query<RawPostRow>(sql, params);
  return rows;
}

function advanceLaneCursor(
  rows: RawPostRow[],
  consumed: number,
  prior: HomeLaneCursor
): HomeLaneCursor {
  if (consumed <= 0) return prior;
  const last = rows[Math.min(consumed, rows.length) - 1];
  if (!last) return prior;
  return { createdAt: toIso(last.created_at), id: last.id };
}

/** Collapse image re-seeds that share the same file / caption. */
function dedupeHomeImageRows(rows: RawPostRow[]): RawPostRow[] {
  return dedupeHomeMediaRows(rows);
}

/**
 * One card per underlying clip. Pipeline seeds original + feed share for the same
 * R2 pack — without this, Home shows the same video from two people a few rows apart.
 * Prefer the share (social context) when both are present.
 */
function dedupeHomeMediaRows(rows: RawPostRow[]): RawPostRow[] {
  const best = new Map<string, RawPostRow>();
  for (const row of rows) {
    const key = homeMediaDedupeKey(row);
    const prev = best.get(key);
    if (!prev) {
      best.set(key, row);
      continue;
    }
    const rowShare = isHomeFeedShareRow(row);
    const prevShare = isHomeFeedShareRow(prev);
    if (rowShare && !prevShare) best.set(key, row);
  }
  return [...best.values()];
}

function isHomeFeedShareRow(row: RawPostRow): boolean {
  if (row.shared_post_id && String(row.shared_post_id).trim()) return true;
  const body = String(row.body ?? '');
  return (
    body.includes('__spark__') ||
    body.includes('__hub_origin__') ||
    body.includes('__shared_post__')
  );
}

function homeImageDedupeKey(row: RawPostRow): string {
  return homeMediaDedupeKey(row);
}

/** Stable identity for the underlying media file / share origin. */
function homeMediaDedupeKey(row: RawPostRow): string {
  const media = String(row.media_url ?? '');
  const r2 = media.match(/"r2_key"\s*:\s*"([^"]+)"/i)?.[1];
  if (r2) return `r2:${r2.toLowerCase()}`;
  const shared = String(row.shared_post_id ?? '').trim();
  if (shared) return `clip:${shared.toLowerCase()}`;
  const url = media.match(/https?:\/\/[^"'\\\s?]+/i)?.[0];
  if (url) {
    const bare = url.toLowerCase().split('?')[0];
    if (
      bare.includes('.mp4') ||
      bare.includes('/shortform/') ||
      bare.includes('/longform/') ||
      bare.includes('image') ||
      bare.includes('.jpg') ||
      bare.includes('.png') ||
      bare.includes('.webp')
    ) {
      return `url:${bare}`;
    }
  }
  const mt = String(row.media_type ?? '').toLowerCase();
  if (mt === 'video' || mt === 'reel' || mt === 'spark' || mt === 'image' || mt === 'photo' || mt === 'gif') {
    // Originals key by id so a later share (shared_post_id=this id) collapses onto them.
    return `clip:${String(row.id).toLowerCase()}`;
  }
  const caption = `${row.title ?? ''}\n${row.body ?? ''}`
    .trim()
    .toLowerCase()
    .slice(0, 160);
  if (caption.length >= 12) return `cap:${caption}`;
  return `id:${row.id}`;
}

/** Extra aliases so share+original collide even when one side only has id / shared_post_id. */
function homeMediaAliasKeys(row: RawPostRow): string[] {
  const keys = new Set<string>([homeMediaDedupeKey(row)]);
  const shared = String(row.shared_post_id ?? '').trim().toLowerCase();
  if (shared) keys.add(`clip:${shared}`);
  const mt = String(row.media_type ?? '').toLowerCase();
  if (mt === 'video' || mt === 'reel' || mt === 'spark' || mt === 'image' || mt === 'photo' || mt === 'gif') {
    keys.add(`clip:${String(row.id).toLowerCase()}`);
  }
  const media = String(row.media_url ?? '');
  const r2 = media.match(/"r2_key"\s*:\s*"([^"]+)"/i)?.[1];
  if (r2) keys.add(`r2:${r2.toLowerCase()}`);
  return [...keys];
}

/**
 * Home feed thin page — even mix of Sparks, Hubs, images, and text.
 * Four independent cursors so ShortForm flood never buries LongForm / written.
 * Lanes use created_at (index-friendly).
 */
export async function fetchHomeFeedPage(input: {
  limit?: number;
  cursor?: string | null;
  viewerUserId?: string | null;
  /** Architecture §5 — retry same key returns the committed batch. */
  idempotencyKey?: string | null;
}): Promise<SurfacePage> {
  const want = Math.min(Math.max(Number(input.limit) || 24, 1), 64);
  const viewerId = input.viewerUserId ? String(input.viewerUserId).trim() : '';
  const idem =
    String(input.idempotencyKey ?? '').trim().slice(0, 128) || null;

  // Authenticated replay of an in-flight/timeout batch.
  if (viewerId && idem) {
    const prior = await loadCommittedBatch(viewerId, 'home_for_you', idem);
    if (prior?.videoIds.length) {
      const rows = await loadRawPostsByIds(prior.videoIds);
      const items = orderRowsByIds(rows, prior.videoIds).map((row) =>
        rowToCard(row, classifyRow(row))
      );
      let liveItems: ThinShelfCard[];
      try {
        liveItems = await freshenCardMedia(items);
      } catch {
        liveItems = items;
      }
      return {
        surface: 'home_for_you',
        items: liveItems,
        nextCursor: input.cursor ?? null,
        count: liveItems.length,
        batchId: prior.batchId,
        deliveryPolicy: 'ledger',
      };
    }
  }

  // Text lane paused — forum/written cards were freezing Home scroll.
  // Mix spark / hub / image only (~1/3 each); over-fetch so pages stay dense after dedupe.
  // Auth path over-fetches more so delivery exclusion still fills `want`.
  const perLane = Math.max(
    4,
    Math.ceil(want / 3) + (viewerId ? 4 : 2)
  );
  const imageLaneWant = perLane + 6;
  const homeCur = decodeHomeFeedCursor(input.cursor);
  const hasCol = await hasHubSlugColumn();
  const slugSelect = hasCol ? 'p.hub_slug' : 'null::text as hub_slug';
  const under18 = await viewerIsUnder18(input.viewerUserId);

  let sparkRows: RawPostRow[] = [];
  let hubRows: RawPostRow[] = [];
  let imageRows: RawPostRow[] = [];
  try {
    const timed = await Promise.race([
      Promise.all([
        fetchHomeLaneRows({
          kind: 'spark',
          limit: perLane,
          cursor: homeCur.spark,
          slugSelect,
          under18,
        }),
        fetchHomeLaneRows({
          kind: 'hub',
          limit: perLane,
          cursor: homeCur.hub,
          slugSelect,
          under18,
        }),
        fetchHomeLaneRows({
          kind: 'image',
          limit: imageLaneWant,
          cursor: homeCur.image,
          slugSelect,
          under18,
        }),
      ]),
      new Promise<'timeout'>((resolve) => setTimeout(() => resolve('timeout'), 7000)),
    ]);
    if (timed === 'timeout') {
      console.error('[feed] three-lane query timed out after 7s');
      return {
        surface: 'home_for_you',
        items: [],
        nextCursor: null,
        count: 0,
      };
    }
    // Collapse original + feed-share of the same R2 clip before weave.
    sparkRows = dedupeHomeMediaRows(timed[0].filter(mediaLooksSpark));
    hubRows = dedupeHomeMediaRows(timed[1].filter(mediaLooksHub));
    imageRows = dedupeHomeImageRows(timed[2].filter(isHomeImageRow));
  } catch (err: any) {
    console.error('[feed] three-lane query failed', err?.message ?? err);
    return {
      surface: 'home_for_you',
      items: [],
      nextCursor: null,
      count: 0,
    };
  }

  // Round-robin: spark → hub → image (text lane off). Build a candidate pool ≥ want.
  const lanes: { kind: HomeLaneKind; rows: RawPostRow[]; i: number }[] = [
    { kind: 'spark', rows: sparkRows, i: 0 },
    { kind: 'hub', rows: hubRows, i: 0 },
    { kind: 'image', rows: imageRows, i: 0 },
  ];
  const candidateWant = viewerId ? Math.min(want * 3, 96) : want;
  const woven: RawPostRow[] = [];
  const seen = new Set<string>();
  const seenMedia = new Set<string>();
  let guard = 0;
  while (woven.length < candidateWant && guard < candidateWant * 4) {
    guard += 1;
    let progressed = false;
    for (const lane of lanes) {
      if (woven.length >= candidateWant) break;
      while (lane.i < lane.rows.length) {
        const row = lane.rows[lane.i++];
        if (seen.has(row.id)) continue;
        // Defense: never weave pure text even if a media lane misclassifies.
        if (isHomeTextRow(row)) continue;
        const aliases = homeMediaAliasKeys(row);
        if (aliases.some((k) => seenMedia.has(k))) continue;
        seen.add(row.id);
        for (const k of aliases) seenMedia.add(k);
        woven.push(row);
        progressed = true;
        break;
      }
    }
    if (!progressed) break;
  }

  let servedRows = woven.slice(0, want);
  let batchId: string | null = null;
  let deliveryPolicy: 'ledger' | 'cursor' = 'cursor';

  if (viewerId && woven.length) {
    const delivered = await loadDeliveredCanonicalKeys(viewerId, 'home_for_you');
    let eligible = woven.filter((row) => {
      const key = canonicalVideoKey(row);
      return !delivered.has(key);
    });
    // Prefer share over original when both somehow remain.
    eligible = dedupeHomeMediaRows(eligible);

    if (eligible.length) {
      let rankedIds = eligible.map((r) => r.id);
      try {
        const ranked = await rankCandidates({
          entityId: viewerId,
          surface: 'home_for_you',
          candidateIds: rankedIds,
          limit: Math.min(eligible.length, want * 2),
        });
        if (ranked.items.length) {
          rankedIds = ranked.items.map((i) => i.id);
        }
      } catch (err: any) {
        console.warn('[feed] rankCandidates failed', err?.message ?? err);
      }

      const byId = new Map(eligible.map((r) => [r.id, r]));
      const rankedRows = rankedIds
        .map((id) => byId.get(id))
        .filter((r): r is RawPostRow => !!r);

      const reserved = await reserveDeliveryBatch({
        userId: viewerId,
        surface: 'home_for_you',
        idempotencyKey: idem || `home:${Date.now()}:${Math.random().toString(36).slice(2, 10)}`,
        candidates: rankedRows.map((r) => ({
          id: r.id,
          canonicalKey: canonicalVideoKey(r),
        })),
        limit: want,
      });

      if (reserved && reserved.videoIds.length) {
        servedRows = orderRowsByIds(rankedRows, reserved.videoIds);
        batchId = reserved.batchId;
        deliveryPolicy = 'ledger';
      } else {
        // Ledger unavailable — still exclude delivered client-side this response.
        servedRows = rankedRows.slice(0, want);
      }
    } else {
      servedRows = [];
    }
  }

  const items = servedRows.map((row) => rowToCard(row, classifyRow(row)));
  let liveItems: ThinShelfCard[];
  try {
    liveItems = await freshenCardMedia(items);
  } catch (err: any) {
    console.error('[feed] freshenCardMedia failed', err?.message ?? err);
    liveItems = items;
  }

  const advanced: HomeFeedCursor = {
    spark: advanceLaneCursor(sparkRows, lanes[0].i, homeCur.spark),
    hub: advanceLaneCursor(hubRows, lanes[1].i, homeCur.hub),
    image: advanceLaneCursor(imageRows, lanes[2].i, homeCur.image),
    // Freeze text cursor — lane paused so old cursors don't resurrect forum rows.
    text: homeCur.text,
  };
  // Keep paging while any active lane still has a full slice or we filled the page.
  const hasMore =
    sparkRows.length >= perLane ||
    hubRows.length >= perLane ||
    imageRows.length >= perLane ||
    liveItems.length >= Math.min(want, 8);

  return {
    surface: 'home_for_you',
    items: liveItems,
    nextCursor: hasMore ? encodeHomeFeedCursor(advanced) : null,
    count: liveItems.length,
    batchId,
    deliveryPolicy,
  };
}

/** Hydrate thin-feed rows by id (idempotent batch replay). */
async function loadRawPostsByIds(ids: string[]): Promise<RawPostRow[]> {
  const clean = [...new Set(ids.map((id) => String(id).trim()).filter(Boolean))].slice(
    0,
    80
  );
  if (!clean.length) return [];
  const hasCol = await hasHubSlugColumn();
  const slugSelect = hasCol ? 'p.hub_slug' : 'null::text as hub_slug';
  try {
    const { rows } = await pool.query<RawPostRow>(
      `
      select
        p.id, p.title, p.body, p.media_type, p.media_url, p.thumb_url,
        p.like_count, p.comment_count, p.created_at, p.updated_at,
        p.country_code, p.country_name, p.author_id, p.shared_post_id,
        p.moderation_status, ${slugSelect},
        pr.display_name as author_name,
        pr.username as author_username,
        pr.avatar_url as author_avatar
      from public.posts p
      left join public.profiles pr on pr.user_id = p.author_id
      where p.id = any($1::uuid[])
      `,
      [clean]
    );
    return rows;
  } catch (err: any) {
    console.warn('[feed] loadRawPostsByIds failed', err?.message ?? err);
    return [];
  }
}

/**
 * Sparks thin page — reels/sparks only, optional slug filter.
 */
export async function fetchSparksPage(input: {
  limit?: number;
  cursor?: string | null;
  slug?: string | null;
  viewerUserId?: string | null;
  /** Already-watched / already-in-pager IDs — keep Sparks endless with fresh clips. */
  excludeIds?: string[] | null;
}): Promise<SurfacePage> {
  // Pre-KNN: larger pages + feed_at so the full R2 spark library is reachable newest-first.
  const want = Math.min(Math.max(Number(input.limit) || 24, 1), 48);
  const focus = input.slug ? normalizeParentSlug(input.slug) : null;
  const cur = decodeCursor(input.cursor);
  const hasCol = await hasHubSlugColumn();
  const slugSelect = hasCol ? 'p.hub_slug' : 'null::text as hub_slug';
  const under18 = await viewerIsUnder18(input.viewerUserId);
  const exclude = (input.excludeIds || [])
    .map((id) => String(id || '').trim())
    .filter((id) => /^[0-9a-f-]{36}$/i.test(id))
    .slice(0, 800);
  const params: unknown[] = [];
  // Sparks = real short video only (spark stamps). Never Hubs LongForm or image memes.
  let where = `
    p.visibility = 'public'
    and lower(coalesce(p.media_type, '')) in ('reel', 'spark', 'video')
    and p.media_url is not null
    and length(trim(p.media_url)) > 8
    and lower(coalesce(p.body, '')) not like '%__story__%'
    and lower(coalesce(p.body, '')) not like '%__hub_channel__%'
    and lower(coalesce(p.body, '')) not like '%__hub_origin__%'
    and coalesce(p.media_path, '') not like '%/LongForm/%'
    and coalesce(p.moderation_status, 'active') not in ('hidden', 'deleted')
    ${adultContentSqlFilter(under18, 'p')}
    and (
      lower(coalesce(p.media_type, '')) in ('reel', 'spark')
      or lower(coalesce(p.body, '')) like '%__spark__|%'
      or lower(coalesce(p.body, '')) like '%__spark_share__|%'
    )
  `;
  if (exclude.length) {
    params.push(exclude);
    where += ` and p.id <> all($${params.length}::uuid[])`;
  }
  if (hasCol && focus) {
    params.push(focus);
    where += ` and (
      lower(coalesce(p.hub_slug, '')) = $${params.length}
      or lower(coalesce(p.hub_slug, '')) like $${params.length} || '\\_%'
    )`;
  }
  if (cur) {
    params.push(cur.createdAt, cur.id);
    where += ` and (greatest(p.updated_at, p.created_at), p.id) < ($${params.length - 1}::timestamptz, $${params.length}::uuid)`;
  }
  // Over-fetch when classifying in memory for slug focus.
  params.push(focus && !hasCol ? want * 4 : want);
  const sql = `
    select
      p.id, p.title, p.body, p.media_type, p.media_url, p.thumb_url,
      p.like_count, p.comment_count, p.created_at, p.updated_at,
      greatest(p.updated_at, p.created_at) as feed_at,
      p.country_code, p.country_name,
      p.author_id, p.shared_post_id, ${slugSelect},
      coalesce(p.moderation_status, 'active') as moderation_status,
      pr.display_name as author_name, pr.username as author_username, pr.avatar_url as author_avatar
    from public.posts p
    left join public.profiles pr on pr.user_id = p.author_id
    where ${where}
    order by greatest(p.updated_at, p.created_at) desc, p.id desc
    limit $${params.length}
  `;
  const { rows } = await pool.query<RawPostRow>(sql, params);
  const items: ThinShelfCard[] = [];
  let lastCursor: string | null = null;
  for (const row of rows) {
    const slug = classifyRow(row);
    lastCursor = encodeCursor(toIso(row.feed_at ?? row.updated_at ?? row.created_at), row.id);
    if (focus && slug !== focus) continue;
    // Prefer short/reel-ish; still accept tagged sparks + R2 spark shares.
    items.push(rowToCard(row, slug));
    if (items.length >= want) break;
  }
  const liveItems = await freshenCardMedia(items);
  return {
    surface: focus ? `sparks:${focus}` : 'sparks',
    items: liveItems,
    nextCursor: lastCursor,
    count: liveItems.length,
  };
}
