import { pool } from '../../../db.js';
import { verifyStoreKitTransactionJws } from './ads.apple-jws.js';

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
 * Redeem a StoreKit 2 consumable into one unused create credit.
 * Requires a cryptographically verified JWS (Apple Root CA G3 + leaf signature).
 * Client-supplied product/transaction ids must match the verified payload.
 */
export async function redeemCreatePurchase(
  userId: string,
  input: {
    product_id: string;
    transaction_id: string;
    original_transaction_id?: string | null;
    jws?: string | null;
  }
): Promise<AdCreateEntitlement> {
  const productId = String(input.product_id ?? '').trim();
  const transactionId = String(input.transaction_id ?? '').trim();
  if (productId !== AD_CAMPAIGN_CREATE_PRODUCT_ID) {
    throw new Error('Unknown Ads product.');
  }
  if (!transactionId) {
    throw new Error('transaction_id is required.');
  }

  const jws = input.jws != null ? String(input.jws).trim() : '';
  if (!jws) {
    throw new Error('Signed App Store transaction (jws) is required.');
  }

  const verified = await verifyStoreKitTransactionJws(jws);
  if (verified.productId !== productId) {
    throw new Error('Purchase product mismatch.');
  }
  if (verified.transactionId !== transactionId) {
    throw new Error('Purchase transaction mismatch.');
  }

  await pool.query(
    `
    insert into public.ad_create_credits (
      user_id, product_id, transaction_id, original_transaction_id, jws
    )
    values ($1::uuid, $2, $3, $4, $5)
    on conflict (transaction_id) do nothing
    `,
    [
      userId,
      verified.productId,
      verified.transactionId,
      verified.originalTransactionId ||
        (input.original_transaction_id
          ? String(input.original_transaction_id).trim()
          : null),
      jws,
    ]
  );

  return getCreateEntitlement(userId, null);
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
