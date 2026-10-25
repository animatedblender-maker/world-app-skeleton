/**
 * MIND-019 — User interest controls + explainability hooks.
 *
 * Explicit overrides beat inferred personality. Stored in
 * public.mind_user_interest_controls (ensured at runtime).
 */
import { pool } from '../db.js';
import { loadInterestBubbles } from './knn.service.js';

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function isUuid(s: string): boolean {
  return UUID_RE.test(s);
}

export type InterestControls = {
  mutedHubs: string[];
  mutedCreators: string[];
  boostedTopics: string[];
  chronoPreferred: boolean;
  updatedAt: string | null;
};

export type InterestSnapshot = {
  controls: InterestControls;
  inferred: {
    hubs: { key: string; score: number }[];
    countries: { key: string; score: number }[];
    media: { key: string; score: number }[];
    creators: { key: string; score: number }[];
    eventsCounted: number;
    coldStart: boolean;
  };
  explain: {
    note: string;
    sourceLabels: Record<string, string>;
  };
};

const SOURCE_LABELS: Record<string, string> = {
  following: 'Someone you follow',
  affinity: 'Creators you engage with',
  bubble: 'Matches your interests',
  outside_bubble: 'Outside your usual topics (exploration)',
  item_stats: 'Popular with others',
  fresh: 'Recently posted',
  knn: 'People like you engaged with this',
  knn_creator: 'Similar creators',
  media_topic: 'Topics from the video',
  ann: 'Semantically related to your interests',
  cold_start: 'Getting to know you',
  cold_prior_country: 'From your country',
  cold_prior_hub: 'Related hub',
  cold_prior_fresh: 'Fresh for new viewers',
  cold_prior_quality: 'Well-received content',
  cold_prior_ann: 'Related content while learning',
  opportunity: 'Rising creator',
  session: 'Based on this session',
  trained: 'Learned ranking model',
  surface_fit: 'Fits this surface',
  explore: 'Exploration',
  muted_skip: 'Hidden by your controls',
};

let schemaReady = false;

export async function ensureInterestControlsSchema(): Promise<boolean> {
  if (schemaReady) return true;
  try {
    await pool.query(`
      create table if not exists public.mind_user_interest_controls (
        entity_id uuid primary key,
        muted_hubs text[] not null default '{}',
        muted_creators uuid[] not null default '{}',
        boosted_topics text[] not null default '{}',
        chrono_preferred boolean not null default false,
        updated_at timestamptz not null default now()
      )
    `);
    schemaReady = true;
    return true;
  } catch (err: any) {
    console.warn('[mind-interest-controls] schema', err?.message ?? err);
    return false;
  }
}

function emptyControls(): InterestControls {
  return {
    mutedHubs: [],
    mutedCreators: [],
    boostedTopics: [],
    chronoPreferred: false,
    updatedAt: null,
  };
}

export async function loadInterestControls(
  entityId: string
): Promise<InterestControls> {
  if (!isUuid(entityId)) return emptyControls();
  await ensureInterestControlsSchema();
  try {
    const { rows } = await pool.query<{
      muted_hubs: string[] | null;
      muted_creators: string[] | null;
      boosted_topics: string[] | null;
      chrono_preferred: boolean;
      updated_at: Date;
    }>(
      `
      select muted_hubs, muted_creators::text[], boosted_topics,
             chrono_preferred, updated_at
      from public.mind_user_interest_controls
      where entity_id = $1::uuid
      `,
      [entityId]
    );
    const r = rows[0];
    if (!r) return emptyControls();
    return {
      mutedHubs: (r.muted_hubs ?? []).map((s) => s.toLowerCase()).filter(Boolean),
      mutedCreators: (r.muted_creators ?? []).filter(Boolean),
      boostedTopics: (r.boosted_topics ?? [])
        .map((s) => s.toLowerCase())
        .filter(Boolean),
      chronoPreferred: !!r.chrono_preferred,
      updatedAt: r.updated_at ? new Date(r.updated_at).toISOString() : null,
    };
  } catch {
    return emptyControls();
  }
}

function topMap(
  m: Map<string, number> | null | undefined,
  limit = 12
): { key: string; score: number }[] {
  if (!m) return [];
  return [...m.entries()]
    .filter(([k, v]) => k && Number.isFinite(v) && v !== 0)
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([key, score]) => ({ key, score: Math.round(score * 1000) / 1000 }));
}

export async function getInterestSnapshot(
  entityId: string
): Promise<InterestSnapshot> {
  const [controls, bubbles] = await Promise.all([
    loadInterestControls(entityId),
    loadInterestBubbles(entityId),
  ]);
  let creators: { key: string; score: number }[] = [];
  try {
    const { rows } = await pool.query<{ creator_id: string; score: number }>(
      `
      select creator_id::text, score
      from public.recsys_user_creator_affinity
      where entity_id = $1::uuid
      order by score desc
      limit 12
      `,
      [entityId]
    );
    creators = rows.map((r) => ({
      key: r.creator_id,
      score: Math.round(Number(r.score) * 1000) / 1000,
    }));
  } catch {
    /* ignore */
  }
  const eventsCounted = bubbles?.eventsCounted ?? 0;
  return {
    controls,
    inferred: {
      hubs: topMap(bubbles?.hubs ?? null),
      countries: topMap(bubbles?.countries ?? null),
      media: topMap(bubbles?.media ?? null),
      creators,
      eventsCounted,
      coldStart: eventsCounted < 25,
    },
    explain: {
      note: 'Coarse reasons only — never raw behavioral traces.',
      sourceLabels: SOURCE_LABELS,
    },
  };
}

export type InterestPatch = {
  mutedHubs?: string[];
  mutedCreators?: string[];
  boostedTopics?: string[];
  chronoPreferred?: boolean;
  /** Merge (default) vs replace listed arrays. */
  mode?: 'merge' | 'replace';
};

function normList(xs: unknown, lower = true): string[] {
  if (!Array.isArray(xs)) return [];
  const out: string[] = [];
  const seen = new Set<string>();
  for (const x of xs) {
    let s = String(x ?? '').trim();
    if (!s || s.length > 64) continue;
    if (lower) s = s.toLowerCase();
    if (seen.has(s)) continue;
    seen.add(s);
    out.push(s);
    if (out.length >= 64) break;
  }
  return out;
}

function mergeOrReplace(
  current: string[],
  next: string[] | undefined,
  mode: 'merge' | 'replace'
): string[] {
  if (next == null) return current;
  if (mode === 'replace') return next;
  const set = new Set(current);
  for (const x of next) set.add(x);
  return [...set].slice(0, 64);
}

export async function patchInterestControls(
  entityId: string,
  patch: InterestPatch
): Promise<InterestControls> {
  if (!isUuid(entityId)) throw new Error('invalid_entity');
  await ensureInterestControlsSchema();
  const mode = patch.mode === 'replace' ? 'replace' : 'merge';
  const cur = await loadInterestControls(entityId);
  const mutedHubs = mergeOrReplace(
    cur.mutedHubs,
    patch.mutedHubs != null ? normList(patch.mutedHubs, true) : undefined,
    mode
  );
  const mutedCreators = mergeOrReplace(
    cur.mutedCreators,
    patch.mutedCreators != null
      ? normList(patch.mutedCreators, false).filter(isUuid)
      : undefined,
    mode
  );
  const boostedTopics = mergeOrReplace(
    cur.boostedTopics,
    patch.boostedTopics != null ? normList(patch.boostedTopics, true) : undefined,
    mode
  );
  const chronoPreferred =
    patch.chronoPreferred != null ? !!patch.chronoPreferred : cur.chronoPreferred;

  await pool.query(
    `
    insert into public.mind_user_interest_controls as t (
      entity_id, muted_hubs, muted_creators, boosted_topics, chrono_preferred, updated_at
    ) values (
      $1::uuid, $2::text[], $3::uuid[], $4::text[], $5, now()
    )
    on conflict (entity_id) do update set
      muted_hubs = excluded.muted_hubs,
      muted_creators = excluded.muted_creators,
      boosted_topics = excluded.boosted_topics,
      chrono_preferred = excluded.chrono_preferred,
      updated_at = now()
    `,
    [entityId, mutedHubs, mutedCreators, boostedTopics, chronoPreferred]
  );
  return loadInterestControls(entityId);
}

/** Clear controls + inferred personality / affinity (hard reset personalization). */
export async function resetInterestControls(entityId: string): Promise<void> {
  if (!isUuid(entityId)) return;
  await ensureInterestControlsSchema();
  try {
    await pool.query(
      `delete from public.mind_user_interest_controls where entity_id = $1::uuid`,
      [entityId]
    );
  } catch {
    /* ignore */
  }
  try {
    await pool.query(
      `delete from public.recsys_user_creator_affinity where entity_id = $1::uuid`,
      [entityId]
    );
  } catch {
    /* ignore */
  }
  try {
    await pool.query(
      `
      update public.entity_personality
      set hubs_affinity = '{}'::jsonb,
          countries_affinity = '{}'::jsonb,
          creators_affinity = '{}'::jsonb,
          media_affinity = '{}'::jsonb,
          feature_vector = null,
          events_counted = 0,
          updated_at = now()
      where entity_id = $1::uuid
      `,
      [entityId]
    );
  } catch {
    /* ignore */
  }
}

export function explainSources(sources: string[]): { code: string; label: string }[] {
  return sources.map((code) => ({
    code,
    label: SOURCE_LABELS[code] ?? code,
  }));
}

/** Look up coarse why-this for a logged decision. */
export async function explainDecision(opts: {
  requestId: string;
  entityId: string;
}): Promise<{
  ok: boolean;
  requestId: string;
  surface?: string;
  items?: { id: string; reasons: { code: string; label: string }[] }[];
  error?: string;
}> {
  if (!opts.requestId || !isUuid(opts.entityId)) {
    return { ok: false, requestId: opts.requestId, error: 'invalid' };
  }
  try {
    const { rows } = await pool.query<{
      surface: string;
      sources: unknown;
      entity_id: string;
    }>(
      `
      select surface, sources, entity_id::text
      from public.recommendation_decisions
      where request_id = $1
      limit 1
      `,
      [opts.requestId]
    );
    const row = rows[0];
    if (!row) return { ok: false, requestId: opts.requestId, error: 'not_found' };
    if (row.entity_id !== opts.entityId) {
      return { ok: false, requestId: opts.requestId, error: 'forbidden' };
    }
    let srcs: { id?: string; sources?: string[] }[] = [];
    if (Array.isArray(row.sources)) srcs = row.sources as typeof srcs;
    else if (typeof row.sources === 'string') {
      try {
        srcs = JSON.parse(row.sources);
      } catch {
        srcs = [];
      }
    }
    return {
      ok: true,
      requestId: opts.requestId,
      surface: row.surface,
      items: srcs.map((s) => ({
        id: String(s.id ?? ''),
        reasons: explainSources(s.sources ?? []),
      })),
    };
  } catch (err: any) {
    return { ok: false, requestId: opts.requestId, error: err?.message ?? 'failed' };
  }
}
