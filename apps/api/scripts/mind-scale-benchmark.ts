/**
 * Phase 5 readiness probe (ADR 0004).
 *
 * Measures current-stack load signals — not a full load test.
 * Phase 5 infra still requires a separate ADR + cost projection.
 *
 *   cd apps/api && npx tsx scripts/mind-scale-benchmark.ts
 *
 * Loads apps/api/.env.
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

/** Placeholders from ADR 0004 — raise only with measured evidence. */
const P95_LATENCY_MS_GATE = 3000;
const DECISIONS_24H_GATE = 500_000;

function percentile(xs: number[], p: number): number {
  if (!xs.length) return 0;
  const s = [...xs].sort((a, b) => a - b);
  const i = Math.min(
    s.length - 1,
    Math.max(0, Math.floor((p / 100) * (s.length - 1)))
  );
  return s[i]!;
}

async function timed<T>(fn: () => Promise<T>): Promise<{ ms: number; value: T }> {
  const t0 = performance.now();
  const value = await fn();
  return { ms: Math.round((performance.now() - t0) * 10) / 10, value };
}

async function main() {
  const { pool } = await import('../src/db.js');

  const select1 = await timed(async () => {
    await pool.query(`select 1`);
    return true;
  });

  let decisions24h = 0;
  const latencies: number[] = [];
  try {
    const { rows: c } = await pool.query<{ n: string }>(
      `
      select count(*)::text as n
      from public.recommendation_decisions
      where created_at > now() - interval '24 hours'
      `
    );
    decisions24h = Number(c[0]?.n) || 0;

    const { rows } = await pool.query<{ latency_ms: number }>(
      `
      select latency_ms
      from public.recommendation_decisions
      where created_at > now() - interval '24 hours'
        and latency_ms is not null
      order by created_at desc
      limit 20000
      `
    );
    for (const r of rows) latencies.push(Number(r.latency_ms));
  } catch (err: any) {
    console.warn('[mind-scale-benchmark] decisions', err?.message ?? err);
  }

  let embeddingsCount = 0;
  let embeddingsTable = false;
  try {
    const { rows } = await pool.query<{ n: string }>(
      `select count(*)::text as n from public.mind_content_embeddings`
    );
    embeddingsTable = true;
    embeddingsCount = Number(rows[0]?.n) || 0;
  } catch {
    embeddingsTable = false;
  }

  let annProbe: { ms: number; rows: number; note: string } = {
    ms: 0,
    rows: 0,
    note: 'mind_content_embeddings missing — skipped',
  };
  if (embeddingsTable && embeddingsCount > 0) {
    const probe = await timed(async () => {
      try {
        const { rows } = await pool.query<{ post_id: string }>(
          `
          select e.post_id::text
          from public.mind_content_embeddings e
          order by e.embedding <=> (
            select embedding from public.mind_content_embeddings limit 1
          )
          limit 8
          `
        );
        return rows.length;
      } catch (err: any) {
        annProbe.note = err?.message ?? 'ann probe failed';
        return 0;
      }
    });
    annProbe = {
      ms: probe.ms,
      rows: probe.value,
      note:
        probe.value > 0
          ? 'self-neighbor order by <=> limit 8'
          : annProbe.note || 'no rows',
    };
  }

  const p50 = percentile(latencies, 50);
  const p95 = percentile(latencies, 95);
  const scaleNeeded =
    p95 > P95_LATENCY_MS_GATE || decisions24h > DECISIONS_24H_GATE;

  const report = {
    ok: true,
    harness: 'mind-scale-benchmark',
    handbook: 'ADR 0004 / Phase 5 gate',
    scaleNeeded,
    gates: {
      p95LatencyMs: P95_LATENCY_MS_GATE,
      decisions24h: DECISIONS_24H_GATE,
    },
    decisions24h: {
      count: decisions24h,
      latencySample: latencies.length,
      latencyMs: {
        p50,
        p95,
      },
    },
    embeddings: {
      tablePresent: embeddingsTable,
      rows: embeddingsCount,
    },
    probes: {
      select1Ms: select1.ms,
      annIsh: annProbe,
    },
    note:
      'Phase 5 infra (feature store, ANN cluster, serving autoscaling) requires a separate ADR + cost projection. This script only reports whether measured placeholders suggest scale work.',
  };

  console.log(JSON.stringify(report, null, 2));
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
