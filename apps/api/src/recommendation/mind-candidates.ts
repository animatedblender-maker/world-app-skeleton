/**
 * MIND §9 — Candidate generation lanes (Phase 1).
 *
 * Handbook wants many retrieval sources; Matterya ships explicit multi-lane
 * retrieval per surface with documented budgets. Phase 2b adds ANN;
 * Phase 3a adds cold-start prior blend (MIND-015 light).
 */

export type CandidateLaneId =
  | 'home_shortform'
  | 'home_tiktok'
  | 'home_hub'
  | 'home_image'
  | 'home_ann_title'
  | 'sparks_mm_thumb'
  | 'home_cold_start'
  | 'home_new_creator'
  | 'hubs_slug_rotate'
  | 'masquerade_fresh'
  | 'masquerade_soft_recycle'
  | 'masquerade_own';

export type CandidateLaneDef = {
  id: CandidateLaneId;
  surface: 'home_for_you' | 'hubs_for_you' | 'masquerade_for_you';
  label: string;
  description: string;
};

/** Canonical lane catalog shown on /mind and used in feed meta. */
export const MIND_CANDIDATE_LANES: CandidateLaneDef[] = [
  {
    id: 'home_shortform',
    surface: 'home_for_you',
    label: 'Home · ShortForm',
    description: 'YouTube/ShortForm spark packs (prefer /ShortForm/ paths).',
  },
  {
    id: 'home_tiktok',
    surface: 'home_for_you',
    label: 'Home · TikTok / country',
    description: 'Country/TikTok spark packs woven for variety.',
  },
  {
    id: 'home_hub',
    surface: 'home_for_you',
    label: 'Home · Hubs long-form',
    description: 'Long-form hub channel posts interleaved into Home.',
  },
  {
    id: 'home_image',
    surface: 'home_for_you',
    label: 'Home · Images',
    description: 'Image posts as a capped lane (not full-page takeover).',
  },
  {
    id: 'home_ann_title',
    surface: 'home_for_you',
    label: 'Home · ANN title/body',
    description: 'Phase 2b pgvector nearest neighbors (Voyage voyage-4-lite).',
  },
  {
    id: 'sparks_mm_thumb',
    surface: 'home_for_you',
    label: 'Sparks · multimodal thumb',
    description:
      'Phase 4.v2: Voyage voyage-multimodal-3.5 thumb+caption ANN for Sparks (all short-form).',
  },
  {
    id: 'home_cold_start',
    surface: 'home_for_you',
    label: 'Home · Cold-start priors',
    description:
      'Phase 3a (MIND-015 light): country/hub priors + popular recent + ANN when eventsCounted < 25.',
  },
  {
    id: 'home_new_creator',
    surface: 'home_for_you',
    label: 'Home · Creator opportunity',
    description:
      'Phase 3b (MIND-018): soft boost for under-exposed creators with recent posts.',
  },
  {
    id: 'hubs_slug_rotate',
    surface: 'hubs_for_you',
    label: 'Hubs · Parent-slug rotate',
    description: 'Round-robin across comedy/music/travel/… parent shelves.',
  },
  {
    id: 'masquerade_fresh',
    surface: 'masquerade_for_you',
    label: 'Masquerade · Unseen',
    description: 'anonymous.posts not yet in masquerade_for_you ledger.',
  },
  {
    id: 'masquerade_soft_recycle',
    surface: 'masquerade_for_you',
    label: 'Masquerade · Soft recycle',
    description: 'Seen keys only when fresh inventory is short; score-penalized.',
  },
  {
    id: 'masquerade_own',
    surface: 'masquerade_for_you',
    label: 'Masquerade · Own posts',
    description: 'Viewer’s recent anonymous posts pinned at top of page.',
  },
];

export type CandidateMix = {
  lane: CandidateLaneId | string;
  count: number;
};

/** Phase-1 retrieval budgets (handbook-aligned proposals, not ANN). */
export const MIND_RETRIEVAL_BUDGETS = {
  homeRawPool: 96,
  hubsRawPool: 96,
  masqueradeHotWindow: 220,
  servePage: 20,
} as const;
