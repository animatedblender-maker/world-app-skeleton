/**
 * MIND §8 — Interest / preference memory (Phase 1).
 *
 * Matterya stores online features in:
 *   - public.entity_personality (hub/country/creator/media maps + feature_vector)
 *   - public.recsys_user_creator_affinity (creator scores)
 *   - public.recsys_item_stats (item popularity priors)
 *
 * Rank reads these in rank.service and reports featureHits on each decision.
 * Session vectors / trained embeddings remain Phase 2+.
 */

export const MIND_INTEREST_SOURCES = [
  {
    id: 'creator_affinity',
    table: 'recsys_user_creator_affinity',
    label: 'Creator affinity',
    usedBy: 'rank.service · personalized creator boost',
  },
  {
    id: 'item_stats',
    table: 'recsys_item_stats',
    label: 'Item stats',
    usedBy: 'rank.service · popularity / quality prior',
  },
  {
    id: 'personality',
    table: 'entity_personality',
    label: 'Personality bubbles',
    usedBy: 'knn.service · hub/country/creator bubbles + feature_vector',
  },
] as const;
