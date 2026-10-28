/**
 * MIND admin status aggregator — read-only snapshots for /mind.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from '../db.js';
import {
  MIND_CLIENT_EVENT_KEYS,
  MIND_NEGATIVE_EVENTS,
  MIND_POLICY_VERSION,
  MIND_POSITIVE_EVENTS,
  mindLedgerEnabled,
} from '../recommendation/mind-contracts.js';
import {
  isolationOverall,
  runMasqueradeIsolationChecks,
  type IsolationCheck,
} from '../recommendation/mind-isolation.js';
import {
  MIND_CANDIDATE_LANES,
  MIND_RETRIEVAL_BUDGETS,
  type CandidateLaneDef,
} from '../recommendation/mind-candidates.js';
import { MIND_INTEREST_SOURCES } from '../recommendation/mind-interest.js';
import {
  MIND_PURPOSE_BLURB,
  MIND_SURFACE_CATALOG,
  type MindSurfaceCatalogEntry,
} from '../recommendation/mind-surfaces.js';
import {
  getMediaUnderstandingStatus,
  MIND_MEDIA_FEATURE_CATALOG,
  type MediaUnderstandingStatus,
} from '../recommendation/mind-media.js';
import {
  getEmbeddingsStatus,
  type EmbeddingsStatus,
} from '../recommendation/mind-embeddings.js';
import {
  getMultimodalStatus,
  mindMultimodalEnabled,
  type MultimodalStatus,
} from '../recommendation/mind-multimodal.js';
import {
  getRerankStatus,
  type RerankStatus,
} from '../recommendation/mind-rerank.js';
import { getGuardianStatus } from '../recommendation/mind-guardian.js';
import { mindSessionFeaturesEnabled } from '../recommendation/mind-session.js';
import { mindOpportunityEnabled } from '../recommendation/mind-opportunity.js';
import { mindTrainedRankerEnabled } from '../recommendation/mind-trained-ranker.js';
import { mindHybridSearchEnabled } from '../recommendation/mind-search.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
function resolveDocsMind(): string {
  // Prefer apps/api/docs/mind (ships on Render Root Directory apps/api).
  // Fall back to monorepo docs/mind for local checkouts.
  const candidates = [
    path.resolve(__dirname, '../../docs/mind'), // dist/ops or src/ops → apps/api/docs/mind
    path.resolve(process.cwd(), 'docs/mind'),
    path.resolve(__dirname, '../../../../docs/mind'),
    path.resolve(process.cwd(), '../../docs/mind'),
  ];
  for (const c of candidates) {
    if (fs.existsSync(c)) return c;
  }
  return candidates[0]!;
}
const REPO_DOCS_MIND = resolveDocsMind();
const SEED_LOG = path.resolve(
  '/Volumes/MatteryaSSD/Development/tmp/masquerade-seed/full_seed.log'
);
const SEED_PID = path.resolve(
  '/Volumes/MatteryaSSD/Development/tmp/masquerade-seed/full_seed.pid'
);

export type MindStatus = {
  ok: true;
  at: string;
  policyVersion: string;
  flags: {
    mindLedgerEnabled: boolean;
    mindSessionFeatures: boolean;
    mindOpportunity: boolean;
    mindTrainedRanker: boolean;
    mindHybridSearch: boolean;
    mindRerank: boolean;
    mindMultimodal: boolean;
  };
  guardian?: {
    openPostReports: number;
    openCommentReports: number;
    moderationReviewHeld: number;
    recentQueue: {
      entityType: string;
      entityId: string;
      decision: string;
      servingStatus: string | null;
      excerpt: string | null;
      createdAt: string;
    }[];
    policyNote: string;
  };
  ledger: {
    deliveries: number;
    batches: number;
    deliveries24h: number;
    bySurface: { surface: string; n: number }[];
  };
  engagement: {
    events: number;
    events1h: number;
    events24h: number;
    positives1h: number;
    negatives1h: number;
    byType1h: { type: string; n: number }[];
    allowlistSize: number;
  };
  decisions: {
    count24h: number;
    recent: {
      at: string;
      surface: string;
      policy: string;
      served: number;
      latencyMs: number;
      requestId: string;
      annHits?: number | null;
      mmAnnHits?: number | null;
      topicHits?: number | null;
    }[];
  };
  candidates: {
    lanes: CandidateLaneDef[];
    budgets: typeof MIND_RETRIEVAL_BUDGETS;
    inventory: { lane: string; n: number }[];
  };
  interest: {
    sources: typeof MIND_INTEREST_SOURCES;
    personalityRows: number;
    personalityWarm: number;
    creatorAffinityRows: number;
    itemStatsRows: number;
    recentHits: {
      withAffinity: number;
      withPersonality: number;
      sample: number;
    };
  };
  purpose: {
    blurb: string;
    surfaces: MindSurfaceCatalogEntry[];
  };
  mediaUnderstanding: MediaUnderstandingStatus;
  embeddings: EmbeddingsStatus;
  multimodal: MultimodalStatus;
  rerank: RerankStatus;
  masquerade: {
    rooms: { slug: string; title: string; posts: number }[];
    posts: number;
    r2media: number;
    isolation: {
      overall: 'pass' | 'fail' | 'warn';
      note: string;
      checks: IsolationCheck[];
    };
  };
  seed: {
    available: boolean;
    phase: string | null;
    progressLine: string | null;
    done: number | null;
    total: number | null;
    inserted: number | null;
    pidAlive: boolean | null;
  };
  gapSummary: { shipped: number; partial: number; missing: number };
  docs: { slug: string; title: string }[];
  recent: { kind: string; at: string; text: string }[];
};

function readSeedProgress(): MindStatus['seed'] {
  const available = fs.existsSync(SEED_LOG);
  let pidAlive: boolean | null = null;
  try {
    if (fs.existsSync(SEED_PID)) {
      const pid = Number(fs.readFileSync(SEED_PID, 'utf8').trim());
      if (Number.isFinite(pid) && pid > 0) {
        try {
          process.kill(pid, 0);
          pidAlive = true;
        } catch {
          pidAlive = false;
        }
      }
    }
  } catch {
    pidAlive = null;
  }

  if (!available) {
    return {
      available: false,
      phase: null,
      progressLine: null,
      done: null,
      total: null,
      inserted: null,
      pidAlive,
    };
  }

  let text = '';
  try {
    text = fs.readFileSync(SEED_LOG, 'utf8');
  } catch {
    return {
      available: false,
      phase: null,
      progressLine: null,
      done: null,
      total: null,
      inserted: null,
      pidAlive,
    };
  }

  const phases = [...text.matchAll(/===\s*PHASE\s+(\S+)/g)];
  const phase = phases.length ? phases[phases.length - 1]![1]! : null;
  const prog = [
    ...text.matchAll(
      /[.…]+\s*(\d+)\s*\/\s*(\d+)\s+inserted=(\d+)\s+skipped=(\d+)/g
    ),
  ];
  const last = prog.length ? prog[prog.length - 1]! : null;
  const progressLine = last ? last[0]! : null;

  return {
    available: true,
    phase,
    progressLine,
    done: last ? Number(last[1]) : null,
    total: last ? Number(last[2]) : null,
    inserted: last ? Number(last[3]) : null,
    pidAlive,
  };
}

function listDocs(): { slug: string; title: string }[] {
  const out: { slug: string; title: string }[] = [
    { slug: 'readme', title: 'MIND overview' },
    { slug: '00-audit', title: 'Phase 0 audit' },
    { slug: '01-gap-matrix', title: 'Gap matrix' },
    { slug: 'adr-0001', title: 'ADR: reuse delivery ledger' },
    { slug: 'adr-0002', title: 'ADR: REST for Phase 1' },
    { slug: 'runbook', title: 'Admin console runbook' },
    { slug: 'implementation', title: 'What we shipped (log)' },
    { slug: 'handbook', title: 'Full engineering handbook' },
  ];
  return out;
}

const DOC_FILES: Record<string, string> = {
  readme: 'README.md',
  '00-audit': '00-audit.md',
  '01-gap-matrix': '01-gap-matrix.md',
  'adr-0001': 'adr/0001-ledger-reuse-feed-video-delivery.md',
  'adr-0002': 'adr/0002-rest-not-graphql-for-v1.md',
  runbook: 'runbooks/admin-mind-console.md',
  implementation: 'IMPLEMENTATION_LOG.md',
  handbook: 'Matterya_MIND_Engineering_Handbook.md',
};

export function readMindDoc(slug: string): string | null {
  const rel = DOC_FILES[slug];
  if (!rel) return null;
  const full = path.join(REPO_DOCS_MIND, rel);
  try {
    return fs.readFileSync(full, 'utf8');
  } catch {
    return null;
  }
}

/** Short TTL — /mind polls ~5s; full COUNTs every tick burn Disk IO budget. */
const MIND_STATUS_TTL_MS = 20_000;
let mindStatusCache: { at: number; value: MindStatus } | null = null;

export async function getMindStatus(): Promise<MindStatus> {
  const now = Date.now();
  if (mindStatusCache && now - mindStatusCache.at < MIND_STATUS_TTL_MS) {
    return mindStatusCache.value;
  }
  const value = await buildMindStatus();
  mindStatusCache = { at: now, value };
  return value;
}

async function buildMindStatus(): Promise<MindStatus> {
  const ledger = {
    deliveries: 0,
    batches: 0,
    deliveries24h: 0,
    bySurface: [] as { surface: string; n: number }[],
  };
  const engagement: MindStatus['engagement'] = {
    events: 0,
    events1h: 0,
    events24h: 0,
    positives1h: 0,
    negatives1h: 0,
    byType1h: [],
    allowlistSize: MIND_CLIENT_EVENT_KEYS.length,
  };
  const decisions: MindStatus['decisions'] = { count24h: 0, recent: [] };
  const candidates: MindStatus['candidates'] = {
    lanes: MIND_CANDIDATE_LANES,
    budgets: MIND_RETRIEVAL_BUDGETS,
    inventory: [],
  };
  const interest: MindStatus['interest'] = {
    sources: MIND_INTEREST_SOURCES,
    personalityRows: 0,
    personalityWarm: 0,
    creatorAffinityRows: 0,
    itemStatsRows: 0,
    recentHits: { withAffinity: 0, withPersonality: 0, sample: 0 },
  };
  const purpose: MindStatus['purpose'] = {
    blurb: MIND_PURPOSE_BLURB,
    surfaces: MIND_SURFACE_CATALOG,
  };
  const masquerade: MindStatus['masquerade'] = {
    rooms: [],
    posts: 0,
    r2media: 0,
    isolation: {
      overall: 'pass',
      note: 'Public ranker reads public.* only; Masquerade feed uses anonymous.* separately.',
      checks: [],
    },
  };
  const recent: MindStatus['recent'] = [];

  try {
    const { rows } = await pool.query<{
      deliveries: string;
      batches: string;
      d24: string;
    }>(`
      select
        (select count(*)::text from public.feed_video_delivery) as deliveries,
        (select count(*)::text from public.feed_batch) as batches,
        (select count(*)::text from public.feed_video_delivery
          where delivered_at > now() - interval '24 hours') as d24
    `);
    const r = rows[0];
    if (r) {
      ledger.deliveries = Number(r.deliveries) || 0;
      ledger.batches = Number(r.batches) || 0;
      ledger.deliveries24h = Number(r.d24) || 0;
    }
  } catch {
    /* schema may be missing on fresh envs */
  }

  try {
    const { rows } = await pool.query<{ surface: string; n: string }>(`
      select surface, count(*)::text as n
      from public.feed_video_delivery
      group by surface
      order by count(*) desc
    `);
    ledger.bySurface = rows.map((x) => ({
      surface: x.surface,
      n: Number(x.n) || 0,
    }));
  } catch {
    /* ignore */
  }

  try {
    const { rows } = await pool.query<{
      n: string;
      n1h: string;
      n24: string;
      pos1h: string;
      neg1h: string;
    }>(`
      select
        count(*)::text as n,
        count(*) filter (where occurred_at > now() - interval '1 hour')::text as n1h,
        count(*) filter (where occurred_at > now() - interval '24 hours')::text as n24,
        count(*) filter (
          where occurred_at > now() - interval '1 hour'
            and event_type = any($1::text[])
        )::text as pos1h,
        count(*) filter (
          where occurred_at > now() - interval '1 hour'
            and event_type = any($2::text[])
        )::text as neg1h
      from public.entity_engagement_events
    `, [Array.from(MIND_POSITIVE_EVENTS), Array.from(MIND_NEGATIVE_EVENTS)]);
    const r = rows[0];
    if (r) {
      engagement.events = Number(r.n) || 0;
      engagement.events1h = Number(r.n1h) || 0;
      engagement.events24h = Number(r.n24) || 0;
      engagement.positives1h = Number(r.pos1h) || 0;
      engagement.negatives1h = Number(r.neg1h) || 0;
    }
  } catch {
    /* ignore */
  }

  try {
    const { rows } = await pool.query<{ type: string; n: string }>(`
      select event_type as type, count(*)::text as n
      from public.entity_engagement_events
      where occurred_at > now() - interval '1 hour'
      group by event_type
      order by count(*) desc
      limit 12
    `);
    engagement.byType1h = rows.map((x) => ({
      type: x.type,
      n: Number(x.n) || 0,
    }));
  } catch {
    /* ignore */
  }

  try {
    const { rows } = await pool.query<{ n: string }>(`
      select count(*)::text as n
      from public.recommendation_decisions
      where created_at > now() - interval '24 hours'
    `);
    decisions.count24h = Number(rows[0]?.n) || 0;
  } catch {
    /* ignore */
  }

  try {
    const { rows } = await pool.query<{
      created_at: Date;
      surface: string;
      policy_version: string;
      served_count: number;
      latency_ms: number;
      request_id: string;
      meta: { featureHits?: { annHits?: number; mmAnnHits?: number; topicHits?: number } } | null;
    }>(`
      select created_at, surface, policy_version, served_count, latency_ms, request_id, meta
      from public.recommendation_decisions
      order by created_at desc
      limit 10
    `);
    decisions.recent = rows.map((r) => {
      const fh = r.meta?.featureHits;
      return {
        at: new Date(r.created_at).toISOString(),
        surface: r.surface,
        policy: r.policy_version,
        served: Number(r.served_count) || 0,
        latencyMs: Number(r.latency_ms) || 0,
        requestId: String(r.request_id).slice(0, 36),
        annHits: fh?.annHits ?? null,
        mmAnnHits: fh?.mmAnnHits ?? null,
        topicHits: fh?.topicHits ?? null,
      };
    });
    for (const r of decisions.recent.slice(0, 5)) {
      const mm = r.mmAnnHits != null ? ` · mmAnn=${r.mmAnnHits}` : '';
      recent.push({
        kind: 'decision',
        at: r.at,
        text: `${r.surface} · served=${r.served} · ${r.latencyMs}ms · ${r.policy}${mm}`,
      });
    }
  } catch {
    /* ignore */
  }

  try {
    const { rows } = await pool.query<{
      slug: string;
      title: string;
      posts: string;
    }>(`
      select normalized_slug as slug, title,
             coalesce(post_count, 0)::text as posts
      from anonymous.spaces
      where status = 'active'
      order by normalized_slug
    `);
    masquerade.rooms = rows.map((x) => ({
      slug: x.slug,
      title: x.title,
      posts: Number(x.posts) || 0,
    }));
  } catch {
    /* ignore */
  }

  try {
    const { rows } = await pool.query<{ n: string; r2: string }>(`
      select
        count(*)::text as n,
        count(*) filter (where source_ref like 'r2media:%')::text as r2
      from anonymous.posts
      where state = 'active'
    `);
    const r = rows[0];
    if (r) {
      masquerade.posts = Number(r.n) || 0;
      masquerade.r2media = Number(r.r2) || 0;
    }
  } catch {
    /* ignore */
  }

  try {
    const { rows } = await pool.query<{
      surface: string;
      delivered_at: Date;
      canonical_video_id: string;
    }>(`
      select surface, delivered_at, left(canonical_video_id, 64) as canonical_video_id
      from public.feed_video_delivery
      order by delivered_at desc
      limit 8
    `);
    for (const r of rows) {
      recent.push({
        kind: 'delivery',
        at: new Date(r.delivered_at).toISOString(),
        text: `${r.surface} · ${r.canonical_video_id}`,
      });
    }
  } catch {
    /* ignore */
  }

  try {
    const { rows } = await pool.query<{ lane: string; n: string }>(`
      select 'home_sparkish'::text as lane, count(*)::text as n
      from public.posts p
      where coalesce(p.visibility,'public') = 'public'
        and (
          coalesce(p.media_path,'') ilike '%/ShortForm/%'
          or coalesce(p.media_url,'') ilike '%/ShortForm/%'
          or coalesce(p.body,'') like '%__spark__%'
        )
      union all
      select 'home_hubish', count(*)::text
      from public.posts p
      where coalesce(p.visibility,'public') = 'public'
        and (
          coalesce(p.media_path,'') ilike '%/LongForm/%'
          or coalesce(p.media_url,'') ilike '%/LongForm/%'
          or coalesce(p.body,'') like '%__hub_origin__%'
        )
      union all
      select 'home_image', count(*)::text
      from public.posts p
      where coalesce(p.visibility,'public') = 'public'
        and lower(coalesce(p.media_type,'')) in ('image','photo','gif')
      union all
      select 'masquerade_posts', count(*)::text
      from anonymous.posts
      where state = 'active'
    `);
    candidates.inventory = rows.map((r) => ({
      lane: r.lane,
      n: Number(r.n) || 0,
    }));
  } catch {
    /* ignore inventory probe failures */
  }

  try {
    const { rows } = await pool.query<{
      personality: string;
      warm: string;
      affinity: string;
      items: string;
    }>(`
      select
        (select count(*)::text from public.entity_personality) as personality,
        (select count(*)::text from public.entity_personality where events_counted > 0) as warm,
        (select count(*)::text from public.recsys_user_creator_affinity) as affinity,
        (select count(*)::text from public.recsys_item_stats) as items
    `);
    const r = rows[0];
    if (r) {
      interest.personalityRows = Number(r.personality) || 0;
      interest.personalityWarm = Number(r.warm) || 0;
      interest.creatorAffinityRows = Number(r.affinity) || 0;
      interest.itemStatsRows = Number(r.items) || 0;
    }
  } catch {
    /* ignore */
  }

  try {
    const { rows } = await pool.query<{
      sample: string;
      with_aff: string;
      with_pers: string;
    }>(`
      select
        count(*)::text as sample,
        count(*) filter (
          where coalesce((meta->'featureHits'->>'affinityCreators')::int, 0) > 0
        )::text as with_aff,
        count(*) filter (
          where coalesce(meta->'featureHits'->>'personality', 'false') = 'true'
        )::text as with_pers
      from (
        select meta from public.recommendation_decisions
        order by created_at desc
        limit 200
      ) t
    `);
    const r = rows[0];
    if (r) {
      interest.recentHits = {
        sample: Number(r.sample) || 0,
        withAffinity: Number(r.with_aff) || 0,
        withPersonality: Number(r.with_pers) || 0,
      };
    }
  } catch {
    /* ignore */
  }

  try {
    const checks = await runMasqueradeIsolationChecks();
    masquerade.isolation = {
      overall: isolationOverall(checks),
      note: 'Public ranker reads public.* only; Masquerade feed uses anonymous.* separately. Link table is ledger identity only.',
      checks,
    };
  } catch (err: any) {
    masquerade.isolation = {
      overall: 'warn',
      note: err?.message ?? 'isolation checks failed',
      checks: [],
    };
  }

  let mediaUnderstanding: MediaUnderstandingStatus;
  try {
    mediaUnderstanding = await getMediaUnderstandingStatus();
  } catch (err: any) {
    mediaUnderstanding = {
      pipelineVersion: 'media.v1',
      enabled: false,
      groqConfigured: !!process.env.GROQ_API_KEY?.trim(),
      transcripts: [],
      features: 0,
      readyWithFeatures: 0,
      catalog: MIND_MEDIA_FEATURE_CATALOG,
    };
    console.warn('[mind-status] mediaUnderstanding', err?.message ?? err);
  }

  let embeddings: EmbeddingsStatus;
  try {
    embeddings = await getEmbeddingsStatus();
  } catch (err: any) {
    embeddings = {
      enabled: false,
      configured: !!process.env.VOYAGE_API_KEY?.trim(),
      model: 'voyage-4-lite',
      modelVersion: 'voyage:voyage-4-lite',
      dims: 1024,
      rows: 0,
      source: 'title_body',
    };
    console.warn('[mind-status] embeddings', err?.message ?? err);
  }

  let multimodal: MultimodalStatus;
  try {
    multimodal = await getMultimodalStatus();
  } catch (err: any) {
    multimodal = {
      enabled: mindMultimodalEnabled(),
      configured: !!process.env.VOYAGE_API_KEY?.trim(),
      model: 'voyage-multimodal-3.5',
      modelVersion: 'voyage:voyage-multimodal-3.5',
      dims: 1024,
      rows: 0,
      source: 'sparks_thumb+image',
      sparksEligible: 0,
      videoEligible: 0,
      imageEligible: 0,
      videoRows: 0,
      imageRows: 0,
    };
    console.warn('[mind-status] multimodal', err?.message ?? err);
  }

  const rerank = getRerankStatus();

  let guardian;
  try {
    guardian = await getGuardianStatus();
  } catch (err: any) {
    guardian = {
      openPostReports: 0,
      openCommentReports: 0,
      moderationReviewHeld: 0,
      recentQueue: [],
      policyNote: `guardian unavailable: ${err?.message ?? err}`,
    };
  }

  return {
    ok: true,
    at: new Date().toISOString(),
    policyVersion: MIND_POLICY_VERSION,
    flags: {
      mindLedgerEnabled: mindLedgerEnabled(),
      mindSessionFeatures: mindSessionFeaturesEnabled(),
      mindOpportunity: mindOpportunityEnabled(),
      mindTrainedRanker: mindTrainedRankerEnabled(),
      mindHybridSearch: mindHybridSearchEnabled(),
      mindRerank: rerank.enabled,
      mindMultimodal: multimodal.enabled,
    },
    ledger,
    engagement,
    masquerade,
    seed: readSeedProgress(),
    // Phase 3b+4.v2 (+ Sparks multimodal); missing = §14 ads auction / §15 GraphQL FeedItem
    gapSummary: { shipped: 17, partial: 3, missing: 2 },
    docs: listDocs(),
    recent,
    decisions,
    candidates,
    interest,
    purpose,
    mediaUnderstanding,
    embeddings,
    multimodal,
    rerank,
    guardian,
  };
}
