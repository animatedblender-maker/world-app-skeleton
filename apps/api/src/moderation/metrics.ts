/** In-process counters for text moderation MVP (no high-cardinality labels). */

type Counters = {
  requests: number;
  rule_blocks: number;
  provider_ok: number;
  provider_fail: number;
  decision_safe: number;
  decision_limited: number;
  decision_review: number;
  decision_held: number;
  persist_fail: number;
};

const c: Counters = {
  requests: 0,
  rule_blocks: 0,
  provider_ok: 0,
  provider_fail: 0,
  decision_safe: 0,
  decision_limited: 0,
  decision_review: 0,
  decision_held: 0,
  persist_fail: 0,
};

export function modInc(key: keyof Counters, n = 1) {
  c[key] += n;
}

export function moderationMetricsSnapshot(): Counters & { ok: true } {
  return { ok: true, ...c };
}
