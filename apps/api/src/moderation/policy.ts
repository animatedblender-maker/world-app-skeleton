import type {
  LocalRuleHit,
  PolicyDecision,
  ServingModerationStatus,
  TextModerationScores,
  TextProviderResult,
} from './types.js';

export const POLICY_VERSION =
  process.env.MODERATION_POLICY_VERSION?.trim() || 'text-mvp-1';

function envThreshold(key: string, fallback: number): number {
  const n = Number(process.env[key]);
  return Number.isFinite(n) ? Math.min(1, Math.max(0, n)) : fallback;
}

/** Tunable thresholds — env override without code change. */
export function policyThresholds() {
  return {
    toxicityLimited: envThreshold('MOD_TOXICITY_LIMITED', 0.72),
    toxicityReview: envThreshold('MOD_TOXICITY_REVIEW', 0.88),
    severeReview: envThreshold('MOD_SEVERE_REVIEW', 0.7),
    threatReview: envThreshold('MOD_THREAT_REVIEW', 0.75),
    spamLimited: envThreshold('MOD_SPAM_LIMITED', 0.65),
    spamReview: envThreshold('MOD_SPAM_REVIEW', 0.85),
  };
}

export function decisionFromScores(
  scores: TextModerationScores,
  provider: TextProviderResult,
  ruleHit: LocalRuleHit | null
): PolicyDecision {
  // Local rules win when they demand hold/review/limited.
  if (ruleHit) return ruleHit.decision;

  // NEVER treat provider failure as SAFE.
  if (!provider.ok) return 'review';

  const t = policyThresholds();
  if (
    scores.severe_toxicity >= t.severeReview ||
    scores.threat >= t.threatReview ||
    scores.toxicity >= t.toxicityReview ||
    (scores.spam ?? 0) >= t.spamReview
  ) {
    return 'review';
  }
  if (
    scores.toxicity >= t.toxicityLimited ||
    scores.insult >= t.toxicityLimited ||
    scores.obscene >= t.toxicityLimited ||
    (scores.spam ?? 0) >= t.spamLimited
  ) {
    return 'limited';
  }
  return 'safe';
}

export function mapDecisionToServing(decision: PolicyDecision): ServingModerationStatus {
  switch (decision) {
    case 'safe':
      return 'active';
    case 'limited':
      return 'sensitive';
    case 'review':
    case 'held':
      return 'hidden';
    default:
      return 'hidden';
  }
}
