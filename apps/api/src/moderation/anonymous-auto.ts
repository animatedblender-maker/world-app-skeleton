/**
 * Masquerade auto-moderation (local only).
 *
 * Text: local spam rules + adult keyword flag.
 * Video: ffmpeg frame sample + on-box NSFW classifier (see video-local.ts).
 * Frames / bytes never leave Matterya.
 *
 * Policy (Masquerade is already 18+):
 * - Spam / scam rules → state = held
 * - High NSFW video outside adult spaces (category confessions / secrets|confessions slugs)
 *   → state = held for human review
 * - High NSFW inside adult spaces → record only (expected)
 * - Classifier failure → record review note; do not mass-hold
 */
import { pool } from '../db.js';
import { runLocalSpamRules } from './local-rules.js';
import { textLooksNsfw } from './nsfw.js';
import {
  isVideoModerationEnabled,
  scoreVideoNsfwLocal,
  videoNsfwThreshold,
  type VideoNsfwResult,
} from './video-local.js';
import { resolveAnonymousMediaUrl } from '../anonymous/media.js';

const ADULT_SPACE_SLUGS = new Set(['secrets', 'confessions']);
const ADULT_SPACE_CATEGORIES = new Set(['confessions']);

function envBool(key: string, fallback: boolean): boolean {
  const v = process.env[key];
  if (v == null || v === '') return fallback;
  return v === '1' || v.toLowerCase() === 'true' || v === 'yes';
}

export function isAnonymousAutoModEnabled(): boolean {
  return envBool('MODERATION_ANON_ENABLED', true);
}

async function recordSystemAction(
  targetType: string,
  targetId: string,
  action: string,
  reason: string
): Promise<void> {
  await pool.query(
    `
    insert into anonymous.moderation_actions (actor_profile_id, target_type, target_id, action, reason)
    values (null, $1, $2::uuid, $3, $4)
    `,
    [targetType, targetId, action, reason.slice(0, 2000)]
  );
}

async function holdPost(postId: string, reason: string): Promise<void> {
  await pool.query(
    `
    update anonymous.posts
    set state = 'held', updated_at = now()
    where id = $1::uuid
      and state = 'active'
    `,
    [postId]
  );
  await recordSystemAction('post', postId, 'auto_hold', reason);
}

function spaceIsAdult(slug: string | null | undefined, category: string | null | undefined): boolean {
  const s = String(slug || '').toLowerCase();
  const c = String(category || '').toLowerCase();
  return ADULT_SPACE_SLUGS.has(s) || ADULT_SPACE_CATEGORIES.has(c);
}

export type AnonymousModInput = {
  postId: string;
  spaceId: string;
  spaceSlug?: string | null;
  spaceCategory?: string | null;
  title?: string | null;
  body?: string | null;
  mediaType?: string | null;
  mediaUrl?: string | null;
};

export type AnonymousModResult = {
  textDecision: 'safe' | 'held' | 'flagged';
  video?: VideoNsfwResult;
  held: boolean;
  reasons: string[];
};

/**
 * Run text + optional video auto-mod for one Masquerade post.
 * Safe to await or fire-and-forget after create.
 */
export async function moderateAnonymousPost(
  input: AnonymousModInput
): Promise<AnonymousModResult | null> {
  if (!isAnonymousAutoModEnabled()) return null;

  const postId = String(input.postId || '').trim();
  if (!postId) return null;

  const reasons: string[] = [];
  let held = false;
  let textDecision: AnonymousModResult['textDecision'] = 'safe';

  const text = [input.title, input.body].filter(Boolean).join('\n');
  const ruleHit = runLocalSpamRules(text);
  if (ruleHit) {
    textDecision = 'held';
    reasons.push(`text:${ruleHit.code}:${ruleHit.reason}`);
    await holdPost(postId, reasons[reasons.length - 1]!);
    held = true;
  } else if (textLooksNsfw(input.title, input.body)) {
    textDecision = 'flagged';
    reasons.push('text:adult_keywords');
    await recordSystemAction('post', postId, 'auto_flag', 'text:adult_keywords');
    // Adult keywords alone do not hold inside adult spaces.
    if (!spaceIsAdult(input.spaceSlug, input.spaceCategory)) {
      await holdPost(postId, 'text:adult_keywords_outside_adult_space');
      held = true;
      reasons.push('held:adult_keywords_outside_adult_space');
    }
  }

  let video: VideoNsfwResult | undefined;
  const mediaType = String(input.mediaType || '').toLowerCase();
  if (mediaType === 'video' && input.mediaUrl && isVideoModerationEnabled()) {
    const playable = (await resolveAnonymousMediaUrl(input.mediaUrl)) || input.mediaUrl;
    video = await scoreVideoNsfwLocal(playable);
    const thr = videoNsfwThreshold();
    if (video.ok) {
      const summary = `video:nsfw=${video.maxNsfw.toFixed(3)} thr=${thr} frames=${video.frames.length}`;
      reasons.push(summary);
      await recordSystemAction(
        'post',
        postId,
        video.maxNsfw >= thr ? 'auto_flag_nsfw_video' : 'auto_scan_video_ok',
        JSON.stringify({
          maxNsfw: video.maxNsfw,
          threshold: thr,
          provider: video.provider,
          model: video.modelVersion,
          frames: video.frames,
        })
      );
      if (video.maxNsfw >= thr && !spaceIsAdult(input.spaceSlug, input.spaceCategory) && !held) {
        await holdPost(
          postId,
          `video:nsfw_outside_adult_space score=${video.maxNsfw.toFixed(3)}`
        );
        held = true;
        reasons.push('held:nsfw_video_outside_adult_space');
      }
    } else {
      reasons.push(`video:scan_failed:${video.error || 'unknown'}`);
      await recordSystemAction(
        'post',
        postId,
        'auto_scan_video_failed',
        video.error || 'unknown'
      );
    }
  }

  return { textDecision, video, held, reasons };
}

/** Fire-and-forget — create path must not hang on model download / ffmpeg. */
export function scheduleAnonymousModeration(input: AnonymousModInput): void {
  if (!isAnonymousAutoModEnabled()) return;
  const timeoutMs = Math.min(
    Math.max(Number(process.env.MODERATION_ANON_SCHEDULE_TIMEOUT_MS) || 90_000, 5_000),
    180_000
  );
  void Promise.race([
    moderateAnonymousPost(input),
    new Promise<null>((resolve) => setTimeout(() => resolve(null), timeoutMs)),
  ]).catch((err) => {
    console.warn('[moderation/anon] schedule error', err?.message ?? err);
  });
}
