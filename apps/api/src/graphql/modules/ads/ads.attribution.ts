import { pool } from '../../../db.js';
import { creditStudioEarnFromAdImpression } from '../../../studio/studio.service.js';

/** Served tokens older than this cannot log view/click (replay window). */
export const IMPRESSION_TOKEN_TTL_SECONDS = 2 * 60 * 60; // 2 hours

function isUuidTokenShape(token: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
    token
  );
}

export async function logImpression(
  impressionToken: string,
  userId: string | null
): Promise<boolean> {
  const token = String(impressionToken ?? '').trim();
  if (!token || !isUuidTokenShape(token)) return false;

  const { rows } = await pool.query<{
    id: string;
    post_id: string | null;
    served_at: Date;
  }>(
    `
    update public.ad_impressions
    set
      viewed_at = coalesce(viewed_at, now()),
      viewer_user_id = coalesce(viewer_user_id, $2::uuid)
    where impression_token = $1
      and served_at >= now() - ($3::int * interval '1 second')
    returning
      id::text as id,
      post_id::text as post_id,
      served_at
    `,
    [token, userId, IMPRESSION_TOKEN_TTL_SECONDS]
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
  const token = String(impressionToken ?? '').trim();
  if (!token || !isUuidTokenShape(token)) return false;

  // Click only within TTL; mark viewed if the client skipped impression.
  const { rows } = await pool.query<{
    id: string;
    campaign_id: string;
    creative_id: string;
    viewer_user_id: string | null;
  }>(
    `
    update public.ad_impressions
    set
      viewed_at = coalesce(viewed_at, now()),
      clicked_at = coalesce(clicked_at, now()),
      viewer_user_id = coalesce(viewer_user_id, $2::uuid)
    where impression_token = $1
      and served_at >= now() - ($3::int * interval '1 second')
    returning id, campaign_id, creative_id, viewer_user_id
    `,
    [token, userId, IMPRESSION_TOKEN_TTL_SECONDS]
  );
  const row = rows[0];
  if (!row) return false;

  // One click row per impression (unique index); ignore duplicates.
  await pool.query(
    `
    insert into public.ad_clicks (
      impression_id,
      campaign_id,
      creative_id,
      viewer_user_id
    )
    values ($1, $2, $3, $4)
    on conflict (impression_id) do nothing
    `,
    [row.id, row.campaign_id, row.creative_id, row.viewer_user_id]
  );
  return true;
}
