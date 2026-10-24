import { randomInt } from 'node:crypto';

const ADJECTIVES = [
  'quiet', 'bright', 'swift', 'calm', 'bold', 'keen', 'soft', 'wild',
  'clear', 'noble', 'brave', 'clever', 'gentle', 'lucky', 'mellow', 'nimble',
  'proud', 'rapid', 'silent', 'steady', 'sunny', 'vivid', 'witty', 'zesty',
  'amber', 'azure', 'coral', 'cosmic', 'crimson', 'distant', 'frosty', 'golden',
  'hidden', 'ivory', 'jade', 'lunar', 'misty', 'neon', 'orbit', 'polar',
  'radiant', 'silver', 'solar', 'steel', 'tidal', 'velvet', 'violet', 'winter',
  'ancient', 'arctic', 'blooming', 'copper', 'drift', 'ember', 'feral', 'glinting',
  'hollow', 'indigo', 'jolly', 'kindled', 'luminous', 'mossy', 'northern', 'opal',
  'pale', 'quieted', 'rustic', 'sable', 'teal', 'umber', 'veiled', 'woven',
  'ambered', 'brisk', 'cedar', 'dusk', 'eerie', 'faint', 'gilded', 'hushed',
];

const NOUNS = [
  'orbit', 'comet', 'river', 'forest', 'harbor', 'meadow', 'nebula', 'pebble',
  'phoenix', 'quartz', 'raven', 'spark', 'summit', 'thunder', 'valley', 'willow',
  'anchor', 'beacon', 'canyon', 'delta', 'ember', 'falcon', 'glacier', 'horizon',
  'island', 'jasper', 'kite', 'lantern', 'mirror', 'nova', 'oasis', 'prism',
  'quill', 'reef', 'shadow', 'temple', 'umbra', 'voyage', 'whisper', 'zenith',
  'archive', 'brook', 'cipher', 'dusk', 'echo', 'fjord', 'grove', 'haven',
  'inkwell', 'junction', 'keel', 'ledge', 'mosaic', 'nightfall', 'onyx', 'petal',
  'quarry', 'ridge', 'sigil', 'thicket', 'undertow', 'vault', 'wick', 'zephyr',
  'atlas', 'bough', 'cradle', 'driftwood', 'emberlit', 'foghorn', 'glyph', 'hearth',
];

/** Combinatorial pool is large; suffix 1000–9999 keeps suggestions effectively endless. */
export function usernamePoolSize(): number {
  return ADJECTIVES.length * NOUNS.length * 9000;
}

const RESERVED = new Set(
  [
    'admin', 'administrator', 'mod', 'moderator', 'matterya', 'official',
    'support', 'help', 'staff', 'system', 'root', 'null', 'undefined',
    'anonymous', 'anon', 'everyone', 'here', 'channel', 'space', 'bot',
    'security', 'trust', 'safety', 'police', 'government', 'apple', 'google',
    'meta', 'facebook', 'instagram', 'tiktok', 'reddit', 'twitter', 'xai',
  ].map((s) => s.toLowerCase())
);

const DISALLOWED_SUBSTRINGS = [
  'nigger', 'faggot', 'retard', 'rape', 'pedophile', 'pedo', 'nazi',
  'hitler', 'kkk', 'slut', 'whore',
];

const USERNAME_RE = /^[a-z][a-z0-9_]{2,23}$/;

export function normalizeUsername(raw: string): string {
  return raw.normalize('NFKC').trim().toLowerCase();
}

export function validateSyntax(username: string): { ok: true } | { ok: false; code: string } {
  const n = normalizeUsername(username);
  if (!USERNAME_RE.test(n)) return { ok: false, code: 'invalid_syntax' };
  if (n.includes('__')) return { ok: false, code: 'invalid_syntax' };
  return { ok: true };
}

export function isReserved(username: string): boolean {
  const n = normalizeUsername(username);
  if (RESERVED.has(n)) return true;
  const base = n.replace(/_+\d+$/, '');
  return RESERVED.has(base);
}

export function isDisallowed(username: string): boolean {
  const n = normalizeUsername(username);
  return DISALLOWED_SUBSTRINGS.some((bad) => n.includes(bad));
}

/** Best-effort: reject handles that closely match ordinary display/username tokens. */
export function looksLikeRealName(
  candidate: string,
  profile?: { display_name?: string | null; username?: string | null } | null
): boolean {
  const n = normalizeUsername(candidate).replace(/_+\d+$/, '').replace(/_/g, '');
  if (!n || n.length < 3) return false;

  const tokens = new Set<string>();
  for (const field of [profile?.display_name, profile?.username]) {
    if (!field) continue;
    const cleaned = field
      .normalize('NFKC')
      .toLowerCase()
      .replace(/[^a-z0-9\s_-]/g, ' ');
    for (const part of cleaned.split(/[\s_-]+/)) {
      if (part.length >= 3) tokens.add(part);
    }
    const joined = cleaned.replace(/[\s_-]+/g, '');
    if (joined.length >= 4) tokens.add(joined);
  }

  for (const t of tokens) {
    if (n === t || n.includes(t) || t.includes(n)) return true;
  }

  // Crude "FirstLast" / "firstname_lastname" patterns without digits suffix stripped already
  if (/^[a-z]{2,}[a-z]{2,}$/.test(n) && !n.includes('_') && ADJECTIVES.every((a) => !n.startsWith(a))) {
    // allow dictionary compounds; only flag if both halves look like common name lengths and not in vocab
    // Keep conservative: do not blanket-reject.
  }
  return false;
}

export function generateSafeUsername(): string {
  const adj = ADJECTIVES[randomInt(ADJECTIVES.length)]!;
  const noun = NOUNS[randomInt(NOUNS.length)]!;
  const suffix = String(randomInt(1000, 10000));
  return `${adj}_${noun}_${suffix}`;
}

export function validateGeneratedCandidate(
  candidate: string,
  profile?: { display_name?: string | null; username?: string | null } | null
): { ok: true; normalized: string } | { ok: false; code: string } {
  const normalized = normalizeUsername(candidate);
  const syntax = validateSyntax(normalized);
  if (!syntax.ok) return syntax;
  if (isReserved(normalized)) return { ok: false, code: 'reserved' };
  if (isDisallowed(normalized)) return { ok: false, code: 'disallowed' };
  if (looksLikeRealName(normalized, profile)) return { ok: false, code: 'real_name_heuristic' };
  return { ok: true, normalized };
}
