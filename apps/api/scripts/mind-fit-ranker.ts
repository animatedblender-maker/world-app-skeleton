/**
 * MIND-016 offline fit stub — co-occurrence priors → RankerWeights JSON.
 *
 * Not sklearn. Joins recent recommendation_decisions sources with engagement
 * positives and writes naive weights from feature presence rates.
 *
 *   cd apps/api && npx tsx scripts/mind-fit-ranker.ts
 *
 * Loads apps/api/.env. Writes apps/api/data/mind-ranker-weights.json.
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { RankerFeatures, RankerWeights } from '../src/recommendation/mind-trained-ranker.js';
import { DEFAULT_RANKER_WEIGHTS } from '../src/recommendation/mind-trained-ranker.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const envPath = path.join(root, '.env');
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, 'utf8').split('\n')) {
    const m = line.match(/^([A-Z0-9_]+)=(.*)$/);
    if (!m) continue;
    if (!process.env[m[1]!]) {
      process.env[m[1]!] = m[2]!.replace(/^["']|["']$/g, '');
    }
  }
}

const LOOKBACK_HOURS = Math.max(1, Number(process.env.LOOKBACK_HOURS) || 168);
const LIMIT = Math.min(Math.max(Number(process.env.LIMIT) || 5000, 100), 50_000);

const FEATURE_KEYS: (keyof RankerFeatures)[] = [
  'following',
  'affinity',
  'itemStats',
  'fresh',
  'bubble',
  'knn',
  'mediaTopic',
  'ann',
  'coldStart',
  'opportunity',
  'session',
  'muted',
];

/** Map decision source labels → RankerFeatures keys. */
const SOURCE_TO_FEATURE: Record<string, keyof RankerFeatures> = {
  following: 'following',
  affinity: 'affinity',
  item_stats: 'itemStats',
  fresh: 'fresh',
  bubble: 'bubble',
  outside_bubble: 'bubble',
  knn: 'knn',
  knn_creator: 'knn',
  media_topic: 'mediaTopic',
  ann: 'ann',
  cold_start: 'coldStart',
  cold_prior_country: 'coldStart',
  cold_prior_hub: 'coldStart',
  cold_prior_fresh: 'coldStart',
  cold_prior_quality: 'coldStart',
  cold_prior_ann: 'ann',
  cold_prior_bubble: 'bubble',
  opportunity: 'opportunity',
  session: 'session',
  muted_skip: 'muted',
};

type SourceEntry = { id?: string; sources?: string[] };

function parseSources(raw: unknown): SourceEntry[] {
  if (Array.isArray(raw)) return raw as SourceEntry[];
  if (typeof raw === 'string') {
    try {
      const p = JSON.parse(raw);
      return Array.isArray(p) ? (p as SourceEntry[]) : [];
    } catch {
      return [];
    }
  }
  return [];
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n));
}

async function main() {
  const { pool } = await import('../src/db.js');

  const { rows } = await pool.query<{
    request_id: string;
    sources: unknown;
  }>(
    `
    select request_id, sources
    from public.recommendation_decisions
    where created_at > now() - ($1::text || ' hours')::interval
    order by created_at desc
    limit $2
    `,
    [String(LOOKBACK_HOURS), LIMIT]
  );

  const itemIds: string[] = [];
  const itemFeatures = new Map<string, Set<keyof RankerFeatures>>();

  for (const r of rows) {
    for (const entry of parseSources(r.sources)) {
      if (!entry.id) continue;
      itemIds.push(entry.id);
      let feats = itemFeatures.get(entry.id);
      if (!feats) {
        feats = new Set();
        itemFeatures.set(entry.id, feats);
      }
      for (const s of entry.sources ?? []) {
        const key = SOURCE_TO_FEATURE[s];
        if (key) feats.add(key);
      }
    }
  }

  const uniqueItems = [...new Set(itemIds)].slice(0, 8000);
  const positive = new Set<string>();
  if (uniqueItems.length) {
    try {
      const { rows: eng } = await pool.query<{ content_id: string }>(
        `
        select distinct content_id::text
        from public.entity_engagement_events
        where content_id = any($1::uuid[])
          and strength > 0
          and occurred_at > now() - ($2::text || ' hours')::interval
        `,
        [uniqueItems, String(LOOKBACK_HOURS + 24)]
      );
      for (const e of eng) positive.add(e.content_id);
    } catch {
      /* sparse / missing engagement table */
    }
  }

  const servedWith: Record<keyof RankerFeatures, number> = {
    following: 0,
    affinity: 0,
    itemStats: 0,
    fresh: 0,
    bubble: 0,
    knn: 0,
    mediaTopic: 0,
    ann: 0,
    coldStart: 0,
    opportunity: 0,
    session: 0,
    muted: 0,
  };
  const positiveWith: Record<keyof RankerFeatures, number> = { ...servedWith };
  let labeled = 0;
  let positives = 0;

  for (const id of uniqueItems) {
    const feats = itemFeatures.get(id);
    if (!feats?.size) continue;
    labeled += 1;
    const isPos = positive.has(id);
    if (isPos) positives += 1;
    for (const f of feats) {
      servedWith[f] += 1;
      if (isPos) positiveWith[f] += 1;
    }
  }

  const baseRate = labeled > 0 ? positives / labeled : 0.15;
  const weights: Partial<Record<keyof RankerFeatures, number>> = {
    ...DEFAULT_RANKER_WEIGHTS.weights,
  };

  for (const key of FEATURE_KEYS) {
    const n = servedWith[key];
    if (n < 5) continue; // keep prior
    const hit = positiveWith[key] / n;
    // Log-odds lift vs base rate → soft weight around prior scale
    const lift =
      Math.log((hit + 0.02) / (1 - hit + 0.02)) -
      Math.log((baseRate + 0.02) / (1 - baseRate + 0.02));
    const prior = DEFAULT_RANKER_WEIGHTS.weights[key] ?? 0.3;
    if (key === 'muted') {
      weights[key] = clamp(prior + lift * 0.5, -5, -0.5);
    } else {
      weights[key] = clamp(prior * 0.4 + lift * 1.2, -1.5, 2.5);
    }
  }

  const bias = clamp(
    -Math.log((baseRate + 0.05) / (1 - baseRate + 0.05)) * 0.3,
    -1.5,
    0.5
  );

  const out: RankerWeights = {
    version: 'logistic.v0-fit-stub',
    bias: Math.round(bias * 1000) / 1000,
    weights,
    trainedAt: new Date().toISOString(),
  };

  const dataDir = path.join(root, 'data');
  fs.mkdirSync(dataDir, { recursive: true });
  const outPath = path.join(dataDir, 'mind-ranker-weights.json');
  fs.writeFileSync(outPath, JSON.stringify(out, null, 2) + '\n', 'utf8');

  const presenceRates: Record<string, { served: number; positive: number; rate: string }> =
    {};
  for (const key of FEATURE_KEYS) {
    const n = servedWith[key];
    presenceRates[key] = {
      served: n,
      positive: positiveWith[key],
      rate: n ? `${((100 * positiveWith[key]) / n).toFixed(1)}%` : 'n/a',
    };
  }

  console.log(
    JSON.stringify(
      {
        ok: true,
        harness: 'mind-fit-ranker',
        handbook: 'MIND-016 stub',
        path: outPath,
        lookbackHours: LOOKBACK_HOURS,
        decisions: rows.length,
        labeledItems: labeled,
        positiveItems: positives,
        baseRate: Math.round(baseRate * 1000) / 1000,
        presenceRates,
        weights: out,
        note: 'Co-occurrence prior stub — not a trained logistic. Enable with MIND_TRAINED_RANKER_ENABLED=1.',
      },
      null,
      2
    )
  );
  console.log(outPath);
  await pool.end();
}

main().catch(async (err) => {
  console.error(err);
  try {
    const { pool } = await import('../src/db.js');
    await pool.end();
  } catch {
    /* ignore */
  }
  process.exit(1);
});
