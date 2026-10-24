/**
 * Server-side video transcription via Groq Whisper.
 * Keeps the iOS app light — never embeds an ASR model on device.
 *
 * Env:
 *   GROQ_API_KEY   required for live transcription
 *   GROQ_WHISPER_MODEL  optional (default whisper-large-v3-turbo)
 */
import { spawn } from 'node:child_process';
import { createReadStream, promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pool } from '../db.js';
import { resolveFfmpegPath } from './frame0.js';
import { extractR2Key, resolvePlayUrlForKey } from './r2-playback.js';

const GROQ_URL = 'https://api.groq.com/openai/v1/audio/transcriptions';
const DEFAULT_MODEL = 'whisper-large-v3-turbo';

export type TranscriptStatus = 'pending' | 'processing' | 'ready' | 'failed' | 'skipped';

export type TranscriptRow = {
  post_id: string;
  status: TranscriptStatus;
  language: string | null;
  model: string | null;
  text: string | null;
  segments: unknown;
  error: string | null;
  source: string | null;
  duration_seconds: number | null;
  completed_at: string | null;
};

function groqKey(): string | null {
  const k = process.env.GROQ_API_KEY?.trim();
  return k || null;
}

function whisperModel(): string {
  return process.env.GROQ_WHISPER_MODEL?.trim() || DEFAULT_MODEL;
}

export function transcriptionConfigured(): boolean {
  return !!groqKey();
}

export async function ensureTranscriptSchema(): Promise<boolean> {
  try {
    await pool.query(`
      create table if not exists public.video_transcripts (
        post_id uuid primary key references public.posts (id) on delete cascade,
        status text not null default 'pending'
          check (status in ('pending', 'processing', 'ready', 'failed', 'skipped')),
        language text,
        model text,
        text text,
        segments jsonb,
        error text,
        source text,
        duration_seconds double precision,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now(),
        completed_at timestamptz
      )
    `);
    return true;
  } catch (err: any) {
    console.warn('[transcribe] ensure schema failed', err?.message ?? err);
    return false;
  }
}

/** Queue a post for transcription (idempotent). */
export async function enqueueTranscript(
  postId: string,
  source = 'auto'
): Promise<void> {
  if (!postId) return;
  await ensureTranscriptSchema();
  await pool.query(
    `
    insert into public.video_transcripts (post_id, status, source, updated_at)
    values ($1::uuid, 'pending', $2, now())
    on conflict (post_id) do update
      set updated_at = now(),
          source = coalesce(public.video_transcripts.source, excluded.source)
      where public.video_transcripts.status in ('failed', 'pending')
    `,
    [postId, source]
  );
}

export async function getTranscript(postId: string): Promise<TranscriptRow | null> {
  await ensureTranscriptSchema();
  const { rows } = await pool.query<TranscriptRow>(
    `
    select post_id::text, status, language, model, text, segments, error, source,
           duration_seconds, completed_at::text
    from public.video_transcripts
    where post_id = $1::uuid
    limit 1
    `,
    [postId]
  );
  return rows[0] ?? null;
}

async function loadPostMedia(postId: string): Promise<{
  mediaUrl: string | null;
  mediaPath: string | null;
  mediaType: string | null;
} | null> {
  const { rows } = await pool.query<{
    media_url: string | null;
    media_path: string | null;
    media_type: string | null;
  }>(
    `
    select media_url::text as media_url,
           media_path::text as media_path,
           media_type::text as media_type
    from public.posts
    where id = $1::uuid
    limit 1
    `,
    [postId]
  );
  const row = rows[0];
  if (!row) return null;
  return {
    mediaUrl: row.media_url,
    mediaPath: row.media_path,
    mediaType: row.media_type,
  };
}

async function resolveAudioSourceUrl(
  mediaUrl: string | null,
  mediaPath: string | null = null
): Promise<string | null> {
  const key = extractR2Key(mediaUrl, mediaPath);
  if (key) {
    const play = await resolvePlayUrlForKey(key);
    if (play) return play;
  }
  // media_url may be JSON {"urls":["https://…"]} — unwrap first playable https.
  if (mediaUrl) {
    const raw = mediaUrl.trim();
    if (raw.startsWith('{')) {
      try {
        const parsed = JSON.parse(raw) as { urls?: unknown; url?: unknown };
        const urls = Array.isArray(parsed.urls) ? parsed.urls : [];
        for (const u of urls) {
          if (typeof u === 'string' && u.startsWith('http')) return u;
        }
        if (typeof parsed.url === 'string' && parsed.url.startsWith('http')) {
          return parsed.url;
        }
      } catch {
        /* ignore */
      }
    }
    if (raw.startsWith('http')) return raw;
  }
  return null;
}

function runFfmpegExtract(inputUrl: string, outPath: string): Promise<void> {
  const ffmpeg = resolveFfmpegPath();
  return new Promise((resolve, reject) => {
    const args = [
      '-y',
      '-i',
      inputUrl,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-b:a',
      '48k',
      '-t',
      '1800', // cap 30 min per clip for cost/latency
      outPath,
    ];
    const child = spawn(ffmpeg, args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let err = '';
    child.stderr.on('data', (d) => {
      err += String(d);
      if (err.length > 4000) err = err.slice(-4000);
    });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`ffmpeg_extract_failed:${code}:${err.slice(-500)}`));
    });
  });
}

type GroqVerbose = {
  text?: string;
  language?: string;
  duration?: number;
  segments?: Array<{ id?: number; start?: number; end?: number; text?: string }>;
};

async function groqTranscribeFile(filePath: string): Promise<GroqVerbose> {
  const key = groqKey();
  if (!key) throw new Error('GROQ_API_KEY missing');

  const form = new FormData();
  const blob = await fs.readFile(filePath);
  form.append('file', new Blob([blob], { type: 'audio/mpeg' }), path.basename(filePath));
  form.append('model', whisperModel());
  form.append('response_format', 'verbose_json');
  form.append('temperature', '0');

  const res = await fetch(GROQ_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}` },
    body: form,
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`groq_${res.status}:${body.slice(0, 400)}`);
  }
  return (await res.json()) as GroqVerbose;
}

/** Process one pending/failed post. Returns final status. */
export async function transcribePost(postId: string): Promise<TranscriptStatus> {
  if (!transcriptionConfigured()) {
    await pool.query(
      `
      insert into public.video_transcripts (post_id, status, error, updated_at)
      values ($1::uuid, 'skipped', 'GROQ_API_KEY not configured', now())
      on conflict (post_id) do update
        set status = 'skipped', error = excluded.error, updated_at = now()
      `,
      [postId]
    );
    return 'skipped';
  }

  await ensureTranscriptSchema();
  await pool.query(
    `
    insert into public.video_transcripts (post_id, status, updated_at)
    values ($1::uuid, 'processing', now())
    on conflict (post_id) do update
      set status = 'processing', error = null, updated_at = now()
    `,
    [postId]
  );

  const tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'matterya-tx-'));
  const audioPath = path.join(tmpDir, 'audio.mp3');
  try {
    const post = await loadPostMedia(postId);
    if (!post) throw new Error('post_not_found');
    const mt = String(post.mediaType ?? '').toLowerCase();
    const blob = `${post.mediaUrl ?? ''}\n${post.mediaPath ?? ''}`;
    if (mt && !['video', 'reel', 'spark'].includes(mt) && !blob.toLowerCase().includes('.mp4')) {
      await pool.query(
        `
        update public.video_transcripts
        set status = 'skipped', error = 'not_video', updated_at = now(), completed_at = now()
        where post_id = $1::uuid
        `,
        [postId]
      );
      return 'skipped';
    }

    const playUrl = await resolveAudioSourceUrl(post.mediaUrl, post.mediaPath);
    if (!playUrl) throw new Error('no_playable_url');

    await runFfmpegExtract(playUrl, audioPath);
    const stat = await fs.stat(audioPath);
    if (stat.size < 256) throw new Error('audio_too_small');
    // Groq free tier ~25MB
    if (stat.size > 24 * 1024 * 1024) throw new Error('audio_too_large');

    const result = await groqTranscribeFile(audioPath);
    const text = String(result.text ?? '').trim();
    if (!text) throw new Error('empty_transcript');

    await pool.query(
      `
      update public.video_transcripts
      set status = 'ready',
          language = $2,
          model = $3,
          text = $4,
          segments = $5::jsonb,
          duration_seconds = $6,
          error = null,
          updated_at = now(),
          completed_at = now()
      where post_id = $1::uuid
      `,
      [
        postId,
        result.language ?? null,
        whisperModel(),
        text,
        JSON.stringify(result.segments ?? []),
        result.duration ?? null,
      ]
    );
    return 'ready';
  } catch (err: any) {
    const msg = String(err?.message ?? err).slice(0, 500);
    await pool.query(
      `
      update public.video_transcripts
      set status = 'failed', error = $2, updated_at = now()
      where post_id = $1::uuid
      `,
      [postId, msg]
    );
    return 'failed';
  } finally {
    await fs.rm(tmpDir, { recursive: true, force: true }).catch(() => undefined);
  }
}

/** Drain pending queue (and optionally backfill videos with no row). */
export async function processTranscriptQueue(opts: {
  limit?: number;
  backfillMissing?: boolean;
} = {}): Promise<{ processed: number; ready: number; failed: number; skipped: number }> {
  await ensureTranscriptSchema();
  const limit = Math.min(Math.max(opts.limit ?? 20, 1), 100);
  let ready = 0;
  let failed = 0;
  let skipped = 0;
  let processed = 0;

  if (opts.backfillMissing) {
    await pool.query(
      `
      insert into public.video_transcripts (post_id, status, source, updated_at)
      select p.id, 'pending', 'backfill', now()
      from public.posts p
      left join public.video_transcripts t on t.post_id = p.id
      where t.post_id is null
        and coalesce(p.moderation_status, '') not in ('removed', 'deleted', 'blocked')
        and (
          lower(coalesce(p.media_type, '')) in ('video', 'reel', 'spark')
          or coalesce(p.media_url::text, '') ilike '%.mp4%'
          or coalesce(p.media_path::text, '') ilike '%.mp4%'
        )
      order by p.created_at desc nulls last
      limit $1
      on conflict do nothing
      `,
      [limit * 3]
    );
  }

  const { rows } = await pool.query<{ post_id: string }>(
    `
    select post_id::text as post_id
    from public.video_transcripts
    where status in ('pending', 'failed')
    order by
      case when status = 'pending' then 0 else 1 end,
      updated_at asc
    limit $1
    `,
    [limit]
  );

  for (const row of rows) {
    const status = await transcribePost(row.post_id);
    processed += 1;
    if (status === 'ready') ready += 1;
    else if (status === 'failed') failed += 1;
    else if (status === 'skipped') skipped += 1;
  }

  return { processed, ready, failed, skipped };
}
