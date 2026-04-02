type ReliefWebFetchOptions = {
  limit?: number;
  offset?: number;
};

export type ReliefWebNormalizedReport = {
  provider_item_id: string;
  title: string;
  url: string;
  source_name: string | null;
  published_at: string | null;
  country_codes: string[];
  country_names: string[];
  disaster_types: string[];
  theme_names: string[];
  format: string | null;
  language: string | null;
  snippet: string | null;
  image_url: string | null;
  raw: any;
};

export class ReliefWebClient {
  private readonly baseUrl = 'https://api.reliefweb.int/v2/reports';
  private readonly appName = String(process.env.RELIEFWEB_APPNAME ?? '').trim();
  private readonly requestTimeoutMs = Number(process.env.RELIEFWEB_TIMEOUT_MS ?? 10000);

  async fetchLatestReports(options?: ReliefWebFetchOptions): Promise<ReliefWebNormalizedReport[]> {
    if (!this.appName) {
      throw new Error(
        'RELIEFWEB_APPNAME is not configured. ReliefWeb requires an approved appname as of November 1, 2025.'
      );
    }

    const limit = Math.max(1, Math.min(100, Number(options?.limit ?? 60)));
    const offset = Math.max(0, Number(options?.offset ?? 0));
    const url = new URL(this.baseUrl);
    url.searchParams.set('appname', this.appName);

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), this.requestTimeoutMs);

    try {
      const res = await fetch(url.toString(), {
        method: 'POST',
        headers: {
          'content-type': 'application/json',
          accept: 'application/json',
        },
        body: JSON.stringify({
          preset: 'latest',
          limit,
          offset,
          sort: ['date.created:desc'],
        }),
        signal: controller.signal,
      });

      const text = await res.text();
      const json = text ? JSON.parse(text) : null;

      if (!res.ok) {
        const message = String(json?.error?.message ?? text ?? `HTTP ${res.status}`).trim();
        throw new Error(`ReliefWeb API error: ${message}`);
      }

      const rows = Array.isArray(json?.data) ? json.data : [];
      return rows
        .map((entry: any) => this.normalizeReport(entry))
        .filter((entry: ReliefWebNormalizedReport | null): entry is ReliefWebNormalizedReport => !!entry);
    } finally {
      clearTimeout(timeoutId);
    }
  }

  private normalizeReport(entry: any): ReliefWebNormalizedReport | null {
    const fields = entry?.fields ?? {};
    const providerItemId = String(entry?.id ?? '').trim();
    const title = String(fields?.title ?? '').trim();
    if (!providerItemId || !title) return null;

    const countries = this.toArray(fields?.country);
    const sources = this.toArray(fields?.source);
    const themes = this.toArray(fields?.theme);
    const disasters = this.toArray(fields?.disaster_type ?? fields?.disaster);
    const formats = this.toArray(fields?.format);
    const languages = this.toArray(fields?.language);

    const countryCodes = countries
      .map((item) => this.normalizeCountryCode(item?.iso2 ?? item?.code ?? item?.shortname))
      .filter((value): value is string => !!value);

    const countryNames = countries
      .map((item) => String(item?.name ?? item?.shortname ?? '').trim())
      .filter(Boolean);

    const disasterTypes = disasters
      .map((item) => String(item?.name ?? item?.shortname ?? '').trim())
      .filter(Boolean);

    const themeNames = themes
      .map((item) => String(item?.name ?? item?.shortname ?? '').trim())
      .filter(Boolean);

    const sourceName =
      sources
        .map((item) => String(item?.shortname ?? item?.name ?? '').trim())
        .find(Boolean) ?? null;

    const publishedAt =
      this.normalizeIsoDate(fields?.date?.created) ??
      this.normalizeIsoDate(fields?.date?.original) ??
      this.normalizeIsoDate(fields?.date?.changed);

    const format =
      formats
        .map((item) => String(item?.name ?? item?.shortname ?? '').trim())
        .find(Boolean) ?? null;

    const language =
      languages
        .map((item) => String(item?.name ?? item?.code ?? '').trim())
        .find(Boolean) ?? null;

    const headlineSummary = String(fields?.headline?.summary ?? '').trim();
    const body = String(fields?.body ?? '').replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
    const snippet = this.compactSnippet(headlineSummary || body);

    const imageUrl =
      this.toArray(fields?.file)
        .map((item) => String(item?.url ?? item?.preview?.url ?? item?.thumbnail?.url ?? '').trim())
        .find(Boolean) ?? null;

    const canonicalUrl =
      String(fields?.url ?? '').trim() || `https://reliefweb.int/report/${providerItemId}`;

    return {
      provider_item_id: providerItemId,
      title,
      url: canonicalUrl,
      source_name: sourceName,
      published_at: publishedAt,
      country_codes: Array.from(new Set(countryCodes)),
      country_names: Array.from(new Set(countryNames)),
      disaster_types: Array.from(new Set(disasterTypes)),
      theme_names: Array.from(new Set(themeNames)),
      format,
      language,
      snippet,
      image_url: imageUrl,
      raw: entry,
    };
  }

  private toArray(value: any): any[] {
    return Array.isArray(value) ? value : [];
  }

  private normalizeCountryCode(value: any): string | null {
    const raw = String(value ?? '').trim().toUpperCase();
    return /^[A-Z]{2}$/.test(raw) ? raw : null;
  }

  private normalizeIsoDate(value: any): string | null {
    const raw = String(value ?? '').trim();
    if (!raw) return null;
    const date = new Date(raw);
    return Number.isNaN(date.getTime()) ? null : date.toISOString();
  }

  private compactSnippet(value: string): string | null {
    const normalized = String(value ?? '').replace(/\s+/g, ' ').trim();
    if (!normalized) return null;
    return normalized.length > 240 ? `${normalized.slice(0, 237).trimEnd()}...` : normalized;
  }
}
