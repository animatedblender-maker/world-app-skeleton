/**
 * MIND §7 — Media understanding (Phase 2a thin slice).
 *
 * Reuses public.video_transcripts (Groq Whisper). Derives versioned
 * mind_content_features (language, topics, text fingerprint).
 * pgvector / mind_content_embeddings stay Phase 2b (MIND-012).
 *
 * Missing transcript ⇒ UNKNOWN — never “not interesting”.
 */
import { createHash } from 'node:crypto';
import { pool } from '../db.js';

export const MIND_MEDIA_PIPELINE_VERSION = 'media.v1';

export function mindMediaFeaturesEnabled(): boolean {
  const raw = process.env.MIND_MEDIA_FEATURES_ENABLED?.trim().toLowerCase();
  if (raw === '0' || raw === 'false' || raw === 'off' || raw === 'no') return false;
  return true;
}

/** Feature catalog shown on /mind Architecture. */
export const MIND_MEDIA_FEATURE_CATALOG = [
  {
    id: 'transcript_status',
    label: 'Transcript status',
    description: 'ready | pending | processing | failed | skipped | unknown',
  },
  {
    id: 'language',
    label: 'Language',
    description: 'Whisper language code or UNKNOWN',
  },
  {
    id: 'topics',
    label: 'Topics',
    description: 'Lexicon topics from transcript + title/body (hub-aligned)',
  },
  {
    id: 'text_fingerprint',
    label: 'Text fingerprint',
    description: 'Stable hash of normalized transcript (near-dupe hint)',
  },
] as const;

/** Cheap hub-aligned topic lexicon — Phase 2a starter, not trained ML. */
const TOPIC_LEXICON: { topic: string; patterns: RegExp[] }[] = [
  { topic: 'comedy', patterns: [/\b(funny|comedy|joke|humor|laugh|meme|skit)\b/i] },
  { topic: 'music', patterns: [/\b(music|song|singer|concert|rap|beat|lyrics|album)\b/i] },
  { topic: 'travel', patterns: [/\b(travel|flight|airport|hotel|vacation|tourist|passport)\b/i] },
  { topic: 'nature', patterns: [/\b(nature|forest|ocean|wildlife|mountain|hiking|park)\b/i] },
  { topic: 'food', patterns: [/\b(food|recipe|cook|restaurant|meal|kitchen|delicious)\b/i] },
  { topic: 'sports', patterns: [/\b(sport|football|soccer|basketball|game|athlete|match)\b/i] },
  { topic: 'tech', patterns: [/\b(tech|software|app|phone|ai|computer|gadget|coding)\b/i] },
  { topic: 'science', patterns: [/\b(science|space|physics|biology|research|nasa|experiment)\b/i] },
  { topic: 'news', patterns: [/\b(news|breaking|report|headline|politics|election)\b/i] },
  { topic: 'lifestyle', patterns: [/\b(lifestyle|fashion|beauty|fitness|wellness|routine)\b/i] },
  { topic: 'education', patterns: [/\b(learn|tutorial|explain|lesson|school|study|how to)\b/i] },
  { topic: 'gaming', patterns: [/\b(game|gaming|gamer|xbox|playstation|nintendo|stream)\b/i] },
];

export type TranscriptStatus =
  | 'ready'
  | 'pending'
  | 'processing'
  | 'failed'
  | 'skipped'
  | 'unknown';

export type MindContentFeatures = {
  postId: string;
  pipelineVersion: string;
  transcriptStatus: TranscriptStatus;
  language: string | null;
  topics: string[];
  textFingerprint: string | null;
  model: string | null;
  source: string | null;
  durationSeconds: number | null;
};

function normalizeText(s: string): string {
  return s
    .toLowerCase()
    .replace(/\s+/g, ' ')
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .trim();
}

export function extractTopics(...chunks: Array<string | null | undefined>): string[] {
  const blob = chunks.filter(Boolean).join('\n');
  if (!blob.trim()) return [];
  const hits = new Set<string>();
  for (const entry of TOPIC_LEXICON) {
    for (const re of entry.patterns) {
      if (re.test(blob)) {
        hits.add(entry.topic);
        break;
      }
    }
  }
  return [...hits].sort();
}

export function textFingerprint(text: string | null | undefined): string | null {
  const n = normalizeText(String(text ?? ''));
  if (n.length < 24) return null;
  return createHash('sha256').update(n).digest('hex').slice(0, 32);
}

let schemaReady = false;

export async function ensureMindContentFeaturesSchema(): Promise<boolean> {
  if (schemaReady) return true;
  try {
    await pool.query(`
      create table if not exists public.mind_content_features (
        post_id uuid primary key references public.posts (id) on delete cascade,
        pipeline_version text not null,
        transcript_status text not null,
        language text,
        topics text[] not null default '{}',
        text_fingerprint text,
        model text,
        source text,
        duration_seconds double precision,
        meta jsonb not null default '{}'::jsonb,
        computed_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      )
    `);
    await pool.query(`
      create index if not exists mind_content_features_topics_gin
        on public.mind_content_features using gin (topics)
    `);
    await pool.query(`
      create index if not exists mind_content_features_status_idx
        on public.mind_content_features (transcript_status)
    `);
    schemaReady = true;
    return true;
  } catch (err: any) {
    console.warn('[mind-media] ensure schema failed', err?.message ?? err);
    return false;
  }
}

function asStatus(raw: string | null | undefined): TranscriptStatus {
  const s = String(raw ?? '').toLowerCase();
  if (
    s === 'ready' ||
    s === 'pending' ||
    s === 'processing' ||
    s === 'failed' ||
    s === 'skipped'
  ) {
    return s;
  }
  return 'unknown';
}

/**
 * Derive + upsert features for one public post from video_transcripts + title/body.
 * Best-effort — never throws to callers that must stay resilient.
 */
export async function upsertFeaturesForPost(postId: string): Promise<MindContentFeatures | null> {
  if (!mindMediaFeaturesEnabled() || !postId) return null;
  const ok = await ensureMindContentFeaturesSchema();
  if (!ok) return null;

  try {
    const { rows } = await pool.query<{
      title: string | null;
      body: string | null;
      t_status: string | null;
      language: string | null;
      model: string | null;
      text: string | null;
      source: string | null;
      duration_seconds: number | null;
    }>(
      `
      select
        p.title,
        p.body,
        t.status as t_status,
        t.language,
        t.model,
        t.text,
        t.source,
        t.duration_seconds
      from public.posts p
      left join public.video_transcripts t on t.post_id = p.id
      where p.id = $1::uuid
      limit 1
      `,
      [postId]
    );
    const row = rows[0];
    if (!row) return null;

    const transcriptStatus = asStatus(row.t_status);
    const topics = extractTopics(row.text, row.title, row.body);

    const language =
      transcriptStatus === 'ready'
        ? row.language?.trim() || 'UNKNOWN'
        : row.language?.trim() || 'UNKNOWN';
    const fp = transcriptStatus === 'ready' ? textFingerprint(row.text) : null;

    await pool.query(
      `
      insert into public.mind_content_features as f (
        post_id, pipeline_version, transcript_status, language, topics,
        text_fingerprint, model, source, duration_seconds, meta, computed_at, updated_at
      ) values (
        $1::uuid, $2, $3, $4, $5::text[],
        $6, $7, $8, $9, $10::jsonb, now(), now()
      )
      on conflict (post_id) do update set
        pipeline_version = excluded.pipeline_version,
        transcript_status = excluded.transcript_status,
        language = excluded.language,
        topics = excluded.topics,
        text_fingerprint = excluded.text_fingerprint,
        model = excluded.model,
        source = excluded.source,
        duration_seconds = excluded.duration_seconds,
        meta = excluded.meta,
        updated_at = now()
      `,
      [
        postId,
        MIND_MEDIA_PIPELINE_VERSION,
        transcriptStatus,
        language,
        topics,
        fp,
        row.model,
        row.source,
        row.duration_seconds,
        JSON.stringify({
          topicCount: topics.length,
          transcriptChars: row.text?.length ?? 0,
        }),
      ]
    );

    return {
      postId,
      pipelineVersion: MIND_MEDIA_PIPELINE_VERSION,
      transcriptStatus,
      language,
      topics,
      textFingerprint: fp,
      model: row.model,
      source: row.source,
      durationSeconds: row.duration_seconds,
    };
  } catch (err: any) {
    console.warn('[mind-media] upsert failed', postId, err?.message ?? err);
    return null;
  }
}

/** Backfill features from ready transcripts (and optionally any missing rows). */
export async function backfillFeatures(limit = 100): Promise<{ scanned: number; upserted: number }> {
  if (!mindMediaFeaturesEnabled()) return { scanned: 0, upserted: 0 };
  const ok = await ensureMindContentFeaturesSchema();
  if (!ok) return { scanned: 0, upserted: 0 };

  const cap = Math.min(Math.max(limit, 1), 500);
  const { rows } = await pool.query<{ post_id: string }>(
    `
    select t.post_id::text
    from public.video_transcripts t
    left join public.mind_content_features f on f.post_id = t.post_id
    where t.status = 'ready'
      and (f.post_id is null or f.pipeline_version is distinct from $2)
    order by t.completed_at desc nulls last
    limit $1
    `,
    [cap, MIND_MEDIA_PIPELINE_VERSION]
  );

  let upserted = 0;
  for (const r of rows) {
    const out = await upsertFeaturesForPost(r.post_id);
    if (out) upserted += 1;
  }
  return { scanned: rows.length, upserted };
}

/** Batch-load features for rank (Public posts only). */
export async function loadMediaFeaturesForPosts(
  postIds: string[]
): Promise<Map<string, { topics: string[]; transcriptReady: boolean; language: string | null }>> {
  const map = new Map<
    string,
    { topics: string[]; transcriptReady: boolean; language: string | null }
  >();
  if (!mindMediaFeaturesEnabled() || postIds.length === 0) return map;
  const uuids = postIds.filter((id) =>
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)
  );
  if (uuids.length === 0) return map;

  try {
    await ensureMindContentFeaturesSchema();
    const { rows } = await pool.query<{
      post_id: string;
      topics: string[] | null;
      transcript_status: string;
      language: string | null;
    }>(
      `
      select post_id::text, topics, transcript_status, language
      from public.mind_content_features
      where post_id = any($1::uuid[])
      `,
      [uuids]
    );
    for (const r of rows) {
      map.set(r.post_id, {
        topics: Array.isArray(r.topics) ? r.topics : [],
        transcriptReady: r.transcript_status === 'ready',
        language: r.language,
      });
    }
  } catch (err: any) {
    console.warn('[mind-media] load features failed', err?.message ?? err);
  }
  return map;
}

export type MediaUnderstandingStatus = {
  pipelineVersion: string;
  enabled: boolean;
  groqConfigured: boolean;
  transcripts: { status: string; n: number }[];
  features: number;
  readyWithFeatures: number;
  catalog: typeof MIND_MEDIA_FEATURE_CATALOG;
};

export async function getMediaUnderstandingStatus(): Promise<MediaUnderstandingStatus> {
  const groqConfigured = !!process.env.GROQ_API_KEY?.trim();
  const base: MediaUnderstandingStatus = {
    pipelineVersion: MIND_MEDIA_PIPELINE_VERSION,
    enabled: mindMediaFeaturesEnabled(),
    groqConfigured,
    transcripts: [],
    features: 0,
    readyWithFeatures: 0,
    catalog: MIND_MEDIA_FEATURE_CATALOG,
  };
  try {
    await ensureMindContentFeaturesSchema();
    const [tRes, fRes, readyRes] = await Promise.all([
      pool.query<{ status: string; n: string }>(
        `
        select status, count(*)::text as n
        from public.video_transcripts
        group by status
        order by count(*) desc
        `
      ),
      pool.query<{ n: string }>(`select count(*)::text as n from public.mind_content_features`),
      pool.query<{ n: string }>(
        `
        select count(*)::text as n
        from public.mind_content_features
        where transcript_status = 'ready'
        `
      ),
    ]);
    base.transcripts = tRes.rows.map((r) => ({ status: r.status, n: Number(r.n) || 0 }));
    base.features = Number(fRes.rows[0]?.n) || 0;
    base.readyWithFeatures = Number(readyRes.rows[0]?.n) || 0;
  } catch (err: any) {
    console.warn('[mind-media] status failed', err?.message ?? err);
  }
  return base;
}
