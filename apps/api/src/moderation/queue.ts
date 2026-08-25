import { pool } from '../db.js';

export type ModerationQueueItem = {
  entity_type: string;
  entity_id: string;
  policy_decision: string;
  provider: string;
  model_version: string;
  policy_version: string;
  created_at: string;
  excerpt: string | null;
  serving_status: string | null;
};

/** Recent REVIEW/HELD decisions for admin (text MVP). */
export async function listModerationQueue(limit = 40): Promise<ModerationQueueItem[]> {
  const safe = Math.max(1, Math.min(100, Number(limit) || 40));
  try {
    const { rows } = await pool.query<ModerationQueueItem>(
      `
      select
        mr.entity_type::text as entity_type,
        mr.entity_id::text as entity_id,
        mr.policy_decision::text as policy_decision,
        mr.provider::text as provider,
        mr.model_version::text as model_version,
        mr.policy_version::text as policy_version,
        mr.created_at::text as created_at,
        case
          when mr.entity_type = 'post' then left(trim(concat(coalesce(p.title, ''), ' ', coalesce(p.body, ''))), 160)
          else left(coalesce(c.body, ''), 160)
        end as excerpt,
        case
          when mr.entity_type = 'post' then coalesce(p.moderation_status, 'active')
          else coalesce(c.moderation_status, 'active')
        end::text as serving_status
      from public.moderation_results mr
      left join public.posts p
        on mr.entity_type = 'post' and p.id = mr.entity_id
      left join public.post_comments c
        on mr.entity_type = 'comment' and c.id = mr.entity_id
      where mr.policy_decision in ('review', 'held', 'limited')
      order by mr.created_at desc
      limit $1
      `,
      [safe]
    );
    return rows;
  } catch (err: any) {
    // Table may not exist until migration is applied.
    console.warn('[moderation] queue unavailable', err?.message ?? err);
    return [];
  }
}
