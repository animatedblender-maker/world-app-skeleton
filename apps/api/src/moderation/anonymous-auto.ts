/**
 * Masquerade auto-moderation (local only).
 *
 * Flow:
 * 1) Score text + video frames on-box (nothing leaves Matterya).
 * 2) On hit → FLAG on the platform (post stays visible) + open a report
 *    for /reports/masquerade (Remove / Flag / Skip).
 * 3) Spam / scam text still goes to held (not shown) — separate from NSFW flag.
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

function envBool(key: string, fallback: boolean): boolean {
  const v = process.env[key];
  if (v == null || v === '') return fallback;
  return v === '1' || v.toLowerCase() === 'true' || v === 'yes';
}

export function isAnonymousAutoModEnabled(): boolean {
  return envBool('MODERATION_ANON_ENABLED', true);
}

let flagSchemaEnsured = false;

/** Best-effort ensure flagged_at / nullable reporter exist (seed locks may delay). */
async function ensureFlagSchema(): Promise<void> {
  if (flagSchemaEnsured) return;
  try {
    await pool.query(`
      alter table anonymous.posts
        add column if not exists flagged_at timestamptz,
        add column if not exists flag_reason text
    `);
    await pool.query(`
      alter table anonymous.reports
        alter column reporter_profile_id drop not null
    `);
    flagSchemaEnsured = true;
  } catch (err: any) {
    console.warn('[moderation/anon] ensureFlagSchema', err?.message ?? err);
  }
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

/** Mark post flagged on-platform (still active / visible) + open review report. */
export async function flagPostForReview(opts: {
  postId: string;
  reason: string;
  detail?: string;
}): Promise<{ reportId: string | null }> {
  await ensureFlagSchema();
  const reason = opts.reason.slice(0, 500);
  const detail = (opts.detail || reason).slice(0, 2000);

  await pool.query(
    `
    update anonymous.posts
    set flagged_at = coalesce(flagged_at, now()),
        flag_reason = coalesce(flag_reason, $2),
        updated_at = now()
    where id = $1::uuid
      and state = 'active'
    `,
    [opts.postId, reason]
  );

  // One open auto-report per post — avoid queue spam on re-scan.
  const existing = await pool.query<{ id: string }>(
    `
    select id from anonymous.reports
    where target_type = 'post'
      and target_id = $1::uuid
      and state = 'open'
      and reason like 'auto:%'
    order by created_at desc
    limit 1
    `,
    [opts.postId]
  );
  if (existing.rows[0]?.id) {
    await recordSystemAction('post', opts.postId, 'auto_flag', detail);
    return { reportId: existing.rows[0].id };
  }

  const { rows } = await pool.query<{ id: string }>(
    `
    insert into anonymous.reports (reporter_profile_id, target_type, target_id, reason, state)
    values (null, 'post', $1::uuid, $2, 'open')
    returning id
    `,
    [opts.postId, `auto:${detail}`.slice(0, 1000)]
  );
  await recordSystemAction('post', opts.postId, 'auto_flag', detail);
  return { reportId: rows[0]?.id ?? null };
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
  flagged: boolean;
  reportId?: string | null;
  reasons: string[];
};

/**
 * Run text + optional video auto-mod for one Masquerade post.
 * NSFW → platform flag + open report (visible with badge). Spam → held.
 */
export async function moderateAnonymousPost(
  input: AnonymousModInput
): Promise<AnonymousModResult | null> {
  if (!isAnonymousAutoModEnabled()) return null;

  const postId = String(input.postId || '').trim();
  if (!postId) return null;

  const reasons: string[] = [];
  let held = false;
  let flagged = false;
  let reportId: string | null = null;
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
    const r = await flagPostForReview({
      postId,
      reason: 'text:adult_keywords',
      detail: 'text:adult_keywords',
    });
    flagged = true;
    reportId = r.reportId;
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
          space: input.spaceSlug ?? null,
        })
      );
      if (video.maxNsfw >= thr) {
        const r = await flagPostForReview({
          postId,
          reason: 'video:nsfw',
          detail: summary,
        });
        flagged = true;
        reportId = r.reportId ?? reportId;
        reasons.push('flagged:nsfw_video');
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

  return { textDecision, video, held, flagged, reportId, reasons };
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
