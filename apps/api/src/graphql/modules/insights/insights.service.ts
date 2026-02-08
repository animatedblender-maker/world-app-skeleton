import { pool } from '../../../db.js';
import { GraphQLError } from 'graphql';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

type MoodCounts = {
  positive: number;
  neutral: number;
  negative: number;
  total: number;
};

export type CountryMood = MoodCounts & {
  country_code: string;
  topics: string[];
  insight: string;
  computed_at: string;
};

type SentimentLabel = 'positive' | 'neutral' | 'negative';

const CACHE_TTL_MS = 5 * 60 * 1000;
const MAX_TEXTS = 220;
const MAX_TEXT_LEN = 420;

const cache = new Map<string, { at: number; value: CountryMood }>();
let cachedCountryCodes: string[] | null = null;

let sentimentPipeline: any | null = null;
let pipelineInitPromise: Promise<any> | null = null;

async function getSentimentPipeline() {
  if (sentimentPipeline) return sentimentPipeline;
  if (!pipelineInitPromise) {
    pipelineInitPromise = (async () => {
      const { pipeline, env } = await import('@xenova/transformers');
      const hfToken = process.env.HF_ACCESS_TOKEN || process.env.HUGGINGFACE_TOKEN || '';
      if (hfToken) {
        (env as any).HF_ACCESS_TOKEN = hfToken;
      }
      return pipeline('sentiment-analysis', 'Xenova/twitter-xlm-roberta-base-sentiment');
    })();
  }
  sentimentPipeline = await pipelineInitPromise;
  return sentimentPipeline;
}

function clampText(value: string): string {
  if (!value) return '';
  return value.length > MAX_TEXT_LEN ? value.slice(0, MAX_TEXT_LEN) : value;
}

function normalizeText(value: string): string {
  return value
    .toLowerCase()
    .replace(/https?:\/\/\S+/g, ' ')
    .replace(/[@#]\S+/g, ' ')
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

const STOPWORDS = new Set(
  [
    'the',
    'and',
    'you',
    'your',
    'for',
    'with',
    'from',
    'this',
    'that',
    'there',
    'here',
    'what',
    'when',
    'where',
    'about',
    'into',
    'then',
    'than',
    'been',
    'have',
    'has',
    'had',
    'are',
    'was',
    'were',
    'will',
    'would',
    'could',
    'should',
    'just',
    'like',
    'love',
    'not',
    'but',
    'can',
    'cant',
    'dont',
    'its',
    'im',
    'we',
    'they',
    'them',
    'our',
    'their',
    'his',
    'her',
    'him',
    'she',
    'he',
    'i',
    'a',
    'an',
    'to',
    'of',
    'in',
    'on',
    'at',
    'by',
    'as',
    'is',
    'it',
    'or',
    'be',
    'if',
    'my',
    'me',
    'us',
  ].map((x) => x.toLowerCase())
);

function extractTopics(texts: string[], limit = 8): string[] {
  const freq = new Map<string, number>();
  for (const text of texts) {
    const norm = normalizeText(text);
    if (!norm) continue;
    const parts = norm.split(' ');
    for (const word of parts) {
      if (word.length < 3) continue;
      if (STOPWORDS.has(word)) continue;
      freq.set(word, (freq.get(word) ?? 0) + 1);
    }
  }
  return [...freq.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, limit)
    .map(([word]) => word);
}

function formatTopic(word: string): string {
  if (!word) return word;
  return word.length > 1 ? word[0].toUpperCase() + word.slice(1) : word.toUpperCase();
}

function buildInsight(counts: MoodCounts, topics: string[]): string {
  if (!counts.total) {
    return 'Not enough recent posts to summarize yet.';
  }

  const posPct = counts.positive / counts.total;
  const negPct = counts.negative / counts.total;
  const delta = posPct - negPct;
  const mood =
    delta > 0.12 ? 'optimistic' :
    delta < -0.12 ? 'tense' :
    'mixed';

  const topTopics = topics.slice(0, 4).map(formatTopic);
  if (topTopics.length) {
    return `Overall mood feels ${mood}. Top themes: ${topTopics.join(', ')}.`;
  }
  return `Overall mood feels ${mood}, with a wide mix of conversations.`;
}

async function classifySentiment(texts: string[]): Promise<SentimentLabel[]> {
  if (!texts.length) return [];
  const batch = texts.map((t) => clampText(t));
  try {
    const pipe = await getSentimentPipeline();
    const results: Array<{ label: string }> = await pipe(batch);
    return results.map((res) => {
      const label = String(res.label ?? '').toLowerCase();
      if (label.includes('positive')) return 'positive';
      if (label.includes('negative')) return 'negative';
      return 'neutral';
    });
  } catch {
    return await classifySentimentRemote(batch);
  }
}

async function classifySentimentRemote(texts: string[]): Promise<SentimentLabel[]> {
  const token = process.env.HF_ACCESS_TOKEN || process.env.HUGGINGFACE_TOKEN || '';
  if (!token) {
    throw new GraphQLError('Sentiment failed: missing HF access token for remote inference.');
  }
  const baseUrl =
    process.env.HF_INFERENCE_URL ||
    'https://router.huggingface.co/hf-inference/models/cardiffnlp/twitter-xlm-roberta-base-sentiment';
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20000);
  try {
    const res = await fetch(
      baseUrl,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ inputs: texts }),
        signal: controller.signal,
      }
    );
    if (!res.ok) {
      const txt = await res.text().catch(() => '');
      if ([502, 503, 504].includes(res.status)) {
        return texts.map(() => 'neutral');
      }
      throw new GraphQLError(`Sentiment failed: ${res.status} ${txt}`);
    }
    const json: Array<Array<{ label: string; score: number }>> = await res.json();
    return json.map((choices) => {
      const best = [...(choices ?? [])].sort((a, b) => b.score - a.score)[0];
      const label = String(best?.label ?? '').toUpperCase();
      if (label === 'LABEL_2' || label.includes('POS')) return 'positive';
      if (label === 'LABEL_0' || label.includes('NEG')) return 'negative';
      return 'neutral';
    });
  } catch (err: any) {
    if (String(err?.name) === 'AbortError') {
      return texts.map(() => 'neutral');
    }
    throw err;
  } finally {
    clearTimeout(timeout);
  }
}

async function fetchTexts(countryCode?: string | null): Promise<string[]> {
  const params: any[] = [];
  let whereSql = '';
  if (countryCode) {
    params.push(countryCode);
    whereSql = `where p.country_code = $${params.length}`;
  }
  params.push(Math.floor(MAX_TEXTS * 0.6));
  const postLimitParam = params.length;
  const postsRes = await pool.query<{ title: string | null; body: string }>(
    `
    select p.title, p.body
    from public.posts p
    ${whereSql}
    order by p.created_at desc
    limit $${postLimitParam}
    `,
    params
  );

  const commentParams: any[] = [];
  let commentsWhere = '';
  if (countryCode) {
    commentParams.push(countryCode);
    commentsWhere = `where p.country_code = $${commentParams.length}`;
  }
  commentParams.push(Math.floor(MAX_TEXTS * 0.4));
  const commentLimitParam = commentParams.length;
  const commentsRes = await pool.query<{ body: string }>(
    `
    select c.body
    from public.post_comments c
    join public.posts p on p.id = c.post_id
    ${commentsWhere}
    order by c.created_at desc
    limit $${commentLimitParam}
    `,
    commentParams
  );

  const texts: string[] = [];
  for (const row of postsRes.rows) {
    const title = row.title ? String(row.title).trim() : '';
    const body = String(row.body ?? '').trim();
    const combined = `${title} ${body}`.trim();
    if (combined) texts.push(combined);
  }
  for (const row of commentsRes.rows) {
    const body = String(row.body ?? '').trim();
    if (body) texts.push(body);
  }
  return texts.slice(0, MAX_TEXTS);
}

async function loadCountryCodesFromGeoJson(): Promise<string[]> {
  if (cachedCountryCodes) return cachedCountryCodes;
  const here = path.dirname(fileURLToPath(import.meta.url));
  const candidates = [
    path.resolve(here, '../../data/countries50m.geojson'),
    path.resolve(here, '../data/countries50m.geojson'),
    path.resolve(process.cwd(), 'apps/api/src/graphql/data/countries50m.geojson'),
    path.resolve(process.cwd(), 'apps/api/dist/graphql/data/countries50m.geojson'),
  ];

  for (const candidate of candidates) {
    try {
      const raw = await readFile(candidate, 'utf8');
      const json = JSON.parse(raw) as {
        features?: Array<{ properties?: Record<string, any> }>;
      };
      const codes = new Set<string>();
      for (const feature of json.features ?? []) {
        const props = feature?.properties ?? {};
        const iso2 = String(props.ISO_A2 ?? props.ISO_A2_EH ?? '').trim().toUpperCase();
        if (iso2.length !== 2) continue;
        if (iso2 === '-9' || iso2 === '-99' || iso2 === 'ZZ') continue;
        codes.add(iso2);
      }
      cachedCountryCodes = [...codes].sort();
      return cachedCountryCodes;
    } catch {
      // try next candidate
    }
  }

  cachedCountryCodes = [];
  return cachedCountryCodes;
}

export async function getCountryMood(countryCode?: string | null): Promise<CountryMood> {
  const key = countryCode ? `cc:${countryCode.toUpperCase()}` : 'global';
  const cached = cache.get(key);
  if (cached && Date.now() - cached.at < CACHE_TTL_MS) return cached.value;

  const texts = await fetchTexts(countryCode ?? null);
  if (!texts.length) {
    const empty: CountryMood = {
      country_code: countryCode ? countryCode.toUpperCase() : 'GLOBAL',
      positive: 0,
      neutral: 0,
      negative: 0,
      total: 0,
      topics: [],
      insight: 'Not enough recent posts to summarize yet.',
      computed_at: new Date().toISOString(),
    };
    cache.set(key, { at: Date.now(), value: empty });
    return empty;
  }

  let labels: SentimentLabel[] = [];
  try {
    labels = await classifySentiment(texts);
  } catch (err: any) {
    throw new GraphQLError(`Sentiment failed: ${err?.message ?? 'unknown'}`);
  }

  const counts: MoodCounts = { positive: 0, neutral: 0, negative: 0, total: labels.length };
  for (const label of labels) {
    counts[label] += 1;
  }

  const topics = extractTopics(texts, 10);
  const insight = buildInsight(counts, topics);
  const mood: CountryMood = {
    country_code: countryCode ? countryCode.toUpperCase() : 'GLOBAL',
    ...counts,
    topics,
    insight,
    computed_at: new Date().toISOString(),
  };

  cache.set(key, { at: Date.now(), value: mood });
  return mood;
}

export async function runAllCountryMoods(): Promise<{ processed: number; failed: number }> {
  const codes = new Set<string>();

  try {
    const geoCodes = await loadCountryCodesFromGeoJson();
    for (const code of geoCodes) codes.add(code);
  } catch {
    // ignore geojson load errors
  }

  const { rows } = await pool.query<{ country_code: string | null }>(
    `
    select distinct country_code
    from public.posts
    where country_code is not null
    order by country_code asc
    `
  );
  for (const row of rows) {
    const code = String(row.country_code ?? '').trim().toUpperCase();
    if (code) codes.add(code);
  }

  let processed = 0;
  let failed = 0;

  for (const code of [...codes].sort()) {
    try {
      await getCountryMood(code);
      processed += 1;
    } catch {
      failed += 1;
    }
  }

  try {
    await getCountryMood(null);
  } catch {
    failed += 1;
  }

  return { processed, failed };
}
