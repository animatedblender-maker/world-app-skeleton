/** Sanitize captions — never surface source platform names. */

export function cleanText(value: unknown, maxLen: number): string {
  if (value == null) return '';
  let text = String(value).replace(/\x00/g, ' ').trim();
  text = text.replace(/\s+/g, ' ');
  text = text.replace(/tiktok/gi, 'matterya');
  if (text.length > maxLen) text = `${text.slice(0, maxLen - 1).trimEnd()}…`;
  return text;
}

export function pickTitle(meta: Record<string, unknown>, kind: string, videoId: string): string {
  for (const key of ['title', 'desc', 'description', 'music_title']) {
    const t = cleanText(meta[key], 200);
    if (t) return t;
  }
  if (kind === 'spark') return `Spark ${videoId.slice(-6)}`;
  return `Video ${videoId}`;
}

export function pickBody(kind: string, title: string, meta: Record<string, unknown>): string {
  const t = cleanText(title, 3980) || 'Clip';
  if (kind === 'spark') return `__spark__|${t}`;
  const channel = cleanText(meta.channel ?? meta.author_name, 80);
  if (channel) return cleanText(`${t}\n\n— ${channel}`, 4000);
  return t;
}

export function markShareBody(originId: string, caption: string): string {
  const sid = originId.replace(/\|/g, '');
  const header = `__spark_share__|sid=${sid}`;
  const cap = (caption || '').trim();
  return cap ? `${header}\n${cap}` : header;
}

export function extractCommentTexts(raw: unknown): string[] {
  let items: unknown[] = [];
  if (Array.isArray(raw)) items = raw;
  else if (raw && typeof raw === 'object') {
    const o = raw as Record<string, unknown>;
    for (const k of ['comments', 'data', 'items', 'results']) {
      if (Array.isArray(o[k])) {
        items = o[k] as unknown[];
        break;
      }
    }
  }
  const out: string[] = [];
  for (const item of items) {
    if (!item || typeof item !== 'object') continue;
    const c = item as Record<string, unknown>;
    const text = cleanText(c.text ?? c.body ?? c.content ?? c.comment, 5000);
    if (text) out.push(text);
  }
  return out.slice(0, 80);
}
