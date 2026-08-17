/**
 * Client performance milestones ingest (butter-smooth §1).
 * In-memory ring for now — Grafana remote_write / Postgres later.
 * No UI. Bounded memory.
 */

export type MetricEventIn = {
  name?: string;
  surface?: string;
  durationMs?: number;
  t0?: number;
  t1?: number;
  ok?: boolean;
  traceId?: string;
  meta?: Record<string, unknown>;
};

export type MetricBatchIn = {
  sessionId?: string;
  appVersion?: string;
  os?: string;
  deviceClass?: string;
  events?: MetricEventIn[];
};

type Stored = {
  at: number;
  sessionId: string;
  appVersion: string;
  os: string;
  deviceClass: string;
  name: string;
  surface: string;
  durationMs: number;
  ok: boolean;
  traceId: string | null;
};

const MAX = 5_000;
const ring: Stored[] = [];
/** name → durations (last N) for cheap p50/p95 */
const byName = new Map<string, number[]>();
const MAX_PER_NAME = 500;

function pushDuration(name: string, ms: number) {
  let arr = byName.get(name);
  if (!arr) {
    arr = [];
    byName.set(name, arr);
  }
  arr.push(ms);
  if (arr.length > MAX_PER_NAME) arr.splice(0, arr.length - MAX_PER_NAME);
}

function percentile(sorted: number[], p: number): number {
  if (sorted.length === 0) return 0;
  const idx = Math.min(sorted.length - 1, Math.max(0, Math.ceil((p / 100) * sorted.length) - 1));
  return sorted[idx] ?? 0;
}

export function ingestMetricBatch(body: MetricBatchIn): { accepted: number; rejected: number } {
  const sessionId = String(body.sessionId ?? '').slice(0, 128) || 'anon';
  const appVersion = String(body.appVersion ?? '').slice(0, 32);
  const os = String(body.os ?? 'unknown').slice(0, 16);
  const deviceClass = String(body.deviceClass ?? 'unknown').slice(0, 64);
  const events = Array.isArray(body.events) ? body.events.slice(0, 50) : [];

  let accepted = 0;
  let rejected = 0;
  const now = Date.now();

  for (const e of events) {
    const name = String(e?.name ?? '').trim().slice(0, 80);
    if (!name) {
      rejected += 1;
      continue;
    }
    const durationMs = Math.min(
      Math.max(0, Math.floor(Number(e.durationMs) || 0)),
      600_000
    );
    const surface = String(e.surface ?? 'app').slice(0, 32);
    const ok = e.ok !== false;
    const traceId = e.traceId ? String(e.traceId).slice(0, 64) : null;

    const row: Stored = {
      at: now,
      sessionId,
      appVersion,
      os,
      deviceClass,
      name,
      surface,
      durationMs,
      ok,
      traceId,
    };
    ring.push(row);
    if (ring.length > MAX) ring.splice(0, ring.length - MAX);
    pushDuration(name, durationMs);
    accepted += 1;
  }

  return { accepted, rejected };
}

export type MetricNameStats = {
  name: string;
  count: number;
  p50: number;
  p95: number;
  p99: number;
};

/** Snapshot for ops / Grafana Infinity JSON. */
export function metricsSummary(): {
  samples: number;
  byName: Record<string, { count: number; p50: number; p95: number; p99: number }>;
  /** Flat rows — easiest for Grafana Infinity table panels. */
  rows: MetricNameStats[];
} {
  const out: Record<string, { count: number; p50: number; p95: number; p99: number }> = {};
  const rows: MetricNameStats[] = [];
  for (const [name, arr] of byName) {
    const sorted = [...arr].sort((a, b) => a - b);
    const stats = {
      count: sorted.length,
      p50: percentile(sorted, 50),
      p95: percentile(sorted, 95),
      p99: percentile(sorted, 99),
    };
    out[name] = stats;
    rows.push({ name, ...stats });
  }
  rows.sort((a, b) => a.name.localeCompare(b.name));
  return { samples: ring.length, byName: out, rows };
}

/** Prometheus text exposition for Grafana Cloud / scrapers. */
export function metricsPrometheusText(): string {
  const lines: string[] = [
    '# HELP matterya_client_milestone_duration_ms Client milestone latency (rolling window)',
    '# TYPE matterya_client_milestone_duration_ms summary',
    '# HELP matterya_client_milestone_samples Rolling sample count in API memory',
    '# TYPE matterya_client_milestone_samples gauge',
  ];
  const summary = metricsSummary();
  lines.push(`matterya_client_milestone_samples ${summary.samples}`);
  for (const row of summary.rows) {
    const n = sanitizePromLabel(row.name);
    lines.push(
      `matterya_client_milestone_duration_ms{name="${n}",quantile="0.5"} ${row.p50}`
    );
    lines.push(
      `matterya_client_milestone_duration_ms{name="${n}",quantile="0.95"} ${row.p95}`
    );
    lines.push(
      `matterya_client_milestone_duration_ms{name="${n}",quantile="0.99"} ${row.p99}`
    );
    lines.push(
      `matterya_client_milestone_duration_ms_count{name="${n}"} ${row.count}`
    );
  }
  return lines.join('\n') + '\n';
}

function sanitizePromLabel(s: string): string {
  return s.replace(/[^a-zA-Z0-9_:.-]/g, '_').slice(0, 80);
}
