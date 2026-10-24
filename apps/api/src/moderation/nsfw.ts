import { pool } from '../db.js';

/**
 * Simple keyword auto-mod (18+) until a real moderation stack ships.
 * Whole-word matches only — keep the list short and obvious.
 */
export const ADULT_KEYWORDS = [
  'nsfw',
  'sex',
  'sexy',
  'sexual',
  'porn',
  'porno',
  'pornography',
  'xxx',
  'onlyfans',
  'hentai',
  'erotic',
  'nude',
  'nudes',
  'naked',
  'blowjob',
  'handjob',
  'cumshot',
  'orgasm',
  'masturbate',
  'masturbation',
  'masturbating',
  'gooning',
  'milf',
  'incest',
] as const;

const ADULT_KEYWORD_RE = new RegExp(
  `\\b(?:${ADULT_KEYWORDS.map((k) => k.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')).join('|')})\\b`,
  'i'
);

/** Word-boundary adult / NSFW markers in title/body/caption text. */
export function textLooksNsfw(...parts: Array<string | null | undefined>): boolean {
  const hay = parts.filter((p) => p != null && String(p).trim() !== '').join('\n');
  if (!hay) return false;
  return ADULT_KEYWORD_RE.test(hay);
}

/** Serving status for adult-keyword posts (18+). */
export function moderationStatusForText(
  ...parts: Array<string | null | undefined>
): 'active' | 'sensitive' {
  return textLooksNsfw(...parts) ? 'sensitive' : 'active';
}

/** Replace competitor brand tokens in user-facing copy (same policy as iOS ContentSanitizer). */
export function rebrandCompetitorNames(value: string | null | undefined): string | null {
  if (value == null) return null;
  let out = String(value);
  // Longer tokens first so "subreddit" → "matterya", "تيك توك" / "tik tok" → "matterya".
  for (const token of [
    'تيك توك',
    'تيك\u200cتوك',
    'تيك-توك',
    'تيكتوك',
    'tik tok',
    'subreddit',
    'reddit',
    'tiktok',
  ]) {
    if (!out.toLowerCase().includes(token.toLowerCase()) && !out.includes(token)) continue;
    const escaped = token.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    out = out.replace(new RegExp(escaped, 'gi'), 'matterya');
  }
  // Reddit shorthand " sub " (spaces required) → Masquerade " space ".
  out = out
    .replace(/ SUB /g, ' SPACE ')
    .replace(/ Sub /g, ' Space ')
    .replace(/ sub /g, ' space ');
  return out;
}

/**
 * True when the viewer’s birthdate makes them under 18.
 * Missing birthdate → false (do not treat unknown age as a minor).
 */
export async function viewerIsUnder18(userId: string | null | undefined): Promise<boolean> {
  if (!userId) return false;
  try {
    const { rows } = await pool.query<{ birthdate: Date | string | null }>(
      `select birthdate from public.profiles where user_id = $1::uuid limit 1`,
      [userId]
    );
    const raw = rows[0]?.birthdate;
    if (raw == null) return false;
    const iso =
      raw instanceof Date
        ? raw.toISOString().slice(0, 10)
        : String(raw).trim().slice(0, 10);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) return false;
    const birth = new Date(`${iso}T00:00:00.000Z`);
    if (Number.isNaN(birth.getTime())) return false;
    const now = new Date();
    let age = now.getUTCFullYear() - birth.getUTCFullYear();
    const m = now.getUTCMonth() - birth.getUTCMonth();
    if (m < 0 || (m === 0 && now.getUTCDate() < birth.getUTCDate())) age -= 1;
    return age < 18;
  } catch {
    return false;
  }
}

/**
 * SQL fragment: NSFW (`sensitive`) never serves on public Feed / Sparks / Hubs.
 * Those packs route to Masquerade `secrets` at ingest. `under18` kept for call-site compat.
 */
export function adultContentSqlFilter(_under18: boolean, alias = 'p'): string {
  return ` and coalesce(${alias}.moderation_status, 'active') <> 'sensitive'`;
}
