/**
 * Canonical Matterya moderation categories.
 * Never use Reddit slang (NSFW) — adult/sexual reports are "Mature content".
 */

export const MODERATION_CATEGORIES = [
  { slug: 'spam', label: 'Spam' },
  { slug: 'harassment', label: 'Harassment' },
  { slug: 'hate', label: 'Hate' },
  { slug: 'mature', label: 'Mature content' },
  { slug: 'violence', label: 'Violence' },
  { slug: 'self_harm', label: 'Self-harm' },
  { slug: 'misinfo', label: 'Misinformation' },
  { slug: 'scam', label: 'Scam' },
  { slug: 'doxxing', label: 'Doxxing / privacy' },
  { slug: 'other', label: 'Other' },
] as const;

export type ModerationCategorySlug = (typeof MODERATION_CATEGORIES)[number]['slug'];

const SLUG_SET = new Set<string>(MODERATION_CATEGORIES.map((c) => c.slug));

const LABEL_TO_SLUG = new Map<string, ModerationCategorySlug>(
  MODERATION_CATEGORIES.flatMap((c) => [
    [c.label.toLowerCase(), c.slug],
    [c.slug, c.slug],
  ])
);

/** Legacy / free-text reasons from older clients → canonical slug. */
const REASON_ALIASES: Record<string, ModerationCategorySlug> = {
  nsfw: 'mature',
  'sexual content': 'mature',
  sexual: 'mature',
  adult: 'mature',
  'adult content': 'mature',
  porn: 'mature',
  harassment: 'harassment',
  hate: 'hate',
  spam: 'spam',
  scam: 'scam',
  misinformation: 'misinfo',
  misinfo: 'misinfo',
  violence: 'violence',
  'self-harm': 'self_harm',
  'self harm': 'self_harm',
  self_harm: 'self_harm',
  doxxing: 'doxxing',
  'doxxing / identity': 'doxxing',
  'doxxing / privacy': 'doxxing',
  privacy: 'doxxing',
  other: 'other',
};

export function isModerationCategory(value: unknown): value is ModerationCategorySlug {
  return typeof value === 'string' && SLUG_SET.has(value);
}

export function labelForCategory(slug: string): string {
  const hit = MODERATION_CATEGORIES.find((c) => c.slug === slug);
  return hit?.label ?? slug;
}

/**
 * Normalize reporter input (slug, label, or legacy free-text) to a category slug.
 * Unknown → `other`.
 */
export function normalizeCategory(
  raw: string | null | undefined,
  fallback: ModerationCategorySlug = 'other'
): ModerationCategorySlug {
  const t = String(raw ?? '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, ' ');
  if (!t) return fallback;
  if (SLUG_SET.has(t)) return t as ModerationCategorySlug;
  const fromLabel = LABEL_TO_SLUG.get(t);
  if (fromLabel) return fromLabel;
  if (REASON_ALIASES[t]) return REASON_ALIASES[t]!;
  // Partial contains (e.g. "this is spam")
  for (const [alias, slug] of Object.entries(REASON_ALIASES)) {
    if (t.includes(alias)) return slug;
  }
  return fallback;
}

export type ModerationPlatform = 'feed' | 'sparks' | 'hubs' | 'masquerade' | 'messages';
export type ModerationTargetKind =
  | 'post'
  | 'comment'
  | 'message'
  | 'space'
  | 'profile'
  | 'conversation';
