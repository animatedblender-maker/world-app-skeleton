/**
 * MIND §18 offline eval stub (Phase 3a / MIND-014 leftover → Phase 3).
 *
 * Reads logged `recommendation_decisions` (+ optional engagement join) and
 * prints offline metrics. No trained model — baseline measurement harness.
 *
 *   cd apps/api && npx tsx scripts/mind-offline-eval.ts
 *   LOOKBACK_HOURS=48 SURFACE=home_for_you npx tsx scripts/mind-offline-eval.ts
 *
 * Requires DATABASE_URL (loads apps/api/.env).
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

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
const SURFACE = (process.env.SURFACE || '').trim(); // empty = all
const LIMIT = Math.min(Math.max(Number(process.env.LIMIT) || 5000, 100), 50_000);

type DecisionRow = {
  request_id: string;
  entity_id: string;
  surface: string;
  policy_version: string;
  served_count: number;
  latency_ms: number | null;
  sources: unknown;
  meta: unknown;
  created_at: Date;
};

type SourceEntry = { id?: string; sources?: string[] };

function asObj(v: unknown): Record<string, unknown> | null {
  if (!v) return null;
  if (typeof v === 'object') return v as Record<string, unknown>;
  if (typeof v === 'string') {
    try {
      return JSON.parse(v) as Record<string, unknown>;
    } catch {
      return null;
    }
  }
  return null;
}

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

function pct(n: number, d: number): string {
  if (!d) return '0.0%';
  return `${((100 * n) / d).toFixed(1)}%`;
}

function mean(xs: number[]): number {
  if (!xs.length) return 0;
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

function percentile(xs: number[], p: number): number {
  if (!xs.length) return 0;
  const s = [...xs].sort((a, b) => a - b);
  const i = Math.min(s.length - 1, Math.max(0, Math.floor((p / 100) * (s.length - 1))));
  return s[i]!;
}

async function main() {
  const { pool } = await import('../src/db.js');

  const params: unknown[] = [LOOKBACK_HOURS, LIMIT];
  let surfaceClause = '';
  if (SURFACE) {
    params.push(SURFACE);
    surfaceClause = ` and surface = $3`;
  }

  const { rows } = await pool.query<DecisionRow>(
    `
    select request_id, entity_id::text, surface, policy_version,
           served_count, latency_ms, sources, meta, created_at
    from public.recommendation_decisions
    where created_at > now() - ($1::text || ' hours')::interval
    ${surfaceClause}
    order by created_at desc
    limit $2
    `,
    params
  );

  if (!rows.length) {
    console.log(
      JSON.stringify(
        {
          ok: false,
          error: 'no recommendation_decisions in window',
          lookbackHours: LOOKBACK_HOURS,
          surface: SURFACE || null,
        },
        null,
        2
      )
    );
    await pool.end();
    process.exit(1);
  }

  const sourceCounts = new Map<string, number>();
  const policyCounts = new Map<string, number>();
  const surfaceCounts = new Map<string, number>();
  const latencies: number[] = [];
  let coldDecisions = 0;
  let warmDecisions = 0;
  let coldStartHitsTotal = 0;
  let annHitDecisions = 0;
  let decisionsWithEngagement = 0;
  let positiveHits = 0;
  let servedItems = 0;
  const entityIds = new Set<string>();

  // Collect served item ids for engagement join (cap)
  const itemIds: string[] = [];
  const decisionItemMap = new Map<string, string[]>(); // request_id → item ids

  for (const r of rows) {
    entityIds.add(r.entity_id);
    policyCounts.set(r.policy_version, (policyCounts.get(r.policy_version) ?? 0) + 1);
    surfaceCounts.set(r.surface, (surfaceCounts.get(r.surface) ?? 0) + 1);
    if (r.latency_ms != null) latencies.push(Number(r.latency_ms));

    const meta = asObj(r.meta);
    const fh = (meta?.featureHits as Record<string, unknown> | undefined) ?? null;
    const isCold = fh?.coldStart === true;
    if (isCold) {
      coldDecisions += 1;
      coldStartHitsTotal += Number(fh?.coldStartHits) || 0;
    } else if (fh && 'coldStart' in fh) {
      warmDecisions += 1;
    } else {
      // Pre-v5 decisions: treat personality=false + low affinity as unknown
      warmDecisions += 1;
    }
    if (Number(fh?.annHits) > 0) annHitDecisions += 1;

    const srcs = parseSources(r.sources);
    const ids: string[] = [];
    for (const entry of srcs) {
      if (entry.id) {
        ids.push(entry.id);
        itemIds.push(entry.id);
      }
      for (const s of entry.sources ?? []) {
        sourceCounts.set(s, (sourceCounts.get(s) ?? 0) + 1);
      }
    }
    servedItems += ids.length || Number(r.served_count) || 0;
    decisionItemMap.set(r.request_id, ids);
  }

  // Engagement join: any positive event on served items within ±2h of decision (proxy label)
  const uniqueItems = [...new Set(itemIds)].slice(0, 8000);
  const positiveByItem = new Map<string, number>();
  if (uniqueItems.length) {
    try {
      const { rows: eng } = await pool.query<{ content_id: string; n: number }>(
        `
        select content_id::text, count(*)::int as n
        from public.entity_engagement_events
        where content_id = any($1::uuid[])
          and strength > 0
          and occurred_at > now() - ($2::text || ' hours')::interval
        group by content_id
        `,
        [uniqueItems, String(LOOKBACK_HOURS + 24)]
      );
      for (const e of eng) positiveByItem.set(e.content_id, Number(e.n) || 0);
    } catch {
      /* engagement table may be sparse */
    }
  }

  let labeledDecisions = 0;
  let hitAt1 = 0;
  let hitAt5 = 0;
  let hitAt10 = 0;
  const ndcgScores: number[] = [];

  for (const [, ids] of decisionItemMap) {
    if (!ids.length) continue;
    const labels = ids.map((id) => (positiveByItem.get(id) ?? 0) > 0);
    if (!labels.some(Boolean) && !labels.length) continue;
    labeledDecisions += 1;
    if (labels.some(Boolean)) decisionsWithEngagement += 1;
    if (labels[0]) hitAt1 += 1;
    if (labels.slice(0, 5).some(Boolean)) hitAt5 += 1;
    if (labels.slice(0, 10).some(Boolean)) hitAt10 += 1;
    // Binary DCG@K / IDCG@K with K=min(10,n)
    const k = Math.min(10, labels.length);
    let dcg = 0;
    let ideal = 0;
    const idealLabels = [...labels].sort((a, b) => Number(b) - Number(a));
    for (let i = 0; i < k; i++) {
      const rel = labels[i] ? 1 : 0;
      const irel = idealLabels[i] ? 1 : 0;
      const denom = Math.log2(i + 2);
      dcg += rel / denom;
      ideal += irel / denom;
      if (rel) positiveHits += 1;
    }
    ndcgScores.push(ideal > 0 ? dcg / ideal : 0);
  }

  const topSources = [...sourceCounts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 20)
    .map(([source, count]) => ({ source, count }));

  const report = {
    ok: true,
    harness: 'mind-offline-eval',
    handbook: '§18 / Phase 3a stub',
    window: {
      lookbackHours: LOOKBACK_HOURS,
      surfaceFilter: SURFACE || null,
      decisions: rows.length,
      uniqueEntities: entityIds.size,
      servedItems,
    },
    latencyMs: {
      mean: Math.round(mean(latencies) * 10) / 10,
      p50: percentile(latencies, 50),
      p95: percentile(latencies, 95),
      p99: percentile(latencies, 99),
    },
    coldStart: {
      coldDecisions,
      warmDecisions,
      coldShare: pct(coldDecisions, coldDecisions + warmDecisions),
      avgColdStartHitsPerColdDecision:
        coldDecisions > 0
          ? Math.round((coldStartHitsTotal / coldDecisions) * 100) / 100
          : 0,
      note: 'coldStart flag only present on server.v5-cold-start+ decisions',
    },
    retrieval: {
      decisionsWithAnnHits: annHitDecisions,
      annShare: pct(annHitDecisions, rows.length),
      topSources,
    },
    policyVersions: Object.fromEntries(policyCounts),
    surfaces: Object.fromEntries(surfaceCounts),
    engagementProxy: {
      labeledDecisions,
      decisionsWithAnyPositiveOnServed: decisionsWithEngagement,
      hitRateAt1: pct(hitAt1, labeledDecisions),
      hitRateAt5: pct(hitAt5, labeledDecisions),
      hitRateAt10: pct(hitAt10, labeledDecisions),
      ndcgAt10Mean: Math.round(mean(ndcgScores) * 1000) / 1000,
      caveat:
        'Binary relevance = any positive engagement on served id in lookback; not a true satisfaction label. Time-split / session leakage not yet enforced.',
    },
    nextSteps: [
      'Compare cold vs warm hit@k after server.v5-cold-start traffic accumulates',
      'Add time-based train/eval split before MIND-016 trained ranker',
      'Gate Phase 3b on offline lift + fairness slices (handbook Phase 3 gate)',
    ],
  };

  console.log(JSON.stringify(report, null, 2));
  await pool.end();
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
