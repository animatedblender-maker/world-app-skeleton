import { isPaidEnabled } from './policy.js';

const PAID_OFF = {
  ok: false as const,
  code: 'paid_disabled',
  reason:
    'Paid Spaces are not enabled yet (ANONYMOUS_PAID_ENABLED). StoreKit/legal required.',
};

export function checkoutStart(_body: unknown): {
  ok: false;
  code: string;
  reason: string;
  status: number;
} {
  if (!isPaidEnabled()) {
    return { ...PAID_OFF, status: 503 };
  }
  // Scaffold only — full checkout lands with StoreKit/legal.
  return {
    ok: false,
    code: 'not_implemented',
    reason: 'Checkout orchestration not implemented.',
    status: 501,
  };
}

export function creatorEarnings(_spaceId?: string): {
  ok: false;
  code: string;
  reason: string;
  status: number;
} {
  if (!isPaidEnabled()) {
    return { ...PAID_OFF, status: 503 };
  }
  return {
    ok: false,
    code: 'not_implemented',
    reason: 'Creator earnings not implemented.',
    status: 501,
  };
}

export function listPriceVersions(_spaceId: string): {
  ok: true;
  price_versions: unknown[];
  paid_enabled: boolean;
} {
  return { ok: true, price_versions: [], paid_enabled: isPaidEnabled() };
}
