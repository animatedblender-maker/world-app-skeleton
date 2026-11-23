import { pool } from '../../../db.js';
import { creditStudioEarnFromAdImpression } from '../../../studio/studio.service.js';

export async function logImpression(
  impressionToken: string,
  userId: string | null
): Promise<boolean> {
  const { rows } = await pool.query<{
    id: string;
    post_id: string | null;
  }>(
    `
    update public.ad_impressions
    set
      viewed_at = coalesce(viewed_at, now()),
      viewer_user_id = coalesce(viewer_user_id, $2)
    where impression_token = $1
    returning
      id::text as id,
      post_id::text as post_id
    `,
    [impressionToken, userId]
  );
  const row = rows[0];
  if (!row) return false;

  // Credit creator ledger once per impression (idempotent on source_ref).
  try {
    await creditStudioEarnFromAdImpression({
      impressionId: row.id,
      postId: row.post_id,
    });
  } catch (err) {
    console.error('[ads] studio earn credit failed (non-fatal)', {
      impression_id: row.id,
      post_id: row.post_id,
      error: err,
    });
  }
  return true;
}

export async function logClick(
  impressionToken: string,
  userId: string | null
): Promise<boolean> {
  const { rows } = await pool.query<{
    id: string;
    campaign_id: string;
    creative_id: string;
    viewer_user_id: string | null;
  }>(
    `
    update public.ad_impressions
    set
      clicked_at = coalesce(clicked_at, now()),
      viewer_user_id = coalesce(viewer_user_id, $2)
    where impression_token = $1
    returning id, campaign_id, creative_id, viewer_user_id
    `,
    [impressionToken, userId]
  );
  const row = rows[0];
  if (!row) return false;
  await pool.query(
    `
    insert into public.ad_clicks (
      impression_id,
      campaign_id,
      creative_id,
      viewer_user_id
    )
    values ($1, $2, $3, $4)
    `,
    [row.id, row.campaign_id, row.creative_id, row.viewer_user_id]
  );
  return true;
}
