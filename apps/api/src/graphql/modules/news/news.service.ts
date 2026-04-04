import { GraphQLError } from 'graphql';

export type ExternalNewsItem = {
  id: string;
  provider: string;
  provider_item_id: string;
  title: string;
  url: string;
  source_name?: string | null;
  published_at?: string | null;
  country_codes: string[];
  country_names: string[];
  disaster_types: string[];
  theme_names: string[];
  format?: string | null;
  language?: string | null;
  snippet?: string | null;
  image_url?: string | null;
  comment_count: number;
  shared_post_count: number;
};

type ReliefWebEntity = {
  id?: number | string;
  name?: string | null;
  shortname?: string | null;
  iso3?: string | null;
  code?: string | null;
};

type ReliefWebFields = {
  title?: string | null;
  body?: string | null;
  source?: ReliefWebEntity[] | null;
  country?: ReliefWebEntity[] | null;
  disaster_type?: ReliefWebEntity[] | null;
  theme?: ReliefWebEntity[] | null;
  format?: ReliefWebEntity[] | null;
  language?: ReliefWebEntity[] | null;
  date?: {
    original?: string | null;
    created?: string | null;
  } | null;
  file?: Array<{ url?: string | null }> | null;
};

type ReliefWebReport = {
  id?: number | string;
  href?: string | null;
  fields?: ReliefWebFields | null;
};

type ReliefWebResponse = {
  data?: ReliefWebReport[];
};

const RELIEFWEB_API_URL = process.env.RELIEFWEB_API_URL ?? 'https://api.reliefweb.int/v2/reports';
const RELIEFWEB_APPNAME = (process.env.RELIEFWEB_APPNAME ?? '').trim();
const RELIEFWEB_TIMEOUT_MS = Number(process.env.RELIEFWEB_TIMEOUT_MS ?? 8000);
const RELIEFWEB_USER_AGENT =
  process.env.RELIEFWEB_USER_AGENT ??
  `Matterya/1.0 (${RELIEFWEB_APPNAME || 'reliefweb-client'})`;

function ensureReliefWebConfigured(): void {
  if (!RELIEFWEB_APPNAME) {
    throw new GraphQLError('provider access is not configured: missing RELIEFWEB_APPNAME', {
      extensions: { code: 'SERVICE_NOT_CONFIGURED' },
    });
  }
}

function iso2ToCountryName(countryCode: string): string | null {
  const code = String(countryCode ?? '').trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(code)) return null;
  try {
    const display = new Intl.DisplayNames(['en'], { type: 'region' });
    return display.of(code) ?? null;
  } catch {
    return null;
  }
}

function plainTextSnippet(raw: string | null | undefined, max = 220): string | null {
  const text = String(raw ?? '')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
  if (!text) return null;
  if (text.length <= max) return text;
  return `${text.slice(0, max - 1).trim()}…`;
}

function entityNames(items: ReliefWebEntity[] | null | undefined): string[] {
  return (items ?? [])
    .map((item) => String(item?.name ?? item?.shortname ?? '').trim())
    .filter(Boolean);
}

function entityCodes(items: ReliefWebEntity[] | null | undefined): string[] {
  return (items ?? [])
    .map((item) => String(item?.iso3 ?? item?.code ?? '').trim().toUpperCase())
    .filter(Boolean);
}

function mapReport(report: ReliefWebReport): ExternalNewsItem {
  const fields = report.fields ?? {};
  const id = String(report.id ?? '');
  const href = String(report.href ?? '').trim();
  const title = String(fields.title ?? 'Untitled ReliefWeb report').trim();
  const source = fields.source?.[0];
  const format = fields.format?.[0];
  const language = fields.language?.[0];

  return {
    id,
    provider: 'reliefweb',
    provider_item_id: id,
    title,
    url: href || `https://reliefweb.int/node/${id}`,
    source_name: source?.shortname || source?.name || 'ReliefWeb',
    published_at: fields.date?.original || fields.date?.created || null,
    country_codes: entityCodes(fields.country),
    country_names: entityNames(fields.country),
    disaster_types: entityNames(fields.disaster_type),
    theme_names: entityNames(fields.theme),
    format: format?.name ?? null,
    language: language?.code || language?.name || null,
    snippet: plainTextSnippet(fields.body),
    image_url: fields.file?.[0]?.url ?? null,
    comment_count: 0,
    shared_post_count: 0,
  };
}

async function fetchReliefWebReports(limit: number, offset: number, countryName?: string | null): Promise<ExternalNewsItem[]> {
  ensureReliefWebConfigured();

  const payload: Record<string, unknown> = {
    limit: Math.max(1, Math.min(limit || 10, 20)),
    offset: Math.max(0, offset || 0),
    sort: ['date.original:desc'],
    fields: {
      include: [
        'title',
        'body',
        'source',
        'country',
        'disaster_type',
        'theme',
        'format',
        'language',
        'date.original',
        'date.created',
        'file.url',
      ],
    },
  };

  if (countryName) {
    payload['filter'] = {
      field: 'country',
      value: [countryName],
      operator: 'OR',
    };
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), RELIEFWEB_TIMEOUT_MS);

  try {
    const response = await fetch(`${RELIEFWEB_API_URL}?appname=${encodeURIComponent(RELIEFWEB_APPNAME)}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'User-Agent': RELIEFWEB_USER_AGENT,
      },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new GraphQLError(
        `ReliefWeb request failed (${response.status}). ${body || 'Please verify RELIEFWEB_APPNAME on Render.'}`.trim(),
        { extensions: { code: 'UPSTREAM_REQUEST_FAILED' } }
      );
    }

    const json = (await response.json()) as ReliefWebResponse;
    return (json.data ?? []).map(mapReport);
  } catch (error: any) {
    if (error instanceof GraphQLError) throw error;
    if (error?.name === 'AbortError') {
      throw new GraphQLError('ReliefWeb request timed out.', {
        extensions: { code: 'UPSTREAM_TIMEOUT' },
      });
    }
    throw new GraphQLError(error?.message ?? 'Failed to load ReliefWeb updates.', {
      extensions: { code: 'UPSTREAM_REQUEST_FAILED' },
    });
  } finally {
    clearTimeout(timeout);
  }
}

export class NewsService {
  async countryConflictUpdates(countryCode: string, limit = 10, offset = 0): Promise<ExternalNewsItem[]> {
    const countryName = iso2ToCountryName(countryCode);
    if (!countryName) return [];
    return await fetchReliefWebReports(limit, offset, countryName);
  }

  async globalConflictUpdates(limit = 10, offset = 0): Promise<ExternalNewsItem[]> {
    return await fetchReliefWebReports(limit, offset);
  }
}
