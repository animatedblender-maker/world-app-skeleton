/**
 * Safe click / media URL normalization for ads.
 * Rejects non-http(s), credentials-in-URL, and oversized strings.
 */

const MAX_URL_LENGTH = 2048;

/** Hosts that must never be used as Learn more / click destinations. */
const BLOCKED_CLICK_HOSTS = new Set([
  'localhost',
  '127.0.0.1',
  '0.0.0.0',
  '::1',
  'metadata.google.internal',
]);

function isBlockedHost(hostname: string): boolean {
  const host = hostname.trim().toLowerCase().replace(/\.$/, '');
  if (!host) return true;
  if (BLOCKED_CLICK_HOSTS.has(host)) return true;
  if (host.endsWith('.localhost')) return true;
  // Link-local / private IPv4 — ads should not deep-link into LAN.
  if (/^(10\.|192\.168\.|169\.254\.)/.test(host)) return true;
  if (/^172\.(1[6-9]|2\d|3[0-1])\./.test(host)) return true;
  return false;
}

/**
 * `matterya.com` → `https://matterya.com` so mobile open() works.
 * Returns null for empty or unsafe values (non-http(s), credentials, blocked hosts).
 */
export function normalizeClickUrl(raw: string | null): string | null {
  const value = String(raw ?? '').trim();
  if (!value) return null;
  if (value.length > MAX_URL_LENGTH) return null;

  // Explicitly reject dangerous schemes before prefixing https.
  if (/^(javascript|data|file|vbscript|blob|about|intent|app):/i.test(value)) {
    return null;
  }

  let candidate = value;
  if (/^\/\//.test(candidate)) {
    candidate = `https:${candidate}`;
  } else if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(candidate)) {
    candidate = `https://${candidate}`;
  }

  let url: URL;
  try {
    url = new URL(candidate);
  } catch {
    return null;
  }

  const scheme = url.protocol.toLowerCase();
  if (scheme !== 'http:' && scheme !== 'https:') {
    return null;
  }
  if (url.username || url.password) {
    return null;
  }
  if (isBlockedHost(url.hostname)) {
    return null;
  }

  return url.toString();
}

/** Media creatives must be direct http(s) file URLs. */
export function normalizeMediaUrl(raw: string | null): string | null {
  const value = String(raw ?? '').trim();
  if (!value || value.length > MAX_URL_LENGTH) return null;
  if (/^(javascript|data|file|vbscript|blob|about):/i.test(value)) {
    return null;
  }
  let candidate = value;
  if (!/^https?:\/\//i.test(candidate)) {
    if (/^\/\//.test(candidate)) candidate = `https:${candidate}`;
    else return null;
  }
  try {
    const url = new URL(candidate);
    if (url.protocol !== 'http:' && url.protocol !== 'https:') return null;
    if (url.username || url.password) return null;
    return url.toString();
  } catch {
    return null;
  }
}

export function normalizeCountryCode(code: string | null): string | null {
  const raw = String(code ?? '').trim().toUpperCase();
  if (!raw) return null;
  if (/^[A-Z]{2}$/.test(raw)) return raw;
  const aliases: Record<string, string> = {
    GERMANY: 'DE',
    DEUTSCHLAND: 'DE',
    'UNITED STATES': 'US',
    USA: 'US',
    AMERICA: 'US',
    EGYPT: 'EG',
    ALBANIA: 'AL',
    FRANCE: 'FR',
    'UNITED KINGDOM': 'GB',
    UK: 'GB',
    ENGLAND: 'GB',
    AUSTRIA: 'AT',
    SWITZERLAND: 'CH',
    NETHERLANDS: 'NL',
    SPAIN: 'ES',
    ITALY: 'IT',
    CANADA: 'CA',
    AUSTRALIA: 'AU',
    KOSOVO: 'XK',
  };
  return aliases[raw] ?? (raw.length <= 3 ? raw : null);
}

export function normalizeCountryCodeArray(values: Array<string | null> | null): string[] {
  const unique = new Set<string>();
  for (const value of values ?? []) {
    const code = normalizeCountryCode(value);
    if (code) unique.add(code);
  }
  return [...unique];
}
