/**
 * MIND-024 — Guardian depth signals for /mind (reuse existing report + mod queues).
 */
import { pool } from '../db.js';
import { listModerationQueue } from '../moderation/queue.js';

export type GuardianStatus = {
  openPostReports: number;
  openCommentReports: number;
  moderationReviewHeld: number;
  recentQueue: {
    entityType: string;
    entityId: string;
    decision: string;
    servingStatus: string | null;
    excerpt: string | null;
    createdAt: string;
  }[];
  policyNote: string;
};

export async function getGuardianStatus(): Promise<GuardianStatus> {
  let openPostReports = 0;
  let openCommentReports = 0;
  let moderationReviewHeld = 0;

  try {
    const { rows } = await pool.query<{ n: number }>(
      `
      select count(*)::int as n
      from public.post_reports
      where coalesce(status, 'open') in ('open', 'pending', 'in_review', 'unreviewed')
      `
    );
    openPostReports = Number(rows[0]?.n) || 0;
  } catch {
    try {
      const { rows } = await pool.query<{ n: number }>(
        `select count(*)::int as n from public.post_reports`
      );
      openPostReports = Number(rows[0]?.n) || 0;
    } catch {
      openPostReports = 0;
    }
  }

  try {
    const { rows } = await pool.query<{ n: number }>(
      `
      select count(*)::int as n
      from public.post_comment_reports
      where coalesce(status, 'open') in ('open', 'pending', 'in_review', 'unreviewed')
      `
    );
    openCommentReports = Number(rows[0]?.n) || 0;
  } catch {
    openCommentReports = 0;
  }

  try {
    const { rows } = await pool.query<{ n: number }>(
      `
      select count(*)::int as n
      from public.moderation_results
      where policy_decision in ('review', 'held', 'limited')
        and created_at > now() - interval '14 days'
      `
    );
    moderationReviewHeld = Number(rows[0]?.n) || 0;
  } catch {
    moderationReviewHeld = 0;
  }

  const queue = await listModerationQueue(12);
  return {
    openPostReports,
    openCommentReports,
    moderationReviewHeld,
    recentQueue: queue.map((q) => ({
      entityType: q.entity_type,
      entityId: q.entity_id,
      decision: q.policy_decision,
      servingStatus: q.serving_status,
      excerpt: q.excerpt,
      createdAt: q.created_at,
    })),
    policyNote:
      'Eligibility already fail-closes on hidden/deleted/sensitive. Guardian panel surfaces queue depth for Ops — appeals stay on /admin/reports.',
  };
}
