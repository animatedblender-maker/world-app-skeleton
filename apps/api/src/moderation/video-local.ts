/**
 * Local-only video moderation — frames never leave Matterya.
 *
 * ffmpeg samples a few frames → @xenova/transformers NSFW image classifier
 * (default Falconsai/nsfw_image_detection). No OpenAI / third-party upload.
 */
import { spawn } from 'node:child_process';
import { createWriteStream } from 'node:fs';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pipeline } from 'node:stream/promises';
import { GetObjectCommand } from '@aws-sdk/client-s3';
import { createR2Client, getBucket, r2Configured } from '../content-pipeline/r2.js';
import { extractR2Key } from '../media/r2-playback.js';
import { ffmpegAvailable, resolveFfmpegPath } from '../media/frame0.js';

export type VideoNsfwFrameScore = {
  atSeconds: number;
  label: string;
  score: number;
};

export type VideoNsfwResult = {
  ok: boolean;
  provider: string;
  modelVersion: string;
  maxNsfw: number;
  frames: VideoNsfwFrameScore[];
  error?: string;
};

function envBool(key: string, fallback: boolean): boolean {
  const v = process.env[key];
  if (v == null || v === '') return fallback;
  return v === '1' || v.toLowerCase() === 'true' || v === 'yes';
}

export function isVideoModerationEnabled(): boolean {
  return envBool('MODERATION_VIDEO_ENABLED', true);
}

export function videoNsfwThreshold(): number {
  const n = Number(process.env.MODERATION_VIDEO_NSFW_THRESHOLD);
  return Number.isFinite(n) ? Math.min(1, Math.max(0, n)) : 0.85;
}

/** AdamCodd ships ONNX for transformers.js; Falconsai does not. */
const DEFAULT_MODEL = 'AdamCodd/vit-base-nsfw-detector';

function modelId(): string {
  return (process.env.MODERATION_VIDEO_MODEL || DEFAULT_MODEL).trim() || DEFAULT_MODEL;
}

/** File path or URL — transformers.js RawImage.read handles both in Node. */
type Classifier = (imagePath: string) => Promise<Array<{ label: string; score: number }>>;

let classifier: Classifier | null = null;
let classifierInit: Promise<Classifier | null> | null = null;
let classifierInitFailed = false;

async function getClassifier(): Promise<Classifier | null> {
  if (classifier) return classifier;
  // Allow one retry path after a failed init (e.g. wrong model id then fixed).
  if (classifierInitFailed && !classifierInit) return null;
  if (!classifierInit) {
    classifierInit = (async () => {
      try {
        const { pipeline, env } = await import('@xenova/transformers');
        const hfToken = process.env.HF_ACCESS_TOKEN || process.env.HUGGINGFACE_TOKEN || '';
        if (hfToken) {
          (env as any).HF_ACCESS_TOKEN = hfToken;
        }
        // Keep cache under /tmp on ephemeral hosts when unset.
        if (!process.env.TRANSFORMERS_CACHE && !process.env.HF_HOME) {
          (env as any).cacheDir = join(tmpdir(), 'matterya-transformers-cache');
        }
        const id = modelId();
        console.log(`[moderation/video] loading classifier ${id}`);
        const pipe = await pipeline('image-classification', id);
        const wrapped: Classifier = async (imagePath) => {
          const out = await pipe(imagePath);
          return Array.isArray(out) ? (out as Array<{ label: string; score: number }>) : [];
        };
        classifier = wrapped;
        classifierInitFailed = false;
        return wrapped;
      } catch (err: any) {
        console.warn('[moderation/video] classifier init failed', err?.message ?? err);
        classifierInitFailed = true;
        classifierInit = null;
        return null;
      }
    })();
  }
  return classifierInit;
}

function runCmd(bin: string, args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args, { stdio: ['ignore', 'ignore', 'pipe'] });
    let err = '';
    child.stderr?.on('data', (d) => {
      err += String(d);
      if (err.length > 4000) err = err.slice(-4000);
    });
    child.on('error', reject);
    child.on('close', (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${bin} exited ${code}: ${err.slice(-800)}`));
    });
  });
}

async function downloadHttpToFile(url: string, destPath: string): Promise<void> {
  const res = await fetch(url, { redirect: 'follow' });
  if (!res.ok || !res.body) {
    throw new Error(`download failed ${res.status}`);
  }
  const { Readable } = await import('node:stream');
  const nodeStream = Readable.fromWeb(res.body as import('node:stream/web').ReadableStream);
  await pipeline(nodeStream, createWriteStream(destPath));
}

async function downloadVideoToFile(mediaUrl: string, destPath: string): Promise<void> {
  const raw = String(mediaUrl || '').trim();
  if (!raw) throw new Error('empty media_url');

  if (raw.startsWith('http://') || raw.startsWith('https://')) {
    await downloadHttpToFile(raw, destPath);
    return;
  }

  if (!r2Configured()) throw new Error('R2 not configured for r2: media');
  const key =
    extractR2Key(raw) ||
    (() => {
      const m = raw.match(/^r2(?:-share|-hubshare)?:(?:[^/]+)\/(.+)$/);
      return m?.[1] ?? null;
    })();
  if (!key) throw new Error(`cannot resolve R2 key from ${raw.slice(0, 80)}`);
  const bucket = getBucket();
  const client = createR2Client();
  const out = await client.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  if (!out.Body) throw new Error(`empty R2 body for ${key}`);
  await pipeline(out.Body as NodeJS.ReadableStream, createWriteStream(destPath));
}

/** Sample offsets as fractions of duration (clamped). */
const SAMPLE_FRACS = [0, 0.35, 0.7] as const;

async function probeDurationSeconds(ffmpegBin: string, srcPath: string): Promise<number> {
  // ffprobe may be missing next to ffmpeg-static — use ffmpeg -i parse.
  return new Promise((resolve) => {
    const child = spawn(ffmpegBin, ['-i', srcPath], { stdio: ['ignore', 'ignore', 'pipe'] });
    let err = '';
    child.stderr?.on('data', (d) => {
      err += String(d);
    });
    child.on('close', () => {
      const m = err.match(/Duration:\s*(\d+):(\d+):(\d+(?:\.\d+)?)/);
      if (!m) {
        resolve(0);
        return;
      }
      const h = Number(m[1]);
      const min = Number(m[2]);
      const sec = Number(m[3]);
      const total = h * 3600 + min * 60 + sec;
      resolve(Number.isFinite(total) ? total : 0);
    });
    child.on('error', () => resolve(0));
  });
}

function nsfwScoreFromLabels(labels: Array<{ label: string; score: number }>): {
  label: string;
  score: number;
} {
  let best = { label: 'unknown', score: 0 };
  for (const row of labels) {
    const lab = String(row.label || '').toLowerCase();
    const score = Number(row.score) || 0;
    // AdamCodd: nsfw | sfw. Others: porn / hentai / sexy / nude / …
    const isNsfw =
      lab === 'nsfw' ||
      lab.includes('porn') ||
      lab.includes('hentai') ||
      lab.includes('sexy') ||
      lab.includes('sensual') ||
      lab.includes('nude') ||
      lab.includes('enticing');
    if (isNsfw && score >= best.score) {
      best = { label: lab, score };
    }
  }
  // If model only returned "sfw"/"normal", nsfw score is 1 - that.
  if (best.score === 0 && labels.length) {
    const normal = labels.find((l) => /normal|sfw|safe|neutral/i.test(l.label));
    if (normal) {
      return { label: 'nsfw', score: Math.max(0, 1 - (Number(normal.score) || 0)) };
    }
  }
  return best;
}

/**
 * Download video → extract a few JPEG frames → local NSFW classify.
 * Frames stay on disk under mkdtemp and are deleted in finally.
 */
export async function scoreVideoNsfwLocal(mediaUrl: string): Promise<VideoNsfwResult> {
  const provider = 'local-xenova';
  const modelVersion = modelId();

  if (!isVideoModerationEnabled()) {
    return {
      ok: false,
      provider,
      modelVersion,
      maxNsfw: 0,
      frames: [],
      error: 'disabled',
    };
  }

  const ffmpegBin = resolveFfmpegPath();
  if (!(await ffmpegAvailable())) {
    return {
      ok: false,
      provider,
      modelVersion,
      maxNsfw: 0,
      frames: [],
      error: 'ffmpeg_unavailable',
    };
  }

  const clf = await getClassifier();
  if (!clf) {
    return {
      ok: false,
      provider,
      modelVersion,
      maxNsfw: 0,
      frames: [],
      error: 'classifier_unavailable',
    };
  }

  const workDir = await mkdtemp(join(tmpdir(), 'matterya-vidmod-'));
  const srcPath = join(workDir, 'source.mp4');
  const frames: VideoNsfwFrameScore[] = [];

  try {
    await downloadVideoToFile(mediaUrl, srcPath);
    const duration = await probeDurationSeconds(ffmpegBin, srcPath);
    const times =
      duration > 1
        ? SAMPLE_FRACS.map((f) => Math.min(Math.max(duration * f, 0), Math.max(duration - 0.05, 0)))
        : [0];

    for (let i = 0; i < times.length; i++) {
      const at = times[i]!;
      const framePath = join(workDir, `frame_${i}.jpg`);
      await runCmd(ffmpegBin, [
        '-y',
        '-ss',
        at.toFixed(3),
        '-i',
        srcPath,
        '-frames:v',
        '1',
        '-vf',
        'scale=384:384:force_original_aspect_ratio=decrease',
        '-q:v',
        '5',
        framePath,
      ]);
      const bytes = await readFile(framePath);
      if (!bytes.length) continue;
      const labels = await clf(framePath);
      const hit = nsfwScoreFromLabels(labels);
      frames.push({ atSeconds: at, label: hit.label, score: hit.score });
    }

    const maxNsfw = frames.reduce((m, f) => Math.max(m, f.score), 0);
    return { ok: true, provider, modelVersion, maxNsfw, frames };
  } catch (err: any) {
    return {
      ok: false,
      provider,
      modelVersion,
      maxNsfw: 0,
      frames,
      error: err?.message ?? String(err),
    };
  } finally {
    await rm(workDir, { recursive: true, force: true }).catch(() => undefined);
  }
}

/** Classify a local image file path (JPEG/PNG/WebP). */
export async function scoreImagePathNsfwLocal(
  imagePath: string
): Promise<{ ok: boolean; score: number; label: string; error?: string }> {
  const clf = await getClassifier();
  if (!clf) return { ok: false, score: 0, label: 'unknown', error: 'classifier_unavailable' };
  try {
    const labels = await clf(imagePath);
    const hit = nsfwScoreFromLabels(labels);
    return { ok: true, score: hit.score, label: hit.label };
  } catch (err: any) {
    return { ok: false, score: 0, label: 'unknown', error: err?.message ?? String(err) };
  }
}

