import type { S3Client } from '@aws-sdk/client-s3';
import { pool } from '../db.js';
import { emitContentPosted } from '../engagement/engagement.service.js';
import {
  createR2Client,
  discoverPacks,
  encodeMediaUrl,
  extractR2KeyFromMediaPath,
  extractR2KeyFromMediaUrl,
  getBucket,
  getObjectJson,
  packKindFromR2Key,
  presignGet,
  r2Configured,
} from './r2.js';
import { clearPipelineLog, pipelineLog } from './log.js';
import { defaultCategoryId, loadOwnersByCountry, pickOwner, pickSharer } from './owners.js';
import {
  extractCommentTexts,
  isFakeShareCaption,
  markHubOriginShareBody,
  markShareBody,
  pickBody,
  pickCaption,
  stripBodyMarkers,
} from './text.js';
import type { PipelineOptions, PipelineStats, ProfileOwner, R2Pack } from './types.js';

function emptyStats(dryRun: boolean): PipelineStats {
  return {
    ok: true,
    dryRun,
    discovered: 0,
    insertedOriginals: 0,
    insertedShares: 0,
    repairedCaptions: 0,
    repairedComments: 0,
    skippedNoOwner: 0,
    skippedExisting: 0,
    skippedIncomplete: 0,
    resigned: 0,
    errors: [],
    ms: 0,
  };
}

/**
 * Full tick: re-sign expiring R2 URLs → discover new packs → insert owned originals + shares.
 * Real user posts (non-r2 media_path) are never modified.
 * Emits live logs via pipelineLog (ops page SSE).
 *
 * Default: **flood mode** — every new complete R2 pack is ingested in this run
 * (no maxOriginals / maxShares / maxMs cap unless explicitly set).
 */
export async function runContentPipeline(opts: PipelineOptions = {}): Promise<PipelineStats> {
  clearPipelineLog();
  const started = Date.now();
  const dryRun = !!opts.dryRun;
  // Unlimited by default — flood Matterya with every new R2 video at once.
  const maxOriginals =
    opts.maxOriginals != null && Number.isFinite(opts.maxOriginals) && opts.maxOriginals > 0
      ? opts.maxOriginals
      : Number.POSITIVE_INFINITY;
  const maxShares =
    opts.maxShares != null && Number.isFinite(opts.maxShares) && opts.maxShares > 0
      ? opts.maxShares
      : Number.POSITIVE_INFINITY;
  const maxResign = opts.maxResign ?? 500;
  // 0 / unset = no time budget (keep going until all new packs are in).
  const maxMs =
    opts.maxMs != null && Number.isFinite(opts.maxMs) && opts.maxMs > 0 ? opts.maxMs : 0;
  const stats = emptyStats(dryRun);

  const timedOut = () => maxMs > 0 && Date.now() - started > maxMs;

  pipelineLog('══════════════════════════════════════', 'step');
  pipelineLog(
    `Pipeline start · dryRun=${dryRun} resignOnly=${!!opts.resignOnly} ingestOnly=${!!opts.ingestOnly}`,
    'step'
  );
  pipelineLog(
    `Limits: maxOriginals=${Number.isFinite(maxOriginals) ? maxOriginals : 'ALL'} maxShares=${Number.isFinite(maxShares) ? maxShares : 'ALL'} maxResign=${maxResign} maxMs=${maxMs || 'none'}`,
    'info'
  );

  try {
    if (!r2Configured()) {
      const err =
        'R2 not configured — set R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_ACCOUNT_ID|R2_ENDPOINT';
      pipelineLog(err, 'error');
      stats.ok = false;
      stats.errors.push(err);
      stats.ms = Date.now() - started;
      return stats;
    }

    pipelineLog(`R2 bucket: ${getBucket()}`, 'ok');
    pipelineLog('Connecting to R2…', 'step');
    const client = createR2Client();
    pipelineLog('R2 client ready', 'ok');

    pipelineLog('Loading real profiles by country (owners)…', 'step');
    const ownersByCc = await loadOwnersByCountry();
    for (const [cc, list] of ownersByCc) {
      pipelineLog(`  ${cc}: ${list.length} profile(s)`, list.length ? 'info' : 'warn');
    }
    const categoryId = await defaultCategoryId();
    pipelineLog(`Default category_id: ${categoryId ?? '(none)'}`, 'info');

    if (!opts.ingestOnly) {
      // "Re-sign" is legacy naming: with R2_PUBLIC_BASE_URL this writes permanent public
      // URLs (no X-Amz expiry). Without it, it mints fresh 7-day presigned GETs.
      const publicBase = process.env.R2_PUBLIC_BASE_URL?.trim();
      pipelineLog(
        publicBase
          ? `Refreshing up to ${maxResign} R2 media URLs → permanent public base…`
          : `Re-signing up to ${maxResign} R2 media URLs (7-day presign; set R2_PUBLIC_BASE_URL for permanent)…`,
        'step'
      );
      await resignExpiring(client, { dryRun, maxResign, stats, timedOut });
      pipelineLog(
        `Media URL refresh done: ${stats.resigned} updated`,
        stats.resigned ? 'ok' : 'info'
      );
    }

    if (opts.resignOnly || timedOut()) {
      if (timedOut()) pipelineLog('Stopped early (time budget / resignOnly)', 'warn');
      stats.ms = Date.now() - started;
      pipelineLog(`Finished in ${stats.ms}ms (media URL refresh only)`, 'step');
      return stats;
    }

    pipelineLog('Discovering complete packs in R2 (Sparks incl. ShortForm + LongForm)…', 'step');
    const packs = await discoverPacks(client);
    stats.discovered = packs.length;
    const sparkTikTok = packs.filter(
      (p) => p.kind === 'spark' && !p.videoKey.startsWith('ShortForm/')
    ).length;
    const sparkShorts = packs.filter(
      (p) => p.kind === 'spark' && p.videoKey.startsWith('ShortForm/')
    ).length;
    const longform = packs.filter((p) => p.kind === 'longform').length;
    pipelineLog(
      `Discovered ${packs.length} pack(s) · sparks=${sparkTikTok + sparkShorts} (tiktok=${sparkTikTok} youtube_shorts=${sparkShorts}) longform=${longform}`,
      'ok'
    );

    pipelineLog('Loading existing r2: media_path rows from Supabase…', 'step');
    const existing = await loadExistingMediaPaths();
    pipelineLog(`Already in DB: ${existing.size} R2 media_path row(s)`, 'info');

    const missing = packs.filter((p) => !existing.has(p.mediaPath));
    stats.skippedExisting = packs.length - missing.length;
    pipelineLog(
      `New packs to ingest: ${missing.length} (skipped existing: ${stats.skippedExisting})`,
      'step'
    );

    // Prefer Sparks (TikTok + YouTube Shorts) before Hubs longform.
    missing.sort((a, b) => {
      if (a.kind === b.kind) return 0;
      return a.kind === 'spark' ? -1 : 1;
    });

    pipelineLog(
      `Ingesting ALL ${missing.length} new pack(s) this run (flood mode${Number.isFinite(maxOriginals) ? `, cap=${maxOriginals}` : ''})…`,
      'step'
    );

    let n = 0;
    for (const pack of missing) {
      if (timedOut() || stats.insertedOriginals >= maxOriginals) {
        pipelineLog(
          timedOut()
            ? 'Time budget hit — stopping new originals'
            : `Hit maxOriginals=${maxOriginals}`,
          'warn'
        );
        break;
      }

      n += 1;
      const poolOwners = ownersByCc.get(pack.countryCode) ?? [];
      const author = pickOwner(poolOwners, pack.mediaPath);
      if (!author) {
        stats.skippedNoOwner += 1;
        pipelineLog(
          `[${n}/${missing.length}] SKIP no owner · ${pack.countryCode} · ${pack.kind} · ${pack.videoId}`,
          'warn'
        );
        continue;
      }

      pipelineLog(
        `[${n}/${missing.length}] ${dryRun ? 'DRY ' : ''}INGEST ${pack.kind} · ${pack.countryCode} · ${pack.videoId} · author=${author.userId.slice(0, 8)}…`,
        'info'
      );

      try {
        const result = await ingestOriginal(client, {
          pack,
          author,
          categoryId,
          dryRun,
          owners: poolOwners,
        });
        if (result === 'ok' || result === 'ok_shared') {
          stats.insertedOriginals += 1;
          existing.add(pack.mediaPath);
          if (result === 'ok_shared') {
            stats.insertedShares += 1;
            pipelineLog(`  → original + feed share created`, 'ok');
          } else {
            pipelineLog(`  → original created`, 'ok');
          }
        } else if (result === 'incomplete') {
          stats.skippedIncomplete += 1;
          pipelineLog(`  → incomplete pack`, 'warn');
        } else {
          pipelineLog(`  → skip (${result})`, 'info');
        }
      } catch (err: any) {
        const msg = `ingest ${pack.mediaPath}: ${err?.message ?? err}`;
        stats.errors.push(msg);
        pipelineLog(`  → ERROR ${err?.message ?? err}`, 'error');
        if (stats.errors.length > 20) {
          pipelineLog('Too many errors — aborting ingest loop', 'error');
          break;
        }
      }
    }

    if (!timedOut() && stats.insertedShares < maxShares) {
      const remainingShares = Number.isFinite(maxShares)
        ? maxShares - stats.insertedShares
        : Number.POSITIVE_INFINITY;
      pipelineLog(
        `Backfilling feed spark shares (${Number.isFinite(remainingShares) ? `up to ${remainingShares}` : 'ALL missing'})…`,
        'step'
      );
      const before = stats.insertedShares;
      await ensureSparkShares({
        dryRun,
        maxShares: remainingShares,
        ownersByCc,
        categoryId,
        stats,
        timedOut,
      });
      pipelineLog(
        `Spark share backfill: +${stats.insertedShares - before} (total shares this run: ${stats.insertedShares})`,
        'ok'
      );
    }

    // Hubs long-form feed shares (`__hub_origin__|`) — badge + “Shared from …” on the home feed.
    if (!timedOut() && stats.insertedShares < maxShares) {
      const remainingShares = Number.isFinite(maxShares)
        ? maxShares - stats.insertedShares
        : Number.POSITIVE_INFINITY;
      pipelineLog(
        `Backfilling Hubs long-form feed shares (${Number.isFinite(remainingShares) ? `up to ${remainingShares}` : 'ALL missing'})…`,
        'step'
      );
      const beforeHub = stats.insertedShares;
      await ensureHubOriginShares({
        dryRun,
        maxShares: remainingShares,
        ownersByCc,
        categoryId,
        stats,
        timedOut,
      });
      // Repair longform originals missing `__hub_channel__|` (last run wrote plain bodies).
      await repairHubChannelMarkers({ dryRun, maxRepair: 800, stats, timedOut });
      pipelineLog(
        `Hubs share backfill: +${stats.insertedShares - beforeHub} (total shares this run: ${stats.insertedShares})`,
        'ok'
      );
    }

    // Replace seeder fluff on existing shares with the origin's real R2 meta caption.
    if (!timedOut() && !opts.resignOnly) {
      pipelineLog('Repairing share captions from R2 origin meta text…', 'step');
      await repairShareCaptions({
        dryRun,
        maxRepair: opts.maxCaptionRepairs ?? 500,
        stats,
        timedOut,
      });
      pipelineLog(`Caption repairs: ${stats.repairedCaptions}`, stats.repairedCaptions ? 'ok' : 'info');
    }

    // Expand posts that were seeded with the old 25-comment cap using full R2 comments.json.
    if (!timedOut() && !opts.resignOnly) {
      pipelineLog('Repairing truncated R2 comment threads (old 25-cap)…', 'step');
      await repairR2Comments({
        client,
        dryRun,
        maxPosts: opts.maxCommentRepairs ?? 80,
        ownersByCc,
        stats,
        timedOut,
      });
      pipelineLog(
        `Comment repairs: ${stats.repairedComments}`,
        stats.repairedComments ? 'ok' : 'info'
      );
    }
  } catch (err: any) {
    stats.ok = false;
    stats.errors.push(err?.message ?? String(err));
    pipelineLog(`FATAL: ${err?.message ?? err}`, 'error');
  }

  stats.ms = Date.now() - started;
  if (stats.errors.length > 0 && stats.insertedOriginals === 0 && stats.resigned === 0) {
    stats.ok = false;
  }
  pipelineLog('──────────────────────────────────────', 'step');
  pipelineLog(
    `DONE ok=${stats.ok} · discovered=${stats.discovered} · originals=+${stats.insertedOriginals} · shares=+${stats.insertedShares} · captionsFixed=${stats.repairedCaptions} · commentsFixed=${stats.repairedComments} · resigned=${stats.resigned} · noOwner=${stats.skippedNoOwner} · existing=${stats.skippedExisting} · ${stats.ms}ms`,
    stats.ok ? 'ok' : 'error'
  );
  if (stats.errors.length) {
    pipelineLog(`Errors (${stats.errors.length}): ${stats.errors.slice(0, 5).join(' | ')}`, 'error');
  }
  return stats;
}

async function loadExistingMediaPaths(): Promise<Set<string>> {
  const set = new Set<string>();
  const { rows } = await pool.query<{ media_path: string }>(
    `
    select media_path from public.posts
    where media_path is not null
      and (
        media_path like 'r2:%'
        or media_path like 'r2-share:%'
        or media_path like 'r2-hubshare:%'
      )
    `
  );
  for (const r of rows) {
    if (r.media_path) set.add(r.media_path);
  }
  pipelineLog(`DB query: ${rows.length} R2-related post row(s)`, 'info');
  return set;
}

/**
 * Seed `like_count` from TikTok/YouTube **engagement** only.
 * Never use play_count / view_count / views — those capped at 5000 and looked fake.
 * Soft ceiling only guards absurd meta (not a product “max likes” display).
 */
export function seedLikeCountFromMeta(meta: Record<string, unknown>): number {
  const raw =
    meta.digg_count ??
    meta.like_count ??
    meta.likes ??
    meta.heart ??
    meta.hearts ??
    null;
  if (raw == null || raw === '') return 0;
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0) return 0;
  // Soft sanity only (billions from bad scrapes) — not the old hard 5000 product cap.
  return Math.min(Math.floor(n), 50_000_000);
}

async function ingestOriginal(
  client: S3Client,
  opts: {
    pack: R2Pack;
    author: ProfileOwner;
    categoryId: string | null;
    dryRun: boolean;
    owners: ProfileOwner[];
  }
): Promise<'ok' | 'ok_shared' | 'incomplete' | 'skip'> {
  const { pack, author, categoryId, dryRun, owners } = opts;

  // Require video object (list already filtered by video.mp4 key presence).
  const metaRaw = await getObjectJson(client, pack.metaKey);
  const meta =
    metaRaw && typeof metaRaw === 'object' && !Array.isArray(metaRaw)
      ? (metaRaw as Record<string, unknown>)
      : {};

  const caption = pickCaption(meta, pack.kind, pack.videoId);
  const body = pickBody(pack.kind, caption, meta);
  pipelineLog(
    `  caption: ${caption.slice(0, 100)}${caption.length > 100 ? '…' : ''}`,
    caption.startsWith('Spark ') || caption.startsWith('Video ') ? 'warn' : 'info'
  );

  const signed = await presignGet(client, pack.videoKey);
  const mediaUrl = encodeMediaUrl({
    signedUrl: signed,
    reel: pack.kind === 'spark',
    r2Key: pack.videoKey,
    sourceId: `${pack.countryFolder}/${pack.videoId}`,
    kind: pack.kind,
  });

  // Always "now" so new R2 content sorts to the top of feed / discovery.
  const createdAt = new Date().toISOString();

  if (dryRun) return 'ok';

  // DB check allows none|image|video|link — Sparks are media_type=video + body/JSON reel markers.
  const mediaType = 'video';
  // Always store real caption in title too (feed cards / search).
  const titleCol = caption.slice(0, 200) || null;
  let postId: string | undefined;
  try {
    const { rows } = await pool.query<{ id: string }>(
      `
      insert into public.posts
        (author_id, category_id, country_name, country_code, city_name,
         title, body, media_type, media_url, media_path, visibility,
         like_count, comment_count, created_at, updated_at, moderation_status)
      values
        ($1, $2, $3, $4, $5,
         $6, $7, $8, $9, $10, 'public',
         $11, 0, $12::timestamptz, $12::timestamptz, 'active')
      returning id
      `,
      [
        author.userId,
        categoryId,
        author.countryName || pack.countryName,
        pack.countryCode,
        author.cityName,
        titleCol,
        body,
        mediaType,
        mediaUrl,
        pack.mediaPath,
        // Seed likes: digg/like only — never play_count/views (those made everything show 5000).
        // No artificial 5000 cap; soft sanity ceiling only for garbage meta.
        seedLikeCountFromMeta(meta),
        createdAt,
      ]
    );
    postId = rows[0]?.id;
  } catch (e: any) {
    if (String(e?.message ?? '').includes('duplicate') || e?.code === '23505') {
      return 'skip';
    }
    throw e;
  }
  if (!postId) return 'skip';

  // Optional media_caption table (used by insights / web) — best-effort.
  try {
    await pool.query(
      `
      insert into public.post_media_captions (post_id, caption)
      values ($1::uuid, $2)
      on conflict (post_id) do update set caption = excluded.caption
      `,
      [postId, caption]
    );
  } catch {
    /* table may not exist */
  }

  // Seed **all** comments from R2 comments.json (no 25-cap — packs often have 50–300+).
  try {
    const commentsRaw = await getObjectJson(client, pack.commentsKey);
    const texts = extractCommentTexts(commentsRaw);
    const n = await seedCommentsForPost({
      postId,
      texts,
      owners,
      authorUserId: author.userId,
    });
    if (n > 0) {
      pipelineLog(`  comments seeded: ${n} (from R2 comments.json, full set)`, 'ok');
    } else if (texts.length === 0) {
      pipelineLog(`  comments: none in R2 pack`, 'info');
    }
  } catch (err: any) {
    pipelineLog(`  comments seed failed: ${err?.message ?? err}`, 'warn');
  }

  void emitContentPosted({
    entityId: author.userId,
    contentId: postId,
    authorId: author.userId,
    mediaType,
    countryCode: pack.countryCode,
    countryName: author.countryName || pack.countryName,
    cityName: author.cityName,
    isSpark: pack.kind === 'spark',
    isHubLongForm: pack.kind === 'longform',
    title: caption,
    summary:
      pack.kind === 'spark'
        ? pack.videoKey.startsWith('ShortForm/')
          ? `Catalog Spark (YouTube Shorts) published for ${pack.countryName}`
          : `Catalog Spark published for ${pack.countryName}`
        : `Catalog Hubs video published for ${pack.countryName}`,
    destination: pack.kind === 'spark' ? 'sparks' : 'hubs',
    surface: pack.kind === 'spark' ? 'sparks' : 'hubs',
    mediaUrl,
  });

  // Immediate feed share for density — same original caption.
  // Sparks → `__spark_share__|` (Spark card). LongForm → `__hub_origin__|` (Hubs badge + Shared from).
  if (pack.kind === 'spark') {
    const shared = await createSparkShare({
      originId: postId,
      originMediaUrl: mediaUrl,
      originAuthorId: author.userId,
      originCaption: caption,
      owners,
      categoryId,
      countryCode: pack.countryCode,
      countryName: author.countryName || pack.countryName,
      dryRun: false,
      seed: pack.mediaPath,
    });
    return shared ? 'ok_shared' : 'ok';
  }

  if (pack.kind === 'longform') {
    const shared = await createHubOriginShare({
      originId: postId,
      originMediaUrl: mediaUrl,
      originAuthorId: author.userId,
      originAuthorName: author.countryName || pack.countryName,
      originUsername: null,
      originCaption: caption,
      owners,
      categoryId,
      countryCode: pack.countryCode,
      countryName: author.countryName || pack.countryName,
      dryRun: false,
      seed: pack.mediaPath,
    });
    return shared ? 'ok_shared' : 'ok';
  }

  return 'ok';
}

/**
 * Feed re-share of a Hubs LongForm original — Hubs badge + “Shared from …” on the home feed.
 */
async function createHubOriginShare(opts: {
  originId: string;
  originMediaUrl: string;
  originAuthorId: string;
  originAuthorName?: string | null;
  originUsername?: string | null;
  originCaption?: string | null;
  owners: ProfileOwner[];
  categoryId: string | null;
  countryCode: string;
  countryName: string;
  dryRun: boolean;
  seed: string;
}): Promise<boolean> {
  const sharer = pickSharer(opts.owners, opts.originAuthorId, opts.seed);
  if (!sharer) return false;

  const { rows: existing } = await pool.query<{ id: string }>(
    `
    select id from public.posts
    where body like $1
    limit 1
    `,
    [`%__hub_origin__|sid=${opts.originId}%`]
  );
  if (existing[0]) return false;
  if (opts.dryRun) return true;

  let caption = (opts.originCaption || '').trim();
  if (isFakeShareCaption(caption)) caption = '';
  if (!caption) {
    const { rows: originRows } = await pool.query<{ title: string | null; body: string | null }>(
      `select title, body from public.posts where id = $1::uuid limit 1`,
      [opts.originId]
    );
    const o = originRows[0];
    const fromBody = stripBodyMarkers(o?.body);
    if (fromBody) caption = fromBody;
    else if (o?.title?.trim() && !isFakeShareCaption(o.title)) caption = o.title.trim();
  }

  let authorName = (opts.originAuthorName || '').trim();
  let username = (opts.originUsername || '').trim();
  if (!authorName || !username) {
    try {
      const { rows: prof } = await pool.query<{ display_name: string | null; username: string | null }>(
        `select display_name, username from public.profiles where user_id = $1::uuid limit 1`,
        [opts.originAuthorId]
      );
      if (!authorName) {
        authorName = (prof[0]?.display_name || prof[0]?.username || opts.countryName || 'Hubs').trim();
      }
      if (!username) username = (prof[0]?.username || '').trim();
    } catch {
      if (!authorName) authorName = opts.countryName || 'Hubs';
    }
  }

  const body = markHubOriginShareBody({
    originId: opts.originId,
    originAuthorId: opts.originAuthorId,
    originAuthorName: authorName,
    originUsername: username || null,
    caption,
  });
  const sharePath = opts.seed.startsWith('r2:')
    ? `r2-hubshare:${opts.seed.slice(3)}`
    : `r2-hubshare:${opts.seed}`;

  let mediaUrl = opts.originMediaUrl;
  try {
    if (mediaUrl.startsWith('{')) {
      const obj = JSON.parse(mediaUrl) as Record<string, unknown>;
      obj.reel = false;
      obj.kind = 'longform';
      obj.source = 'r2_hub_share';
      mediaUrl = JSON.stringify(obj);
    }
  } catch {
    /* keep */
  }

  const createdAt = new Date().toISOString();
  const { rows } = await pool.query<{ id: string }>(
    `
    insert into public.posts
      (author_id, category_id, country_name, country_code, city_name,
       title, body, media_type, media_url, media_path, shared_post_id, visibility,
       like_count, comment_count, created_at, updated_at, moderation_status)
    values
      ($1, $2, $3, $4, $5,
       $6, $7, 'video', $8, $9, $10::uuid, 'public',
       0, 0, $11::timestamptz, $11::timestamptz, 'active')
    returning id
    `,
    [
      sharer.userId,
      opts.categoryId,
      sharer.countryName || opts.countryName,
      opts.countryCode,
      sharer.cityName,
      caption ? caption.slice(0, 200) : null,
      body,
      mediaUrl,
      sharePath,
      opts.originId,
      createdAt,
    ]
  );

  const shareId = rows[0]?.id;
  if (!shareId) return false;

  try {
    if (caption) {
      await pool.query(
        `
        insert into public.post_media_captions (post_id, caption)
        values ($1::uuid, $2)
        on conflict (post_id) do update set caption = excluded.caption
        `,
        [shareId, caption]
      );
    }
  } catch {
    /* optional */
  }

  void emitContentPosted({
    entityId: sharer.userId,
    contentId: shareId,
    authorId: sharer.userId,
    mediaType: 'video',
    countryCode: opts.countryCode,
    countryName: sharer.countryName || opts.countryName,
    isSpark: false,
    isHubLongForm: true,
    sharedPostId: opts.originId,
    title: caption || null,
    summary: `Hubs video shared to the home feed from ${opts.countryName}`,
    destination: 'share',
    surface: 'feed',
    mediaUrl,
  });

  return true;
}

async function createSparkShare(opts: {
  originId: string;
  originMediaUrl: string;
  originAuthorId: string;
  /** Real caption from R2 meta (not filler). */
  originCaption?: string;
  owners: ProfileOwner[];
  categoryId: string | null;
  countryCode: string;
  countryName: string;
  dryRun: boolean;
  seed: string;
}): Promise<boolean> {
  const sharer = pickSharer(opts.owners, opts.originAuthorId, opts.seed);
  if (!sharer) return false;

  // Already shared?
  const { rows: existing } = await pool.query<{ id: string }>(
    `
    select id from public.posts
    where body like $1
    limit 1
    `,
    [`%__spark_share__|sid=${opts.originId}%`]
  );
  if (existing[0]) return false;

  if (opts.dryRun) return true;

  // Prefer caption from caller; else load real text from origin (never seeder fluff).
  let caption = (opts.originCaption || '').trim();
  if (isFakeShareCaption(caption)) caption = '';
  if (!caption) {
    const { rows: originRows } = await pool.query<{ title: string | null; body: string | null }>(
      `select title, body from public.posts where id = $1::uuid limit 1`,
      [opts.originId]
    );
    const o = originRows[0];
    const fromBody = stripBodyMarkers(o?.body);
    if (fromBody) caption = fromBody;
    else if (o?.title?.trim() && !isFakeShareCaption(o.title)) caption = o.title.trim();
  }
  const body = markShareBody(opts.originId, caption);
  const sharePath = opts.seed.startsWith('r2:')
    ? `r2-share:${opts.seed.slice(3)}`
    : `r2-share:${opts.seed}`;

  // Ensure reel flag on media payload for feed player.
  let mediaUrl = opts.originMediaUrl;
  try {
    if (mediaUrl.startsWith('{')) {
      const obj = JSON.parse(mediaUrl) as Record<string, unknown>;
      obj.reel = true;
      obj.source = 'r2_spark_share';
      mediaUrl = JSON.stringify(obj);
    }
  } catch {
    /* keep */
  }

  // Fresh timestamp so the home feed (newest-first) shows this share immediately.
  const createdAt = new Date().toISOString();

  const { rows } = await pool.query<{ id: string }>(
    `
    insert into public.posts
      (author_id, category_id, country_name, country_code, city_name,
       title, body, media_type, media_url, media_path, shared_post_id, visibility,
       like_count, comment_count, created_at, updated_at, moderation_status)
    values
      ($1, $2, $3, $4, $5,
       $6, $7, 'video', $8, $9, $10::uuid, 'public',
       0, 0, $11::timestamptz, $11::timestamptz, 'active')
    returning id
    `,
    [
      sharer.userId,
      opts.categoryId,
      sharer.countryName || opts.countryName,
      opts.countryCode,
      sharer.cityName,
      caption ? caption.slice(0, 200) : null,
      body,
      mediaUrl,
      sharePath,
      opts.originId,
      createdAt,
    ]
  );

  const shareId = rows[0]?.id;
  if (!shareId) return false;

  try {
    if (caption) {
      await pool.query(
        `
        insert into public.post_media_captions (post_id, caption)
        values ($1::uuid, $2)
        on conflict (post_id) do update set caption = excluded.caption
        `,
        [shareId, caption]
      );
    }
  } catch {
    /* optional */
  }

  void emitContentPosted({
    entityId: sharer.userId,
    contentId: shareId,
    authorId: sharer.userId,
    mediaType: 'video',
    countryCode: opts.countryCode,
    countryName: sharer.countryName || opts.countryName,
    isSpark: true,
    sharedPostId: opts.originId,
    title: caption || null,
    summary: `Spark shared to the home feed from ${opts.countryName}`,
    destination: 'share',
    surface: 'feed',
    mediaUrl,
  });

  return true;
}

async function ensureSparkShares(opts: {
  dryRun: boolean;
  maxShares: number;
  ownersByCc: Map<string, ProfileOwner[]>;
  categoryId: string | null;
  stats: PipelineStats;
  timedOut: () => boolean;
}): Promise<void> {
  // Sparks without a share stamp pointing at them.
  const { rows } = await pool.query<{
    id: string;
    author_id: string;
    media_url: string | null;
    media_path: string | null;
    country_code: string | null;
    country_name: string | null;
  }>(
    `
    select p.id, p.author_id, p.media_url, p.media_path, p.country_code, p.country_name
    from public.posts p
    where p.media_path like 'r2:%'
      and p.body like '%__spark__|%'
      and p.body not like '%__spark_share__|%'
      and not exists (
        select 1 from public.posts s
        where s.body like '%__spark_share__|sid=' || p.id::text || '%'
        limit 1
      )
    order by p.created_at desc
    limit $1
    `,
    [
      Number.isFinite(opts.maxShares)
        ? Math.max(1, Math.floor(opts.maxShares * 2))
        : 100_000,
    ]
  );

  for (const row of rows) {
    if (opts.timedOut() || opts.stats.insertedShares >= opts.maxShares) break;
    const cc = (row.country_code || '').toUpperCase();
    const owners = opts.ownersByCc.get(cc) ?? [];
    if (!owners.length) {
      opts.stats.skippedNoOwner += 1;
      continue;
    }
    try {
      const ok = await createSparkShare({
        originId: row.id,
        originMediaUrl: row.media_url || '',
        originAuthorId: row.author_id,
        // Caption loaded from origin post title/body inside createSparkShare
        owners,
        categoryId: opts.categoryId,
        countryCode: cc || 'US',
        countryName: row.country_name || cc,
        dryRun: opts.dryRun,
        seed: row.media_path || row.id,
      });
      if (ok) opts.stats.insertedShares += 1;
    } catch (err: any) {
      opts.stats.errors.push(`share ${row.id}: ${err?.message ?? err}`);
    }
  }
}

/** LongForm R2 originals missing a `__hub_origin__|` feed share. */
async function ensureHubOriginShares(opts: {
  dryRun: boolean;
  maxShares: number;
  ownersByCc: Map<string, ProfileOwner[]>;
  categoryId: string | null;
  stats: PipelineStats;
  timedOut: () => boolean;
}): Promise<void> {
  const { rows } = await pool.query<{
    id: string;
    author_id: string;
    media_url: string | null;
    media_path: string | null;
    country_code: string | null;
    country_name: string | null;
    title: string | null;
    body: string | null;
  }>(
    `
    select p.id, p.author_id, p.media_url, p.media_path, p.country_code, p.country_name, p.title, p.body
    from public.posts p
    where p.media_path like 'r2:%'
      and (
        p.media_path ilike '%/LongForm/%'
        or p.media_url ilike '%LongForm/%'
        or p.media_url ilike '%"kind":"longform"%'
        or p.body like '%__hub_channel__|%'
      )
      and p.body not like '%__spark__|%'
      and p.body not like '%__spark_share__|%'
      and p.body not like '%__hub_origin__|%'
      and not exists (
        select 1 from public.posts s
        where s.body like '%__hub_origin__|sid=' || p.id::text || '%'
        limit 1
      )
    order by p.created_at desc
    limit $1
    `,
    [
      Number.isFinite(opts.maxShares)
        ? Math.max(1, Math.floor(opts.maxShares * 2))
        : 100_000,
    ]
  );

  for (const row of rows) {
    if (opts.timedOut() || opts.stats.insertedShares >= opts.maxShares) break;
    const cc = (row.country_code || '').toUpperCase();
    const owners = opts.ownersByCc.get(cc) ?? [];
    if (!owners.length) {
      opts.stats.skippedNoOwner += 1;
      continue;
    }
    try {
      const cap = stripBodyMarkers(row.body) || (row.title || '').trim();
      const ok = await createHubOriginShare({
        originId: row.id,
        originMediaUrl: row.media_url || '',
        originAuthorId: row.author_id,
        originCaption: cap,
        owners,
        categoryId: opts.categoryId,
        countryCode: cc || 'US',
        countryName: row.country_name || cc,
        dryRun: opts.dryRun,
        seed: row.media_path || row.id,
      });
      if (ok) opts.stats.insertedShares += 1;
    } catch (err: any) {
      opts.stats.errors.push(`hub-share ${row.id}: ${err?.message ?? err}`);
    }
  }
}

/**
 * Stamp `__hub_channel__|` on LongForm R2 originals that were ingested without it
 * (so iOS treats them as Hubs catalog / channel content).
 */
async function repairHubChannelMarkers(opts: {
  dryRun: boolean;
  maxRepair: number;
  stats: PipelineStats;
  timedOut: () => boolean;
}): Promise<void> {
  const { rows } = await pool.query<{ id: string; body: string | null }>(
    `
    select id, body
    from public.posts
    where media_path like 'r2:%'
      and (
        media_path ilike '%/LongForm/%'
        or media_url ilike '%LongForm/%'
        or media_url ilike '%"kind":"longform"%'
      )
      and coalesce(body, '') not like '%__hub_channel__|%'
      and coalesce(body, '') not like '%__spark__|%'
      and coalesce(body, '') not like '%__hub_origin__|%'
      and coalesce(body, '') not like '%__spark_share__|%'
    order by updated_at asc nulls first
    limit $1
    `,
    [opts.maxRepair]
  );

  let fixed = 0;
  for (const row of rows) {
    if (opts.timedOut()) break;
    const raw = (row.body || '').trim();
    const next = raw ? `__hub_channel__|\n${raw}` : '__hub_channel__|';
    if (opts.dryRun) {
      fixed += 1;
      continue;
    }
    try {
      await pool.query(
        `update public.posts set body = $2, updated_at = now() where id = $1::uuid`,
        [row.id, next]
      );
      fixed += 1;
    } catch (err: any) {
      opts.stats.errors.push(`hub-channel repair ${row.id}: ${err?.message ?? err}`);
    }
  }
  if (fixed > 0) {
    pipelineLog(`  stamped __hub_channel__| on ${fixed} LongForm original(s)`, 'ok');
  }
}

/**
 * Insert every comment text from R2 and set posts.comment_count to the real count.
 * Uses batch inserts for packs with 100+ comments.
 */
async function seedCommentsForPost(opts: {
  postId: string;
  texts: string[];
  owners: ProfileOwner[];
  authorUserId: string;
}): Promise<number> {
  const texts = opts.texts.filter((t) => t && t.trim());
  if (!texts.length) {
    await pool.query(
      `update public.posts set comment_count = 0, updated_at = now() where id = $1::uuid`,
      [opts.postId]
    );
    return 0;
  }

  const commentAuthors = opts.owners.filter((o) => o.userId !== opts.authorUserId);
  const cPool = commentAuthors.length ? commentAuthors : opts.owners;
  if (!cPool.length) return 0;

  const chunkSize = 40;
  let inserted = 0;
  for (let start = 0; start < texts.length; start += chunkSize) {
    const chunk = texts.slice(start, start + chunkSize);
    const values: string[] = [];
    const params: unknown[] = [];
    chunk.forEach((text, j) => {
      const i = start + j;
      const author = cPool[i % cPool.length]!;
      const base = params.length;
      // $1 post, $2 author, $3 body, $4 minutes ago
      values.push(
        `($${base + 1}::uuid, $${base + 2}::uuid, $${base + 3}, now() - ($${base + 4} || ' minutes')::interval, now())`
      );
      params.push(opts.postId, author.userId, text, String(2 + (i % 5000)));
    });
    const { rowCount } = await pool.query(
      `
      insert into public.post_comments (post_id, author_id, body, created_at, updated_at)
      values ${values.join(',')}
      `,
      params
    );
    inserted += rowCount ?? chunk.length;
  }

  await pool.query(
    `
    update public.posts
    set comment_count = (
      select count(*)::int from public.post_comments where post_id = $1::uuid
    ),
    updated_at = now()
    where id = $1::uuid
    `,
    [opts.postId]
  );
  return inserted;
}

/**
 * For existing R2 originals that were capped at 25 comments, re-read comments.json
 * and append any missing texts (does not delete user-written comments).
 */
async function repairR2Comments(opts: {
  client: S3Client;
  dryRun: boolean;
  maxPosts: number;
  ownersByCc: Map<string, ProfileOwner[]>;
  stats: PipelineStats;
  timedOut: () => boolean;
}): Promise<void> {
  const { rows } = await pool.query<{
    id: string;
    media_path: string | null;
    country_code: string | null;
    author_id: string;
    comment_count: number;
  }>(
    `
    select p.id, p.media_path, p.country_code, p.author_id,
           coalesce(
             (select count(*)::int from public.post_comments c where c.post_id = p.id),
             0
           ) as comment_count
    from public.posts p
    where p.media_path like 'r2:%'
      and p.media_path not like 'r2-share:%'
      and p.media_path not like 'r2-hubshare:%'
      and (
        coalesce(
          (select count(*)::int from public.post_comments c where c.post_id = p.id),
          0
        ) < 40
      )
    order by p.created_at desc
    limit $1
    `,
    [opts.maxPosts]
  );

  pipelineLog(`  comment-repair candidates: ${rows.length}`, 'info');
  let fixed = 0;

  for (const row of rows) {
    if (opts.timedOut()) break;
    const key = extractR2KeyFromMediaPath(row.media_path || '');
    if (!key || !key.endsWith('/video.mp4')) continue;
    const commentsKey = key.replace(/\/video\.mp4$/i, '/comments.json');

    try {
      const raw = await getObjectJson(opts.client, commentsKey);
      const texts = extractCommentTexts(raw);
      if (texts.length <= row.comment_count) {
        // Already full (or R2 has fewer). Still sync count.
        if (!opts.dryRun && row.comment_count !== texts.length) {
          await pool.query(
            `
            update public.posts
            set comment_count = (
              select count(*)::int from public.post_comments where post_id = $1::uuid
            )
            where id = $1::uuid
            `,
            [row.id]
          );
        }
        continue;
      }

      // Load existing bodies to append only missing texts.
      const { rows: existing } = await pool.query<{ body: string }>(
        `select body from public.post_comments where post_id = $1::uuid`,
        [row.id]
      );
      const have = new Set(existing.map((e) => e.body.trim().toLowerCase()));
      const missing = texts.filter((t) => !have.has(t.trim().toLowerCase()));
      if (!missing.length) continue;

      if (opts.dryRun) {
        fixed += 1;
        continue;
      }

      const cc = (row.country_code || '').toUpperCase();
      const owners = opts.ownersByCc.get(cc) ?? [];
      const n = await seedCommentsForPost({
        postId: row.id,
        texts: missing,
        owners: owners.length ? owners : [{ userId: row.author_id, countryCode: cc, countryName: null, cityName: null }],
        authorUserId: row.author_id,
      });
      // seedCommentsForPost sets count from total rows — good.
      if (n > 0) {
        fixed += 1;
        // Mirror onto spark shares of this origin (feed cards).
        await mirrorCommentsToShares(row.id, missing, owners, row.author_id);
        if (fixed === 1 || fixed % 20 === 0) {
          pipelineLog(
            `  comments repaired on ${fixed} posts · last +${n} (had ${row.comment_count}, r2 has ${texts.length})`,
            'info'
          );
        }
      }
    } catch (err: any) {
      opts.stats.errors.push(`comments ${row.id}: ${err?.message ?? err}`);
    }
  }

  opts.stats.repairedComments = (opts.stats.repairedComments ?? 0) + fixed;
  pipelineLog(`  comment repair done: ${fixed} post(s) expanded`, fixed ? 'ok' : 'info');
}

/** Copy newly seeded origin comments onto r2-share posts that point at this origin. */
async function mirrorCommentsToShares(
  originId: string,
  texts: string[],
  owners: ProfileOwner[],
  originAuthorId: string
): Promise<void> {
  if (!texts.length) return;
  const { rows: shares } = await pool.query<{ id: string; author_id: string; comment_count: number }>(
    `
    select id, author_id,
           coalesce((select count(*)::int from public.post_comments c where c.post_id = p.id), 0) as comment_count
    from public.posts p
    where (
      shared_post_id = $1::uuid
      or body like $2
    )
    and media_path like 'r2-share:%'
    limit 20
    `,
    [originId, `%__spark_share__|sid=${originId}%`]
  );

  for (const share of shares) {
    if (share.comment_count >= texts.length) continue;
    const { rows: existing } = await pool.query<{ body: string }>(
      `select body from public.post_comments where post_id = $1::uuid`,
      [share.id]
    );
    const have = new Set(existing.map((e) => e.body.trim().toLowerCase()));
    const missing = texts.filter((t) => !have.has(t.trim().toLowerCase()));
    if (!missing.length) continue;
    await seedCommentsForPost({
      postId: share.id,
      texts: missing,
      owners,
      authorUserId: share.author_id || originAuthorId,
    });
  }
}

/**
 * Rewrite existing spark *shares* that still carry seeder fluff captions
 * (`the audio though`, `mood`, …) to the origin post's real R2 meta caption.
 * Also fills empty `title` on originals when body has the meta text.
 */
async function repairShareCaptions(opts: {
  dryRun: boolean;
  maxRepair: number;
  stats: PipelineStats;
  timedOut: () => boolean;
}): Promise<void> {
  const { rows: shares } = await pool.query<{
    id: string;
    body: string | null;
    title: string | null;
    shared_post_id: string | null;
  }>(
    `
    select id, body, title, shared_post_id
    from public.posts
    where media_path like 'r2-share:%'
      and body like '%__spark_share__|%'
    order by created_at desc
    limit $1
    `,
    [Math.max(50, opts.maxRepair * 3)]
  );

  pipelineLog(`  share rows scanned: ${shares.length}`, 'info');
  let checked = 0;

  for (const share of shares) {
    if (opts.timedOut() || opts.stats.repairedCaptions >= opts.maxRepair) break;
    checked += 1;

    const currentCap = stripBodyMarkers(share.body);
    // Already has a real (non-fluff) caption and a title → skip.
    const titleOk = !!(share.title && share.title.trim() && !isFakeShareCaption(share.title));
    if (currentCap && !isFakeShareCaption(currentCap) && titleOk) continue;

    // Resolve origin id from column or body marker.
    let originId = share.shared_post_id || '';
    if (!originId && share.body) {
      const m = share.body.match(/__spark_share__\|sid=([0-9a-f-]{36})/i);
      if (m?.[1]) originId = m[1];
    }
    if (!originId) continue;

    const { rows: originRows } = await pool.query<{
      id: string;
      title: string | null;
      body: string | null;
    }>(`select id, title, body from public.posts where id = $1::uuid limit 1`, [originId]);
    const origin = originRows[0];
    if (!origin) continue;

    let caption = stripBodyMarkers(origin.body);
    if (!caption && origin.title?.trim() && !isFakeShareCaption(origin.title)) {
      caption = origin.title.trim();
    }
    if (!caption) continue;

    // Origin may still have empty title — fill from body meta text.
    if (!opts.dryRun && (!origin.title || !origin.title.trim())) {
      try {
        await pool.query(
          `update public.posts set title = $2, updated_at = now() where id = $1::uuid and (title is null or title = '')`,
          [origin.id, caption.slice(0, 200)]
        );
      } catch {
        /* non-fatal */
      }
    }

    // Share already correct text but missing title?
    if (currentCap === caption && !titleOk) {
      if (!opts.dryRun) {
        await pool.query(
          `update public.posts set title = $2, updated_at = now() where id = $1::uuid`,
          [share.id, caption.slice(0, 200)]
        );
      }
      opts.stats.repairedCaptions += 1;
      continue;
    }

    // Replace fluff / empty with real origin caption.
    if (currentCap && currentCap === caption) continue;
    if (currentCap && !isFakeShareCaption(currentCap) && currentCap.length > 8) {
      // Different real caption already set by user — leave it.
      continue;
    }

    const newBody = markShareBody(originId, caption);
    if (opts.dryRun) {
      opts.stats.repairedCaptions += 1;
      continue;
    }

    try {
      await pool.query(
        `
        update public.posts
        set body = $2,
            title = $3,
            updated_at = now()
        where id = $1::uuid
        `,
        [share.id, newBody, caption.slice(0, 200)]
      );
      try {
        await pool.query(
          `
          insert into public.post_media_captions (post_id, caption)
          values ($1::uuid, $2)
          on conflict (post_id) do update set caption = excluded.caption
          `,
          [share.id, caption]
        );
      } catch {
        /* optional table */
      }
      opts.stats.repairedCaptions += 1;
      if (opts.stats.repairedCaptions === 1 || opts.stats.repairedCaptions % 50 === 0) {
        pipelineLog(
          `  repaired ${opts.stats.repairedCaptions} · sample: ${caption.slice(0, 80)}${caption.length > 80 ? '…' : ''}`,
          'info'
        );
      }
    } catch (err: any) {
      opts.stats.errors.push(`repair ${share.id}: ${err?.message ?? err}`);
    }
  }

  pipelineLog(`  share caption check done (scanned=${checked})`, 'info');
}

async function resignExpiring(
  client: S3Client,
  opts: {
    dryRun: boolean;
    maxResign: number;
    stats: PipelineStats;
    timedOut: () => boolean;
  }
): Promise<void> {
  // Only R2 catalog rows — never touch user Supabase Storage uploads.
  const { rows } = await pool.query<{ id: string; media_url: string | null; media_path: string | null }>(
    `
    select id, media_url, media_path
    from public.posts
    where media_path is not null
      and (
        media_path like 'r2:%'
        or media_path like 'r2-share:%'
        or media_path like 'r2-hubshare:%'
      )
    order by updated_at asc nulls first
    limit $1
    `,
    [opts.maxResign]
  );

  const publicBase = process.env.R2_PUBLIC_BASE_URL?.trim().replace(/\/+$/, '') || '';
  const usingPublic = publicBase.length > 0;
  pipelineLog(
    `Media URL refresh candidates: ${rows.length}` +
      (usingPublic ? ` (public base ${publicBase.replace(/^https?:\/\//, '')})` : ' (presigned mode)'),
    'info'
  );
  let i = 0;
  let skippedAlreadyGood = 0;
  for (const row of rows) {
    if (opts.timedOut()) break;
    i += 1;
    const key =
      extractR2KeyFromMediaUrl(row.media_url) ||
      extractR2KeyFromMediaPath(row.media_path || '');
    if (!key) continue;

    try {
      // Already permanent public URL for this key → skip (no DB write, no “re-sign” thrash).
      if (usingPublic && mediaUrlAlreadyPublic(row.media_url, publicBase, key)) {
        skippedAlreadyGood += 1;
        if (i === 1 || i % 100 === 0 || i === rows.length) {
          pipelineLog(
            `  refresh progress ${i}/${rows.length} (updated=${opts.stats.resigned} already_public=${skippedAlreadyGood})`,
            'info'
          );
        }
        continue;
      }

      // Name is legacy: with R2_PUBLIC_BASE_URL this returns a permanent public URL.
      const playUrl = await presignGet(client, key);
      let next = playUrl;
      const raw = (row.media_url || '').trim();
      if (raw.startsWith('{')) {
        try {
          const obj = JSON.parse(raw) as Record<string, unknown>;
          const urls = Array.isArray(obj.urls) ? [...obj.urls] : [];
          if (urls.length) urls[0] = playUrl;
          else urls.push(playUrl);
          obj.urls = urls;
          if (!obj.types) obj.types = ['video'];
          obj.r2_key = key;
          // Timestamp of last URL write (not “signature expiry” when public).
          obj.signed_at = new Date().toISOString();
          if (usingPublic) obj.url_mode = 'public_permanent';
          next = JSON.stringify(obj);
        } catch {
          const kind = packKindFromR2Key(key);
          next = encodeMediaUrl({
            signedUrl: playUrl,
            reel: kind === 'spark',
            r2Key: key,
            sourceId: key,
            kind,
          });
        }
      } else {
        const kind = packKindFromR2Key(key);
        next = encodeMediaUrl({
          signedUrl: playUrl,
          reel: kind === 'spark',
          r2Key: key,
          sourceId: key,
          kind,
        });
      }

      if (opts.dryRun) {
        opts.stats.resigned += 1;
      } else {
        await pool.query(
          `update public.posts set media_url = $2, updated_at = now() where id = $1::uuid`,
          [row.id, next]
        );
        opts.stats.resigned += 1;
      }
      if (i === 1 || i % 25 === 0 || i === rows.length) {
        pipelineLog(
          `  refresh progress ${i}/${rows.length} (updated=${opts.stats.resigned} already_public=${skippedAlreadyGood})`,
          'info'
        );
      }
    } catch (err: any) {
      opts.stats.errors.push(`resign ${row.id}: ${err?.message ?? err}`);
      pipelineLog(`  refresh fail ${row.id.slice(0, 8)}…: ${err?.message ?? err}`, 'error');
    }
  }
  if (skippedAlreadyGood > 0) {
    pipelineLog(
      `  skipped ${skippedAlreadyGood} already on permanent public URL`,
      'ok'
    );
  }
}

/** True when media_url already points at the permanent public object for this key. */
function mediaUrlAlreadyPublic(
  mediaUrl: string | null | undefined,
  publicBase: string,
  key: string
): boolean {
  if (!mediaUrl || !publicBase) return false;
  // Still has AWS query-sig → not permanent public.
  if (mediaUrl.includes('X-Amz-Signature') || mediaUrl.includes('X-Amz-Algorithm')) {
    return false;
  }
  const expected = `${publicBase.replace(/\/+$/, '')}/${key.replace(/^\/+/, '')}`;
  const raw = mediaUrl.trim();
  if (raw.startsWith('{')) {
    try {
      const obj = JSON.parse(raw) as { urls?: unknown[] };
      const first = Array.isArray(obj.urls) ? String(obj.urls[0] ?? '') : '';
      return first === expected;
    } catch {
      return false;
    }
  }
  return raw === expected;
}


