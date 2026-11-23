import { pool } from '../../../db.js';
import { creditStudioEarnFromAdImpression } from '../../../studio/studio.service.js';
import { debitImpression } from './ads.wallet.js';

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
    campaign_id: string;
    advertiser_user_id: string;
  }>(
    `
    update public.ad_impressions i
    set
      viewed_at = coalesce(i.viewed_at, now()),
      viewer_user_id = coalesce(i.viewer_user_id, $2::uuid)
    from public.ad_campaigns c
    where i.impression_token = $1
      and i.campaign_id = c.id
      and i.served_at >= now() - ($3::int * interval '1 second')
    returning
      i.id::text as id,
      i.post_id::text as post_id,
      i.campaign_id::text as campaign_id,
      c.advertiser_user_id::text as advertiser_user_id
    `,
    [token, userId, IMPRESSION_TOKEN_TTL_SECONDS]
  );
  // Debit is idempotent on impression_id — safe on every call.
  const row = rows[0];
  if (!row) return false;

  try {
    await debitImpression({
      advertiserUserId: row.advertiser_user_id,
      campaignId: row.campaign_id,
      impressionId: row.id,
    });
  } catch (err) {
    console.error('[ads] wallet debit failed (non-fatal)', {
      impression_id: row.id,
      error: err,
    });
  }

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
    advertiser_user_id: string;
  }>(
    `
    update public.ad_impressions i
    set
      viewed_at = coalesce(i.viewed_at, now()),
      clicked_at = coalesce(i.clicked_at, now()),
      viewer_user_id = coalesce(i.viewer_user_id, $2::uuid)
    from public.ad_campaigns c
    where i.impression_token = $1
      and i.campaign_id = c.id
      and i.served_at >= now() - ($3::int * interval '1 second')
    returning
      i.id,
      i.campaign_id,
      i.creative_id,
      i.viewer_user_id,
      c.advertiser_user_id::text as advertiser_user_id
    `,
    [token, userId, IMPRESSION_TOKEN_TTL_SECONDS]
  );
  const row = rows[0];
  if (!row) return false;

  try {
    await debitImpression({
      advertiserUserId: row.advertiser_user_id,
      campaignId: String(row.campaign_id),
      impressionId: String(row.id),
    });
  } catch (err) {
    console.error('[ads] wallet debit on click failed (non-fatal)', err);
  }

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
