/** `matterya.com` → `https://matterya.com` so mobile open() works. */
export function normalizeClickUrl(raw: string | null): string | null {
  const value = String(raw ?? '').trim();
  if (!value) return null;
  if (/^https?:\/\//i.test(value)) return value;
  if (/^\/\//.test(value)) return `https:${value}`;
  return `https://${value}`;
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
