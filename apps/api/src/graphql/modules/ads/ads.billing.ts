import { pool } from '../../../db.js';
/** StoreKit consumable — pay once per new campaign create (not a subscription). */
export const AD_CAMPAIGN_CREATE_PRODUCT_ID =
  'com.matterya.worldapp.ads.campaign_create';

const DEFAULT_ADS_FREE_CREATE_EMAILS = ['animatedblender@gmail.com'];

function adsFreeCreateEmails(): Set<string> {
  const extra = String(process.env.ADS_FREE_CREATE_EMAILS ?? '')
    .split(/[,;\s]+/)
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
  return new Set([...DEFAULT_ADS_FREE_CREATE_EMAILS, ...extra]);
}

export function isAdsFreeCreateEmail(email?: string | null): boolean {
  const e = String(email ?? '')
    .trim()
    .toLowerCase();
  return !!e && adsFreeCreateEmails().has(e);
}

export type AdCreateEntitlement = {
  free_create: boolean;
  credits_available: number;
  product_id: string;
};

export async function resolveUserEmail(
  userId: string,
  jwtEmail?: string | null
): Promise<string | null> {
  const fromJwt = String(jwtEmail ?? '')
    .trim()
    .toLowerCase();
  if (fromJwt) return fromJwt;
  const { rows } = await pool.query<{ email: string | null }>(
    `select email from auth.users where id = $1::uuid limit 1`,
    [userId]
  );
  const email = String(rows[0]?.email ?? '')
    .trim()
    .toLowerCase();
  return email || null;
}

export async function getCreateEntitlement(
  userId: string,
  jwtEmail?: string | null
): Promise<AdCreateEntitlement> {
  const email = await resolveUserEmail(userId, jwtEmail);
  if (isAdsFreeCreateEmail(email)) {
    return {
      free_create: true,
      credits_available: 0,
      product_id: AD_CAMPAIGN_CREATE_PRODUCT_ID,
    };
  }
  const { rows } = await pool.query<{ n: string }>(
    `
    select count(*)::text as n
    from public.ad_create_credits
    where user_id = $1::uuid
      and consumed_at is null
    `,
    [userId]
  );
  return {
    free_create: false,
    credits_available: Number(rows[0]?.n ?? 0) || 0,
    product_id: AD_CAMPAIGN_CREATE_PRODUCT_ID,
  };
}

/**
 * Ads create IAP is retired — Matterya Ads uses Stripe prepaid wallet only.
 * Kept so old clients get a clear error instead of silent credit minting.
 */
export async function redeemCreatePurchase(
  _userId: string,
  _input: {
    product_id: string;
    transaction_id: string;
    original_transaction_id?: string | null;
    jws?: string | null;
  }
): Promise<AdCreateEntitlement> {
  const err = new Error(
    'Ads App Store IAP is disabled. Top up the Matterya Ads wallet with Stripe.'
  );
  (err as any).code = 'ADS_IAP_DISABLED';
  throw err;
}

export async function consumeCreateCredit(
  userId: string,
  campaignId: string
): Promise<boolean> {
  const client = await pool.connect();
  try {
    await client.query('begin');
    const { rows } = await client.query<{ id: string }>(
      `
      select id
      from public.ad_create_credits
      where user_id = $1::uuid
        and consumed_at is null
      order by purchased_at asc
      for update skip locked
      limit 1
      `,
      [userId]
    );
    if (!rows.length) {
      await client.query('rollback');
      return false;
    }
    await client.query(
      `
      update public.ad_create_credits
      set consumed_at = now(), campaign_id = $2::uuid
      where id = $1::uuid
      `,
      [rows[0]!.id, campaignId]
    );
    await client.query('commit');
    return true;
  } catch (err) {
    await client.query('rollback');
    throw err;
  } finally {
    client.release();
  }
}
