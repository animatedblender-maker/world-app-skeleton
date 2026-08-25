export type ModerationEntityType = 'post' | 'comment';

/** Policy decisions (architecture). Mapped to DB moderation_status for serving. */
export type PolicyDecision = 'safe' | 'limited' | 'review' | 'held';

/** Serving enum already on posts (and comments after migration). */
export type ServingModerationStatus = 'active' | 'sensitive' | 'hidden' | 'deleted';

export type TextModerationScores = {
  toxicity: number;
  severe_toxicity: number;
  obscene: number;
  threat: number;
  insult: number;
  identity_attack: number;
  spam?: number;
};

export type TextProviderResult = {
  scores: TextModerationScores;
  provider: string;
  modelVersion: string;
  ok: boolean;
  error?: string;
};

export type LocalRuleHit = {
  code: string;
  reason: string;
  decision: PolicyDecision;
};

export type ModerateTextInput = {
  entityType: ModerationEntityType;
  entityId: string;
  text: string;
  /** When false, skip entirely (feature flag). */
  enabled?: boolean;
};

export type ModerateTextResult = {
  decision: PolicyDecision;
  servingStatus: ServingModerationStatus;
  provider: string;
  modelVersion: string;
  policyVersion: string;
  rawScores: TextModerationScores;
  ruleHit?: LocalRuleHit;
  cached?: boolean;
};
