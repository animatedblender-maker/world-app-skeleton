/** Same competitor rebrand as iOS ContentSanitizer — longer tokens first. */
export function rebrandCompetitorNames(value: string | null | undefined): string {
  if (value == null) return '';
  let out = String(value);
  // Longer first: Arabic TikTok spellings + "tik tok" + Latin brands.
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

/** Same simple 18+ keyword gate as API moderation/nsfw.ts (whole words). */
const ADULT_KEYWORD_RE =
  /\b(?:nsfw|sex|sexy|sexual|porn|porno|pornography|xxx|onlyfans|hentai|erotic|nude|nudes|naked|blowjob|handjob|cumshot|orgasm|masturbate|masturbation|masturbating|gooning|milf|incest)\b/i;

export function textLooksNsfw(value: string | null | undefined): boolean {
  if (!value) return false;
  return ADULT_KEYWORD_RE.test(String(value));
}

export function isAdultPost(post: {
  title?: string | null;
  body?: string | null;
  media_caption?: string | null;
  is_adult?: boolean | null;
  moderation_status?: string | null;
}): boolean {
  if (post.is_adult === true) return true;
  if (String(post.moderation_status || '').toLowerCase() === 'sensitive') return true;
  return (
    textLooksNsfw(post.title) || textLooksNsfw(post.body) || textLooksNsfw(post.media_caption)
  );
}

/** Escape HTML entities so user text is safe before injecting markup. */
export function escapeHtml(value: string | null | undefined): string {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Render lightweight inline markup:
 * - line-leading `# heading` → `<strong class="md-h">` (marker removed)
 * - `**bold**` → `<strong>`
 * - `*italic*` → `<em>`
 * Escapes HTML first. Composer rich-text controls can come later.
 */
export function formatInlineBold(value: string | null | undefined): string {
  let out = escapeHtml(value);
  // `# Title` at start of a line → header (bold, larger via CSS).
  out = out.replace(/(^|\n)[ \t]*#[ \t]+([^\n]+)/g, '$1<strong class="md-h">$2</strong>');
  if (out.includes('**')) {
    out = out.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  }
  if (out.includes('*')) {
    out = out.replace(/\*([^*]+)\*/g, '<em>$1</em>');
  }
  return out;
}

/** Strip `#` / `**…**` / `*…*` markers for previews / plain display. */
export function stripInlineBold(value: string | null | undefined): string {
  return String(value ?? '')
    .replace(/(^|\n)[ \t]*#[ \t]+([^\n]+)/g, '$1$2')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/\*([^*]+)\*/g, '$1');
}
