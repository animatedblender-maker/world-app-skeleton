/**
 * Hard eligibility gates before soft ranking (MIND handbook §2 / §10).
 * Fail closed for safety; callers still apply surface-specific SQL filters.
 */

import type { MindSurface } from './mind-contracts.js';

export type EligibilityInput = {
  id?: string | null;
  state?: string | null;
  moderation_status?: string | null;
  visibility?: string | null;
  is_deleted?: boolean | null;
  author_blocked?: boolean | null;
  media_processing?: boolean | null;
  /** Public posts only — never pass Masquerade rows into public surfaces. */
  namespace?: 'public' | 'masquerade';
};

export type EligibilityResult = {
  ok: boolean;
  reason?: string;
};

const BLOCKED_MOD = new Set([
  'removed',
  'rejected',
  'banned',
  'illegal',
  'csam',
]);

/**
 * Surface-agnostic hard checks. Soft scoring must not override a false result.
 */
export function isEligibleForSurface(
  row: EligibilityInput,
  surface: MindSurface | string
): EligibilityResult {
  if (!row?.id) return { ok: false, reason: 'missing_id' };

  if (row.is_deleted) return { ok: false, reason: 'deleted' };
  if (row.author_blocked) return { ok: false, reason: 'blocked' };

  const state = String(row.state ?? 'active').toLowerCase();
  if (state && state !== 'active' && state !== 'published') {
    return { ok: false, reason: `state:${state}` };
  }

  const mod = String(row.moderation_status ?? '').toLowerCase();
  if (mod && BLOCKED_MOD.has(mod)) {
    return { ok: false, reason: `moderation:${mod}` };
  }

  if (row.media_processing) {
    return { ok: false, reason: 'processing' };
  }

  // Namespace isolation — public MIND never ranks masquerade rows.
  const ns = row.namespace ?? 'public';
  const surf = String(surface);
  if (ns === 'masquerade' && !surf.startsWith('masquerade')) {
    return { ok: false, reason: 'namespace_isolation' };
  }
  if (ns === 'public' && surf.startsWith('masquerade')) {
    // Masquerade feed should not pull public social posts as native cards.
    return { ok: false, reason: 'namespace_isolation' };
  }

  return { ok: true };
}

export function filterEligible<T extends EligibilityInput>(
  rows: T[],
  surface: MindSurface | string
): T[] {
  return rows.filter((r) => isEligibleForSurface(r, surface).ok);
}
