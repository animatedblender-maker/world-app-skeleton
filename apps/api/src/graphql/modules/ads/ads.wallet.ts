import Stripe from 'stripe';

import { pool } from '../../../db.js';

/** Must match ads.serve pacing + iOS AdsBudgetEstimate. */
export const ADS_COST_PER_IMPRESSION_CENTS = 10;
export const ADS_WALLET_CURRENCY = 'eur';
export const ADS_TOPUP_MIN_CENTS = 500; // €5
export const ADS_TOPUP_MAX_CENTS = 500_000; // €5,000

export type AdsWallet = {
  balance_cents: number;
  currency: string;
  has_payment_method: boolean;
  billing_configured: boolean;
  cost_per_impression_cents: number;
};

export type AdsCheckoutSession = {
  url: string;
  kind: 'setup' | 'topup';
};

function stripeSecret(): string | null {
  const key = String(process.env.STRIPE_SECRET_KEY ?? '').trim();
  return key || null;
}

export function isAdsBillingConfigured(): boolean {
  return !!stripeSecret() && !!String(process.env.STRIPE_WEBHOOK_SECRET ?? '').trim();
}

export function getStripe(): Stripe {
  const key = stripeSecret();
  if (!key) {
    const err = new Error('Ads billing is not configured (missing STRIPE_SECRET_KEY).');
    (err as any).code = 'ADS_BILLING_NOT_CONFIGURED';
    throw err;
  }
  return new Stripe(key);
}

function returnUrls(): { success: string; cancel: string } {
  const base = String(
    process.env.ADS_WALLET_RETURN_URL ?? 'https://matterya.com/ads/wallet-return'
  ).trim();
  const success = base.includes('?')
    ? `${base}&status=success`
    : `${base}?status=success`;
  const cancel = base.includes('?')
    ? `${base}&status=cancel`
    : `${base}?status=cancel`;
  return { success, cancel };
}

async function ensureAdvertiserRow(userId: string): Promise<void> {
  await pool.query(
    `
    insert into public.ad_advertisers (user_id)
    values ($1::uuid)
    on conflict (user_id) do nothing
    `,
    [userId]
  );
}

export async function ensureStripeCustomer(
  userId: string,
  email?: string | null
): Promise<string> {
  await ensureAdvertiserRow(userId);
  const { rows } = await pool.query<{ stripe_customer_id: string | null }>(
    `select stripe_customer_id from public.ad_advertisers where user_id = $1::uuid`,
    [userId]
  );
  const existing = rows[0]?.stripe_customer_id;
  if (existing) return existing;

  const stripe = getStripe();
  const customer = await stripe.customers.create({
    email: email ? String(email).trim() || undefined : undefined,
    metadata: { matterya_user_id: userId },
  });
  await pool.query(
    `
    update public.ad_advertisers
    set stripe_customer_id = $2, updated_at = now()
    where user_id = $1::uuid
      and stripe_customer_id is null
    `,
    [userId, customer.id]
  );
  // Race: another request may have set it.
  const again = await pool.query<{ stripe_customer_id: string | null }>(
    `select stripe_customer_id from public.ad_advertisers where user_id = $1::uuid`,
    [userId]
  );
  return again.rows[0]?.stripe_customer_id || customer.id;
}

export async function getWallet(userId: string): Promise<AdsWallet> {
  await ensureAdvertiserRow(userId);
  const { rows } = await pool.query<{
    wallet_balance_cents: number;
    default_payment_method_id: string | null;
  }>(
    `
    select wallet_balance_cents, default_payment_method_id
    from public.ad_advertisers
    where user_id = $1::uuid
    `,
    [userId]
  );
  const row = rows[0];
  return {
    balance_cents: Number(row?.wallet_balance_cents ?? 0) || 0,
    currency: ADS_WALLET_CURRENCY,
    has_payment_method: !!row?.default_payment_method_id,
    billing_configured: !!stripeSecret(),
    cost_per_impression_cents: ADS_COST_PER_IMPRESSION_CENTS,
  };
}

export async function createWalletCheckout(
  userId: string,
  input: { kind: 'setup' | 'topup'; amount_cents?: number | null },
  email?: string | null
): Promise<AdsCheckoutSession> {
  const kind = input.kind === 'setup' ? 'setup' : 'topup';
  const customerId = await ensureStripeCustomer(userId, email);
  const stripe = getStripe();
  const { success, cancel } = returnUrls();

  if (kind === 'setup') {
    const session = await stripe.checkout.sessions.create({
      mode: 'setup',
      customer: customerId,
      success_url: success,
      cancel_url: cancel,
      currency: ADS_WALLET_CURRENCY,
      metadata: {
        matterya_user_id: userId,
        matterya_kind: 'setup',
      },
    });
    if (!session.url) throw new Error('Stripe Checkout did not return a URL.');
    return { url: session.url, kind: 'setup' };
  }

  const amount = Math.floor(Number(input.amount_cents ?? 0) || 0);
  if (amount < ADS_TOPUP_MIN_CENTS || amount > ADS_TOPUP_MAX_CENTS) {
    throw new Error(
      `Top-up must be between €${(ADS_TOPUP_MIN_CENTS / 100).toFixed(0)} and €${(
        ADS_TOPUP_MAX_CENTS / 100
      ).toFixed(0)}.`
    );
  }

  const session = await stripe.checkout.sessions.create({
    mode: 'payment',
    customer: customerId,
    success_url: success,
    cancel_url: cancel,
    client_reference_id: userId,
    metadata: {
      matterya_user_id: userId,
      matterya_kind: 'topup',
      amount_cents: String(amount),
    },
    line_items: [
      {
        quantity: 1,
        price_data: {
          currency: ADS_WALLET_CURRENCY,
          unit_amount: amount,
          product_data: {
            name: 'Matterya Ads wallet top-up',
            description: 'Prepaid balance for Sparks and Hubs ad delivery.',
          },
        },
      },
    ],
    payment_intent_data: {
      setup_future_usage: 'off_session',
      metadata: {
        matterya_user_id: userId,
        matterya_kind: 'topup',
      },
    },
  });
  if (!session.url) throw new Error('Stripe Checkout did not return a URL.');
  return { url: session.url, kind: 'topup' };
}

async function creditTopUp(params: {
  userId: string;
  amountCents: number;
  stripeEventId: string;
  checkoutSessionId: string | null;
  paymentMethodId?: string | null;
}): Promise<void> {
  const client = await pool.connect();
  try {
    await client.query('begin');
    const dup = await client.query(
      `select 1 from public.ad_wallet_ledger where stripe_event_id = $1 limit 1`,
      [params.stripeEventId]
    );
    if (dup.rows.length) {
      await client.query('commit');
      return;
    }

    await client.query(
      `
      insert into public.ad_advertisers (user_id)
      values ($1::uuid)
      on conflict (user_id) do nothing
      `,
      [params.userId]
    );

    const { rows } = await client.query<{ wallet_balance_cents: number }>(
      `
      update public.ad_advertisers
      set
        wallet_balance_cents = wallet_balance_cents + $2,
        default_payment_method_id = coalesce($3, default_payment_method_id),
        updated_at = now()
      where user_id = $1::uuid
      returning wallet_balance_cents
      `,
      [params.userId, params.amountCents, params.paymentMethodId ?? null]
    );
    const balance = Number(rows[0]?.wallet_balance_cents ?? 0) || 0;
    await client.query(
      `
      insert into public.ad_wallet_ledger (
        user_id, kind, amount_cents, balance_after_cents,
        stripe_event_id, stripe_checkout_session_id, note
      )
      values ($1::uuid, 'topup', $2, $3, $4, $5, $6)
      `,
      [
        params.userId,
        params.amountCents,
        balance,
        params.stripeEventId,
        params.checkoutSessionId,
        'Stripe Checkout top-up',
      ]
    );
    await client.query('commit');
  } catch (err) {
    await client.query('rollback');
    throw err;
  } finally {
    client.release();
  }
}

async function markPaymentMethod(params: {
  userId: string;
  paymentMethodId: string;
  stripeEventId: string;
  checkoutSessionId: string | null;
}): Promise<void> {
  // Idempotent: stripe_event_id unique. amount_cents is audit-only (balance unchanged).
  const bal = await pool.query<{ wallet_balance_cents: number }>(
    `
    update public.ad_advertisers
    set default_payment_method_id = $2, updated_at = now()
    where user_id = $1::uuid
    returning wallet_balance_cents
    `,
    [params.userId, params.paymentMethodId]
  );
  const balance = Number(bal.rows[0]?.wallet_balance_cents ?? 0) || 0;
  try {
    await pool.query(
      `
      insert into public.ad_wallet_ledger (
        user_id, kind, amount_cents, balance_after_cents,
        stripe_event_id, stripe_checkout_session_id, note
      )
      values ($1::uuid, 'adjust', 0, $2, $3, $4, $5)
      `,
      [
        params.userId,
        balance,
        params.stripeEventId,
        params.checkoutSessionId,
        `Payment method saved: ${params.paymentMethodId}`,
      ]
    );
  } catch (err: any) {
    if (err?.code === '23505') return;
    throw err;
  }
}

/**
 * Debit wallet once per impression (counted view). Returns false if insufficient funds.
 */
export async function debitImpression(params: {
  advertiserUserId: string;
  campaignId: string;
  impressionId: string;
  amountCents?: number;
}): Promise<boolean> {
  const cost = params.amountCents ?? ADS_COST_PER_IMPRESSION_CENTS;
  const client = await pool.connect();
  try {
    await client.query('begin');
    const existing = await client.query(
      `
      select 1 from public.ad_wallet_ledger
      where impression_id = $1::uuid and kind = 'debit_impression'
      limit 1
      `,
      [params.impressionId]
    );
    if (existing.rows.length) {
      await client.query('commit');
      return true;
    }

    const { rows } = await client.query<{ wallet_balance_cents: number }>(
      `
      update public.ad_advertisers
      set
        wallet_balance_cents = wallet_balance_cents - $2,
        updated_at = now()
      where user_id = $1::uuid
        and wallet_balance_cents >= $2
      returning wallet_balance_cents
      `,
      [params.advertiserUserId, cost]
    );
    if (!rows.length) {
      await client.query('rollback');
      return false;
    }
    const balance = Number(rows[0]!.wallet_balance_cents) || 0;
    await client.query(
      `
      insert into public.ad_wallet_ledger (
        user_id, kind, amount_cents, balance_after_cents,
        campaign_id, impression_id, note
      )
      values ($1::uuid, 'debit_impression', $2, $3, $4::uuid, $5::uuid, $6)
      `,
      [
        params.advertiserUserId,
        -cost,
        balance,
        params.campaignId,
        params.impressionId,
        'Impression delivery debit',
      ]
    );
    await client.query('commit');
    return true;
  } catch (err: any) {
    await client.query('rollback');
    if (err?.code === '23505') return true;
    throw err;
  } finally {
    client.release();
  }
}

export async function handleStripeWebhook(
  rawBody: Buffer,
  signature: string | undefined
): Promise<{ ok: boolean }> {
  const secret = String(process.env.STRIPE_WEBHOOK_SECRET ?? '').trim();
  if (!secret) {
    const err = new Error('STRIPE_WEBHOOK_SECRET missing');
    (err as any).code = 'ADS_BILLING_NOT_CONFIGURED';
    throw err;
  }
  const stripe = getStripe();
  let event: Stripe.Event;
  try {
    event = stripe.webhooks.constructEvent(rawBody, signature ?? '', secret);
  } catch (err) {
    const e = new Error(
      `Stripe signature verification failed: ${(err as Error).message}`
    );
    (e as any).code = 'STRIPE_SIGNATURE_INVALID';
    throw e;
  }

  if (
    event.type !== 'checkout.session.completed' &&
    event.type !== 'checkout.session.async_payment_succeeded'
  ) {
    return { ok: true };
  }

  const session = event.data.object as Stripe.Checkout.Session;
  const userId =
    session.metadata?.matterya_user_id ||
    session.client_reference_id ||
    null;
  if (!userId) {
    console.warn('[ads.wallet] checkout without matterya_user_id', session.id);
    return { ok: true };
  }

  const kind = session.metadata?.matterya_kind || session.mode;

  if (session.mode === 'setup' || kind === 'setup') {
    const setupIntentId =
      typeof session.setup_intent === 'string'
        ? session.setup_intent
        : session.setup_intent?.id;
    let pmId: string | null = null;
    if (setupIntentId) {
      const si = await stripe.setupIntents.retrieve(setupIntentId);
      pmId =
        typeof si.payment_method === 'string'
          ? si.payment_method
          : si.payment_method?.id ?? null;
    }
    if (pmId) {
      await markPaymentMethod({
        userId,
        paymentMethodId: pmId,
        stripeEventId: event.id,
        checkoutSessionId: session.id,
      });
    }
    return { ok: true };
  }

  if (session.mode === 'payment' || kind === 'topup') {
    if (session.payment_status !== 'paid' && event.type === 'checkout.session.completed') {
      // Wait for async_payment_succeeded when not yet paid.
      if (session.payment_status !== 'no_payment_required') {
        return { ok: true };
      }
    }
    const amount =
      Number(session.metadata?.amount_cents ?? 0) ||
      Number(session.amount_total ?? 0) ||
      0;
    if (amount <= 0) {
      console.warn('[ads.wallet] top-up with zero amount', session.id);
      return { ok: true };
    }
    let pmId: string | null = null;
    const piId =
      typeof session.payment_intent === 'string'
        ? session.payment_intent
        : session.payment_intent?.id;
    if (piId) {
      const pi = await stripe.paymentIntents.retrieve(piId);
      pmId =
        typeof pi.payment_method === 'string'
          ? pi.payment_method
          : pi.payment_method?.id ?? null;
    }
    await creditTopUp({
      userId,
      amountCents: amount,
      stripeEventId: event.id,
      checkoutSessionId: session.id,
      paymentMethodId: pmId,
    });
  }

  return { ok: true };
}
