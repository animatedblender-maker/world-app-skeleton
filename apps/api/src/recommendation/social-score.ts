/**
 * Shared social ranking primitives (Wilson / time decay / MMR).
 * Used by Home, Hubs, and Masquerade For you — keep pure + unit-testable.
 */

/** Wilson score lower bound for upvote ratio (Reddit-stable under low counts). */
export function wilsonLowerBound(
  ups: number,
  downs = 0,
  z = 1.96
): number {
  const n = Math.max(0, ups) + Math.max(0, downs);
  if (n <= 0) return 0;
  const phat = Math.max(0, ups) / n;
  const z2 = z * z;
  const denom = 1 + z2 / n;
  const centre = phat + z2 / (2 * n);
  const margin = z * Math.sqrt((phat * (1 - phat) + z2 / (4 * n)) / n);
  return (centre - margin) / denom;
}

/** Exponential time decay — half-life in hours (HN / Reddit Hot style). */
export function timeDecay(ageHours: number, halfLifeHours = 18): number {
  const age = Math.max(0, ageHours);
  const hl = Math.max(0.5, halfLifeHours);
  return Math.exp((-Math.LN2 * age) / hl);
}

export type MmrCandidate = {
  id: string;
  score: number;
  authorId?: string | null;
  family?: string | null;
  mediaKey?: string | null;
  spaceId?: string | null;
};

export type MmrOptions = {
  /** Relevance vs diversity (0…1). Higher → keep more of pointwise score. */
  lambda?: number;
  limit: number;
  creatorWindow?: number;
  maxSameCreator?: number;
  /** Families that must not sit adjacent (e.g. tiktok + image). */
  exclusiveFamilies?: string[];
  /** Max exclusive-family cards per this many slots (e.g. 1 per 4). */
  exclusiveEveryN?: number;
};

/**
 * Greedy MMR / constrained diversity pick (Instagram/TikTok serving style).
 * Penalizes same creator in window, same media key, adjacent exclusive families,
 * and enforces a frequency cap on exclusive families (TikTok/image).
 */
export function mmrPick<T extends MmrCandidate>(
  candidates: T[],
  opts: MmrOptions
): T[] {
  const limit = Math.max(1, opts.limit);
  const lambda = Math.min(1, Math.max(0, opts.lambda ?? 0.72));
  const creatorWindow = Math.max(1, opts.creatorWindow ?? 8);
  const maxSameCreator = Math.max(1, opts.maxSameCreator ?? 2);
  const exclusive = new Set(
    (opts.exclusiveFamilies ?? ['tiktok', 'image', 'tiktok_image']).map((s) =>
      s.toLowerCase()
    )
  );
  const exclusiveEveryN = Math.max(2, opts.exclusiveEveryN ?? 4);

  const remaining = [...candidates].sort((a, b) => b.score - a.score);
  const out: T[] = [];
  const usedIds = new Set<string>();
  const usedMedia = new Set<string>();

  const isExclusive = (c: T) =>
    !!c.family && exclusive.has(String(c.family).toLowerCase());

  while (out.length < limit && remaining.length) {
    let bestI = -1;
    let bestM = -Infinity;
    const exclusiveInOut = out.filter(isExclusive).length;
    // At most ~1 exclusive (TikTok/image) per exclusiveEveryN slots.
    const canTakeExclusive =
      exclusiveInOut < Math.max(1, Math.ceil((out.length + 1) / exclusiveEveryN));

    for (let i = 0; i < remaining.length; i++) {
      const c = remaining[i]!;
      if (usedIds.has(c.id)) continue;
      if (c.mediaKey && usedMedia.has(c.mediaKey)) continue;

      let m = lambda * c.score;

      if (isExclusive(c)) {
        if (!canTakeExclusive) continue;
        const prev = out[out.length - 1];
        if (prev && isExclusive(prev)) m -= 6;
        // Prefer spacing
        m -= exclusiveInOut * 0.35;
      }

      const recent = out.slice(-creatorWindow);
      if (c.authorId) {
        const same = recent.filter((x) => x.authorId === c.authorId).length;
        if (same >= maxSameCreator) m -= 8;
        else if (same > 0) m -= same * 1.5;
        if (out.length && out[out.length - 1]?.authorId === c.authorId) m -= 4;
      }

      if (c.spaceId && out.length && out[out.length - 1]?.spaceId === c.spaceId) {
        m -= 1.2;
      }
      if (c.family && out.length && out[out.length - 1]?.family === c.family) {
        m -= 2.5;
      }

      // Diversity term vs already picked (classic MMR)
      let sim = 0;
      for (const p of out.slice(-6)) {
        if (c.authorId && p.authorId === c.authorId) sim += 0.45;
        if (c.family && p.family === c.family) sim += 0.35;
        if (c.mediaKey && p.mediaKey === c.mediaKey) sim += 1;
        if (c.spaceId && p.spaceId === c.spaceId) sim += 0.2;
      }
      m -= (1 - lambda) * sim;

      if (m > bestM) {
        bestM = m;
        bestI = i;
      }
    }

    if (bestI < 0) break;
    const [pick] = remaining.splice(bestI, 1);
    if (!pick) break;
    usedIds.add(pick.id);
    if (pick.mediaKey) usedMedia.add(pick.mediaKey);
    out.push(pick);
  }

  return out;
}

/** Pointwise Hot-like score for Masquerade / simple SQL replacements. */
export function socialHotScore(input: {
  ups: number;
  downs?: number;
  commentCount?: number;
  ageHours: number;
  membershipBoost?: number;
  halfLifeHours?: number;
}): number {
  const wilson = wilsonLowerBound(input.ups, input.downs ?? 0);
  const comments = Math.min(1, Math.log1p(Math.max(0, input.commentCount ?? 0)) / 4);
  const decay = timeDecay(input.ageHours, input.halfLifeHours ?? 18);
  const member = input.membershipBoost ?? 0.35;
  return 0.45 * wilson + 0.2 * comments + 0.25 * decay + 0.1 * member;
}
