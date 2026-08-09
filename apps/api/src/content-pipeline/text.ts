/** Sanitize captions — never surface source platform names. Prefer real R2 meta text. */

/** Old seeder fluff that must never be shown as a caption (was used on spark shares). */
export const FAKE_SHARE_CAPTIONS = new Set([
  '',
  'this one 🔥',
  'need this on loop',
  'sending this to everyone',
  'no notes',
  'how is this real',
  'ok wait',
  'the audio though',
  "I'm obsessed",
  'more of this please',
  'mood',
  'saw this and had to share',
  'too good',
  'watch till the end',
  '😂😂😂',
  '//',
]);

export function cleanText(value: unknown, maxLen: number): string {
  if (value == null) return '';
  let text = String(value).replace(/\x00/g, ' ').trim();
  // Keep newlines as spaces for single-line captions; collapse runs of space.
  text = text.replace(/\s+/g, ' ');
  text = text.replace(/tiktok/gi, 'matterya');
  if (text.length > maxLen) text = `${text.slice(0, maxLen - 1).trimEnd()}…`;
  return text;
}

/**
 * Strip internal control markers from a post body and return the human caption.
 * Handles same-line forms: `__spark__|real caption here`
 */
export function stripBodyMarkers(body: string | null | undefined): string {
  if (!body) return '';
  const lines: string[] = [];
  for (const rawLine of body.split(/\r?\n/)) {
    let line = rawLine.trim();
    if (!line) continue;
    // Peel known markers; keep any text after `|` on the same line.
    const markers = [
      '__spark_share__|',
      '__spark__|',
      '__reel__|',
      '__hub_channel__|',
      '__hub_origin__|',
      '__story__|',
    ];
    let peeled = false;
    for (const m of markers) {
      if (line.startsWith(m)) {
        line = line.slice(m.length).trim();
        // share header may be `sid=…|aid=…` with no caption on that line
        if (m === '__spark_share__|' && (/^sid=/i.test(line) || !line)) {
          line = '';
        }
        peeled = true;
        break;
      }
    }
    if (!line) continue;
    if (!peeled && line.startsWith('__') && line.includes('|')) continue;
    lines.push(line);
  }
  const text = lines.join(' ').replace(/\s+/g, ' ').trim();
  if (FAKE_SHARE_CAPTIONS.has(text)) return '';
  return text;
}

export function isFakeShareCaption(text: string | null | undefined): boolean {
  if (text == null) return true;
  const t = text.trim();
  if (!t) return true;
  if (FAKE_SHARE_CAPTIONS.has(t)) return true;
  return false;
}

/**
 * Real caption from R2 meta.json (not seeder fluff / not “Spark ab12cd”).
 * Meta packs store the original text in `title` / `desc` (and sometimes nested fields).
 */
export function pickCaption(meta: Record<string, unknown>, kind: string, videoId: string): string {
  const candidates: unknown[] = [
    meta.title,
    meta.desc,
    meta.description,
    meta.caption,
    meta.text,
    meta.music_title,
    // Nested shapes some exporters use
    (meta as { video?: { desc?: string } }).video?.desc,
    (meta as { video?: { title?: string } }).video?.title,
    (meta as { content?: { desc?: string } }).content?.desc,
    (meta as { item?: { desc?: string } }).item?.desc,
    (meta as { aweme_detail?: { desc?: string } }).aweme_detail?.desc,
  ];

  for (const raw of candidates) {
    const t = cleanText(raw, 4000);
    if (!t) continue;
    // Skip useless placeholders
    if (/^spark\s+[a-z0-9]{4,}$/i.test(t)) continue;
    if (/^video\s+[a-z0-9]{4,}$/i.test(t)) continue;
    if (t === 'Clip' || t === 'clip') continue;
    if (isFakeShareCaption(t)) continue;
    return t;
  }

  // Last resort — short id, not a fake social caption
  if (kind === 'spark' || kind === 'shortform') return `Spark ${String(videoId).slice(-8)}`;
  return `Video ${String(videoId).slice(-8)}`;
}

/** @deprecated use pickCaption — kept for call-site clarity */
export function pickTitle(meta: Record<string, unknown>, kind: string, videoId: string): string {
  return pickCaption(meta, kind, videoId);
}

export function pickBody(kind: string, caption: string, meta: Record<string, unknown>): string {
  const t = cleanText(caption, 3980) || 'Clip';
  // TikTok Sparks + YouTube ShortForm both use the Sparks player (`__spark__|` marker).
  if (kind === 'spark' || kind === 'shortform') {
    return `__spark__|${t}`;
  }
  const channel = cleanText(meta.channel ?? meta.author_name, 80);
  if (channel) return cleanText(`${t}\n\n— ${channel}`, 4000);
  return t;
}

export function markShareBody(originId: string, caption: string): string {
  const sid = originId.replace(/\|/g, '');
  const header = `__spark_share__|sid=${sid}`;
  const cap = cleanText(caption, 2800);
  // Always attach original caption when we have it — never invent “this one 🔥”.
  if (!cap || isFakeShareCaption(cap)) return header;
  return `${header}\n${cap}`;
}

/**
 * Full comments.json from R2 — **no artificial cap**.
 * Some packs have 50–300+ comments; they all belong in post_comments.
 */
export function extractCommentTexts(raw: unknown): string[] {
  let items: unknown[] = [];
  if (Array.isArray(raw)) items = raw;
  else if (raw && typeof raw === 'object') {
    const o = raw as Record<string, unknown>;
    for (const k of ['comments', 'data', 'items', 'results', 'comment_list']) {
      if (Array.isArray(o[k])) {
        items = o[k] as unknown[];
        break;
      }
    }
  }
  // Prefer higher-engagement comments first when order is messy.
  const scored: Array<{ text: string; likes: number }> = [];
  for (const item of items) {
    if (typeof item === 'string') {
      const text = cleanText(item, 5000);
      if (text) scored.push({ text, likes: 0 });
      continue;
    }
    if (!item || typeof item !== 'object') continue;
    const c = item as Record<string, unknown>;
    const text = cleanText(c.text ?? c.body ?? c.content ?? c.comment, 5000);
    if (!text) continue;
    const likes = Number(c.digg_count ?? c.like_count ?? c.likes ?? 0) || 0;
    scored.push({ text, likes });
  }
  scored.sort((a, b) => b.likes - a.likes);
  // De-dupe identical text while keeping order.
  const seen = new Set<string>();
  const out: string[] = [];
  for (const row of scored) {
    const key = row.text.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(row.text);
  }
  return out;
}
