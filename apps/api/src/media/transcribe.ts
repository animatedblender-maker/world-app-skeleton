/**
 * Server-side video transcription via Groq Whisper.
 * Keeps the iOS app light — never embeds an ASR model on device.
 *
 * Env:
 *   GROQ_API_KEY   required for live transcription
 *   GROQ_WHISPER_MODEL  optional (default whisper-large-v3-turbo)
 */
import { spawn } from 'node:child_process';
import { createWriteStream, promises as fs } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { GetObjectCommand, HeadObjectCommand } from '@aws-sdk/client-s3';
import { createR2Client, getBucket, r2Configured } from '../content-pipeline/r2.js';
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

/** Queue a post for transcription (idempotent). `force` resets a ready row (e.g. short 60s CC). */
export async function enqueueTranscript(
  postId: string,
  source = 'auto',
  opts: { force?: boolean } = {}
): Promise<void> {
  if (!postId) return;
  await ensureTranscriptSchema();
  if (opts.force) {
    await pool.query(
      `
      insert into public.video_transcripts (post_id, status, source, error, updated_at)
      values ($1::uuid, 'pending', $2, null, now())
      on conflict (post_id) do update
        set status = 'pending',
            error = null,
            text = null,
            segments = null,
            duration_seconds = null,
            completed_at = null,
            updated_at = now(),
            source = excluded.source
      `,
      [postId, source]
    );
    return;
  }
  // User CC / API enqueue may revive skipped backfill rows; never overwrite ready.
  const revive =
    source === 'api_enqueue' || source === 'cc'
      ? `('failed', 'pending', 'skipped', 'processing')`
      : `('failed', 'pending')`;
  await pool.query(
    `
    insert into public.video_transcripts (post_id, status, source, updated_at)
    values ($1::uuid, 'pending', $2, now())
    on conflict (post_id) do update
      set status = 'pending',
          error = null,
          updated_at = now(),
          source = excluded.source
      where public.video_transcripts.status in ${revive}
        and public.video_transcripts.status is distinct from 'ready'
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

/** Download R2 object to disk (same pattern as Frame0) — avoids ffmpeg HTTP kills on Render. */
async function downloadR2ObjectToFile(
  key: string,
  destPath: string,
  opts: { rangeBytes?: string } = {}
): Promise<void> {
  if (!r2Configured()) throw new Error('r2_not_configured');
  const client = createR2Client();
  const bucket = getBucket();
  const clean = key.replace(/^\/+/, '');
  const out = await client.send(
    new GetObjectCommand({
      Bucket: bucket,
      Key: clean,
      ...(opts.rangeBytes ? { Range: opts.rangeBytes } : {}),
    })
  );
  if (!out.Body) throw new Error(`empty_r2_body:${clean}`);
  await pipeline(out.Body as NodeJS.ReadableStream, createWriteStream(destPath));
}

type AudioExtractMode = 'cc' | 'batch';

function runFfmpegExtract(
  inputPathOrUrl: string,
  outPath: string,
  opts: { timeoutMs?: number; maxSeconds?: number } = {}
): Promise<void> {
  const ffmpeg = resolveFfmpegPath();
  const timeoutMs = opts.timeoutMs ?? 180_000;
  const maxSeconds = opts.maxSeconds ?? 600;
  return new Promise((resolve, reject) => {
    // Stream audio only — never buffer the whole LongForm file on disk for CC.
    const args = [
      '-hide_banner',
      '-loglevel',
      'error',
      '-nostdin',
      '-y',
      '-i',
      inputPathOrUrl,
      '-vn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-b:a',
      '32k',
      '-t',
      String(maxSeconds),
      outPath,
    ];
    const child = spawn(ffmpeg, args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let err = '';
    let settled = false;
    const timer = setTimeout(() => {
      if (settled) return;
      settled = true;
      try {
        child.kill('SIGKILL');
      } catch {
        /* ignore */
      }
      reject(new Error(`ffmpeg_extract_timeout:${timeoutMs}ms`));
    }, timeoutMs);
    child.stderr.on('data', (d) => {
      err += String(d);
      if (err.length > 6000) err = err.slice(-6000);
    });
    child.on('error', (e) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      reject(e);
    });
    child.on('close', (code, signal) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (code === 0) {
        resolve();
        return;
      }
      const tail = err.trim().slice(-800) || '(no ffmpeg stderr)';
      reject(
        new Error(
          `ffmpeg_extract_failed:code=${code}:signal=${signal ?? ''}:${tail}`
        )
      );
    });
  });
}

/**
 * Materialize audio for Whisper.
 *
 * Render's ffmpeg-static **SIGSEGVs on HTTPS inputs** — never feed signed URLs to it.
 * Always R2 SDK → local file → ffmpeg (same pattern Frame0 uses successfully).
 * CC keeps downloads bounded so captions stay interactive.
 */
async function prepareAudioForWhisper(opts: {
  mediaUrl: string | null;
  mediaPath: string | null;
  workDir: string;
  mode?: AudioExtractMode;
}): Promise<string> {
  const mode: AudioExtractMode = opts.mode ?? 'batch';
  const audioPath = path.join(opts.workDir, 'audio.mp3');
  // CC must cover the film (up to 10 min) — the old 60s cut left captions blank mid-video.
  // 32kbps mono ≈ 2.4MB / 10 min, well under Groq’s ~25MB upload cap.
  const maxSeconds = 600;
  const key = extractR2Key(opts.mediaUrl, opts.mediaPath);

  if (key && r2Configured()) {
    const client = createR2Client();
    const clean = key.replace(/^\/+/, '');
    let size = 0;
    try {
      const head = await client.send(
        new HeadObjectCommand({ Bucket: getBucket(), Key: clean })
      );
      size = Number(head.ContentLength ?? 0);
    } catch {
      size = 0;
    }

    const srcPath = path.join(opts.workDir, 'source.mp4');
    // Prefer enough of the object to extract ≤10 min of audio (faststart moov + body).
    const fullMax = 80 * 1024 * 1024;
    const rangeBytes = 48 * 1024 * 1024;

    if (size > 0 && size <= fullMax) {
      await downloadR2ObjectToFile(clean, srcPath);
    } else {
      await downloadR2ObjectToFile(clean, srcPath, {
        rangeBytes: `bytes=0-${rangeBytes - 1}`,
      });
    }
    const st = await fs.stat(srcPath);
    if (st.size < 1024) throw new Error('r2_download_too_small');
    try {
      await runFfmpegExtract(srcPath, audioPath, {
        timeoutMs: mode === 'cc' ? 90_000 : 180_000,
        maxSeconds,
      });
      return audioPath;
    } catch (err: any) {
      // Partial range sometimes lacks moov — one bounded full retry under 90MB.
      if (size > 0 && size <= 90 * 1024 * 1024 && st.size < size) {
        await downloadR2ObjectToFile(clean, srcPath);
        await runFfmpegExtract(srcPath, audioPath, {
          timeoutMs: 180_000,
          maxSeconds,
        });
        return audioPath;
      }
      throw new Error(
        `${mode === 'cc' ? 'cc' : 'batch'}_local_ffmpeg_failed:${err?.message ?? err}`
      );
    }
  }

  // Non-R2 media only: last resort HTTP (may SIGSEGV on Render — prefer R2).
  const playUrl = await resolveAudioSourceUrl(opts.mediaUrl, opts.mediaPath);
  if (!playUrl) throw new Error('no_playable_url');
  await runFfmpegExtract(playUrl, audioPath, {
    timeoutMs: mode === 'cc' ? 90_000 : 120_000,
    maxSeconds,
  });
  return audioPath;
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

/** In-process lock so CC + backfill don't double-run the same post. */
const activeJobs = new Set<string>();

/** Process one pending/failed post. Returns final status. */
export async function transcribePost(
  postId: string,
  opts: { mode?: AudioExtractMode; force?: boolean } = {}
): Promise<TranscriptStatus> {
  const mode: AudioExtractMode = opts.mode ?? 'batch';
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

  if (activeJobs.has(postId)) {
    return 'processing';
  }
  activeJobs.add(postId);
  let tmpDir: string | null = null;
  try {
    await ensureTranscriptSchema();
    // Already ready — don't burn Whisper again (unless force, e.g. replace short CC).
    const existing = await getTranscript(postId);
    if (
      !opts.force &&
      existing?.status === 'ready' &&
      (existing.text || existing.segments)
    ) {
      return 'ready';
    }

    await pool.query(
      `
      insert into public.video_transcripts (post_id, status, updated_at)
      values ($1::uuid, 'processing', now())
      on conflict (post_id) do update
        set status = 'processing', error = null, updated_at = now()
      `,
      [postId]
    );

    tmpDir = await fs.mkdtemp(path.join(os.tmpdir(), 'matterya-tx-'));
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

    const audioPath = await prepareAudioForWhisper({
      mediaUrl: post.mediaUrl,
      mediaPath: post.mediaPath,
      workDir: tmpDir,
      mode,
    });
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
    // Rate limits stay pending so the loop retries after backoff.
    const rateLimited = /groq_429|rate limit/i.test(msg);
    const status = rateLimited ? 'pending' : 'failed';
    await pool.query(
      `
      update public.video_transcripts
      set status = $3, error = $2, updated_at = now()
      where post_id = $1::uuid
      `,
      [postId, msg, status]
    );
    return rateLimited ? 'pending' : 'failed';
  } finally {
    activeJobs.delete(postId);
    if (tmpDir) {
      await fs.rm(tmpDir, { recursive: true, force: true }).catch(() => undefined);
    }
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
