import { pool } from '../../../db.js';
import { GraphQLError } from 'graphql';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { getAdminSettings } from '../../../admin/admin.service.js';

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

type SentimentScores = {
  positive: number;
  neutral: number;
  negative: number;
};

type PostTextRow = {
  text: string;
  created_at: string;
};

const DEFAULT_CACHE_TTL_MS = 5 * 60 * 1000;
const MAX_TEXTS = 180;
const MAX_TEXT_LEN = 1600;
const OLLAMA_PROMPT_TEXT_LIMIT = 12000;
const OLLAMA_TIMEOUT_MS = Number(process.env.OLLAMA_TIMEOUT_MS || 20000);

const cache = new Map<string, { at: number; value: CountryMood }>();
let cachedCountryCodes: string[] | null = null;

let sentimentPipeline: any | null = null;
let pipelineInitPromise: Promise<any> | null = null;
let cachedDemoPostsPromise: Promise<PostTextRow[]> | null = null;

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

function topicCoverage(texts: string[], topic: string): number {
  const normalizedTopic = normalizeText(topic);
  if (!normalizedTopic) return 0;
  let matches = 0;
  for (const text of texts) {
    const normalized = normalizeText(text);
    if (!normalized) continue;
    const words = new Set(normalized.split(' ').filter(Boolean));
    if (words.has(normalizedTopic)) matches += 1;
  }
  return matches;
}

function buildInsight(counts: MoodCounts, texts: string[], topics: string[]): string {
  if (!counts.total) {
    return 'Not enough recent posts to summarize yet.';
  }

  const posPct = counts.positive / counts.total;
  const negPct = counts.negative / counts.total;
  const delta = posPct - negPct;
  const mood =
    delta > 0.18 ? 'cautiously upbeat' :
    delta > 0.08 ? 'measured but hopeful' :
    delta < -0.18 ? 'tense and frustrated' :
    delta < -0.08 ? 'worried and unsettled' :
    'mixed and watchful';

  const leadTopics = topics
    .slice(0, 3)
    .map((topic) => ({
      topic,
      count: topicCoverage(texts, topic),
    }))
    .filter((entry) => entry.count > 0)
    .map((entry) => ({
      topic: formatTopic(entry.topic),
      pct: Math.max(1, Math.round((entry.count / Math.max(1, texts.length)) * 100)),
    }));

  const topicSummary = leadTopics.length
    ? leadTopics
        .map((entry) => `${entry.topic} (${entry.pct}%)`)
        .join(', ')
    : 'a broad mix of issues';

  if (counts.total < 8) {
    return `People in this feed are mostly discussing ${topicSummary}. The mood feels ${mood}, although this read is based on a relatively small sample of recent posts.`;
  }
  return `People in this feed are mainly discussing ${topicSummary}. Overall, the country conversation feels ${mood} across recent posts.`;
}

function sampleTextsForSummary(texts: string[]): string[] {
  if (texts.length <= 24) return texts;
  const head = texts.slice(0, 12);
  const midStart = Math.max(12, Math.floor(texts.length / 2) - 6);
  const middle = texts.slice(midStart, midStart + 6);
  const tail = texts.slice(-6);
  const seen = new Set<string>();
  return [...head, ...middle, ...tail].filter((text) => {
    const key = text.trim();
    if (!key || seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function buildSummaryPrompt(countryCode: string, counts: MoodCounts, texts: string[]): string {
  const sampled = sampleTextsForSummary(texts);
  let totalLen = 0;
  const clipped: string[] = [];
  for (const text of sampled) {
    const normalized = clampText(String(text ?? '').replace(/\s+/g, ' ').trim());
    if (!normalized) continue;
    if (totalLen + normalized.length > OLLAMA_PROMPT_TEXT_LIMIT) break;
    clipped.push(normalized);
    totalLen += normalized.length;
  }

  return [
    'You are writing a concise country desk brief based on social posts from a country feed.',
    'Use only the posts provided below.',
    'Read the full meaning of each post, not isolated keywords.',
    'Explain what people are actually discussing, what they seem hopeful, worried, angry, or relieved about, and why.',
    'Estimate rough discussion share percentages by theme based on the posts.',
    'Do not invent topics that are not in the posts.',
    'Do not mention AI, models, sentiment classifiers, or that this is generated.',
    'Write like a human spokesperson or analyst summarizing the public conversation in this country.',
    'Return one compact paragraph in plain English, 70 to 130 words.',
    `Country context: ${countryCode}.`,
    `Recent post count: ${counts.total}.`,
    `Mood distribution hint: positive ${Math.round((counts.positive / Math.max(1, counts.total)) * 100)}%, neutral ${Math.round((counts.neutral / Math.max(1, counts.total)) * 100)}%, negative ${Math.round((counts.negative / Math.max(1, counts.total)) * 100)}%.`,
    'Posts:',
    ...clipped.map((text, index) => `${index + 1}. ${text}`),
  ].join('\n');
}

function ollamaDebugEnabled(): boolean {
  const value = String(process.env.OLLAMA_DEBUG || '').trim().toLowerCase();
  return value === '1' || value === 'true' || value === 'yes' || value === 'on';
}

async function generateInsightWithOllama(
  countryCode: string,
  counts: MoodCounts,
  texts: string[]
): Promise<string | null> {
  const baseUrl = String(process.env.OLLAMA_BASE_URL || '').trim().replace(/\/+$/, '');
  const model = String(process.env.OLLAMA_MODEL || '').trim();
  if (!baseUrl || !model) return null;

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  const apiKey = String(process.env.OLLAMA_API_KEY || '').trim();
  if (apiKey) headers.Authorization = `Bearer ${apiKey}`;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), OLLAMA_TIMEOUT_MS);
  try {
    const prompt = buildSummaryPrompt(countryCode, counts, texts);
    if (ollamaDebugEnabled()) {
      console.log('[ollama-debug] request', {
        countryCode,
        totalTexts: texts.length,
        previewTexts: texts.slice(0, 12),
        prompt,
      });
    }
    const res = await fetch(`${baseUrl}/chat`, {
      method: 'POST',
      headers,
      signal: controller.signal,
      body: JSON.stringify({
        model,
        stream: false,
        messages: [
          {
            role: 'system',
            content:
              'Summarize discussion themes from user posts. Be grounded, concise, and avoid mentioning AI or uncertainty unless the data is genuinely sparse.',
          },
          { role: 'user', content: prompt },
        ],
        options: {
          temperature: 0.35,
        },
      }),
    });
    if (!res.ok) {
      const body = await res.text().catch(() => '');
      if (ollamaDebugEnabled()) {
        console.log('[ollama-debug] upstream-error', {
          countryCode,
          status: res.status,
          body,
        });
      }
      throw new Error(`Ollama summary failed: ${res.status} ${body}`);
    }
    const json: any = await res.json();
    if (ollamaDebugEnabled()) {
      console.log('[ollama-debug] raw-response', {
        countryCode,
        response: json,
      });
    }
    const content = String(json?.message?.content ?? json?.response ?? '').trim();
    if (!content) return null;
    const cleaned = content
      .replace(/<think>[\s\S]*?<\/think>/gi, ' ')
      .replace(/thinking process:[\s\S]*$/i, ' ')
      .replace(/\s+/g, ' ')
      .trim();
    if (ollamaDebugEnabled()) {
      console.log('[ollama-debug] cleaned-summary', {
        countryCode,
        cleaned,
      });
    }
    return cleaned;
  } catch {
    return null;
  } finally {
    clearTimeout(timeout);
  }
}

function clampScore(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return Math.max(0, Math.min(1, value));
}

function normalizeSentimentScores(scores: Partial<SentimentScores>): SentimentScores {
  const positive = clampScore(Number(scores.positive ?? 0));
  const neutral = clampScore(Number(scores.neutral ?? 0));
  const negative = clampScore(Number(scores.negative ?? 0));
  const total = positive + neutral + negative;
  if (total <= 0) {
    return { positive: 0, neutral: 1, negative: 0 };
  }
  return {
    positive: positive / total,
    neutral: neutral / total,
    negative: negative / total,
  };
}

async function classifySentiment(texts: string[]): Promise<SentimentScores[]> {
  if (!texts.length) return [];
  const batch = texts.map((t) => clampText(t));
  try {
    const pipe = await getSentimentPipeline();
    const results: Array<any> = await pipe(batch, { top_k: 3 });
    return results.map((entry) => {
      const choices = Array.isArray(entry) ? entry : [entry];
      const next: Partial<SentimentScores> = {};
      for (const choice of choices) {
        const label = String(choice?.label ?? '').toUpperCase();
        const score = Number(choice?.score ?? 0);
        if (label === 'LABEL_2' || label.includes('POS')) next.positive = score;
        else if (label === 'LABEL_0' || label.includes('NEG')) next.negative = score;
        else next.neutral = score;
      }
      return normalizeSentimentScores(next);
    });
  } catch {
    return await classifySentimentRemote(batch);
  }
}

async function classifySentimentRemote(texts: string[]): Promise<SentimentScores[]> {
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
        return texts.map(() => ({ positive: 0, neutral: 1, negative: 0 }));
      }
      throw new GraphQLError(`Sentiment failed: ${res.status} ${txt}`);
    }
    const json: Array<Array<{ label: string; score: number }>> = await res.json();
    return json.map((choices) => {
      const next: Partial<SentimentScores> = {};
      for (const choice of choices ?? []) {
        const label = String(choice?.label ?? '').toUpperCase();
        const score = Number(choice?.score ?? 0);
        if (label === 'LABEL_2' || label.includes('POS')) next.positive = score;
        else if (label === 'LABEL_0' || label.includes('NEG')) next.negative = score;
        else next.neutral = score;
      }
      return normalizeSentimentScores(next);
    });
  } catch (err: any) {
    if (String(err?.name) === 'AbortError') {
      return texts.map(() => ({ positive: 0, neutral: 1, negative: 0 }));
    }
    throw err;
  } finally {
    clearTimeout(timeout);
  }
}

function parseJsonl<T>(text: string): T[] {
  const rows: T[] = [];
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      rows.push(JSON.parse(trimmed) as T);
    } catch {
      // skip malformed row
    }
  }
  return rows;
}

async function loadDemoPosts(): Promise<PostTextRow[]> {
  if (!cachedDemoPostsPromise) {
    cachedDemoPostsPromise = (async () => {
      const here = path.dirname(fileURLToPath(import.meta.url));
      const candidates = [
        path.resolve(process.cwd(), 'demo_social_dataset_30k/posts.jsonl'),
        path.resolve(process.cwd(), 'apps/web/public/demo_social_dataset_30k/posts.jsonl'),
        path.resolve(here, '../../../../../../demo_social_dataset_30k/posts.jsonl'),
      ];
      for (const candidate of candidates) {
        try {
          const raw = await readFile(candidate, 'utf8');
          const rows = parseJsonl<Array<Record<string, any>> extends never ? never : Record<string, any>>(raw);
          return rows
            .map((row) => ({
              text: [String(row?.title ?? '').trim(), String(row?.body ?? '').trim()].filter(Boolean).join(' ').trim(),
              created_at: String(row?.created_at ?? '').trim(),
              country_code: String(row?.country_code ?? '').trim().toUpperCase(),
            }))
            .filter((row) => row.text && row.created_at)
            .map(({ text, created_at, country_code }) => ({ text: `${country_code}\u0000${created_at}\u0000${text}`, created_at }));
        } catch {
          // try next candidate
        }
      }
      return [];
    })();
  }
  return cachedDemoPostsPromise;
}

async function fetchTexts(
  countryCode: string | null | undefined,
  preferredWindowHours: number,
  maxLookbackHours: number,
  maxPosts: number
): Promise<string[]> {
  const normalizedCountry = String(countryCode ?? '').trim().toUpperCase();
  const params: any[] = [];
  let whereSql = '';
  if (countryCode) {
    params.push(countryCode);
    whereSql = `where p.country_code = $${params.length}`;
  }
  params.push(maxLookbackHours);
  whereSql += `${whereSql ? ' and' : ' where'} p.created_at > now() - ($${params.length}::int * interval '1 hour')`;
  params.push(Math.min(MAX_TEXTS, maxPosts));
  const postLimitParam = params.length;
  const postsRes = await pool.query<{ title: string | null; body: string | null; created_at: string }>(
    `
    select p.title, p.body, p.created_at
    from public.posts p
    ${whereSql}
    order by p.created_at desc
    limit $${postLimitParam}
    `,
    params
  );

  const rows: PostTextRow[] = [];
  for (const row of postsRes.rows) {
    const title = row.title ? String(row.title).trim() : '';
    const body = String(row.body ?? '').trim();
    const combined = [title, body].filter(Boolean).join(' ').trim();
    if (combined) rows.push({ text: combined, created_at: String(row.created_at) });
  }

  const demoRows = await loadDemoPosts();
  for (const row of demoRows) {
    const [demoCountry, createdAt, text] = String(row.text ?? '').split('\u0000');
    if (!text || !createdAt) continue;
    if (normalizedCountry && demoCountry !== normalizedCountry) continue;
    const createdMs = Date.parse(createdAt);
    if (!Number.isFinite(createdMs)) continue;
    if (createdMs < Date.now() - maxLookbackHours * 60 * 60 * 1000) continue;
    rows.push({ text, created_at: createdAt });
  }

  return rows
    .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at))
    .filter((row, index) => {
      if (index < Math.min(40, maxPosts)) return true;
      const ageMs = Date.now() - Date.parse(row.created_at);
      return ageMs <= preferredWindowHours * 60 * 60 * 1000;
    })
    .slice(0, maxPosts)
    .map((row) => row.text);
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
  const settings = await getAdminSettings().catch(() => null);
  const cacheTtlMs = Math.max(
    60_000,
    Number(settings?.insight_cache_minutes ?? DEFAULT_CACHE_TTL_MS / 60000) * 60_000
  );
  const key = countryCode ? `cc:${countryCode.toUpperCase()}` : 'global';
  const cached = cache.get(key);
  if (cached && Date.now() - cached.at < cacheTtlMs) return cached.value;

  const windowHours = Math.max(1, Number(settings?.insight_window_hours ?? 24));
  const minPosts = Math.max(1, Number(settings?.insight_min_posts ?? 3));
  const maxPosts = Math.max(10, Number((settings as any)?.insight_max_posts ?? 250));
  const maxLookbackHours = Math.max(
    windowHours,
    Number((settings as any)?.insight_max_lookback_hours ?? 24 * 30)
  );
  const texts = await fetchTexts(countryCode ?? null, windowHours, maxLookbackHours, maxPosts);
  if (!texts.length) {
    const empty: CountryMood = {
      country_code: countryCode ? countryCode.toUpperCase() : 'GLOBAL',
      positive: 0,
      neutral: 0,
      negative: 0,
      total: 0,
      topics: [],
      insight: `Not enough posts are available to summarize yet. Try a wider lookback window or wait for more posts.`,
      computed_at: new Date().toISOString(),
    };
    cache.set(key, { at: Date.now(), value: empty });
    return empty;
  }

  let scores: SentimentScores[] = [];
  try {
    scores = await classifySentiment(texts);
  } catch (err: any) {
    throw new GraphQLError(`Sentiment failed: ${err?.message ?? 'unknown'}`);
  }

  const counts: MoodCounts = { positive: 0, neutral: 0, negative: 0, total: scores.length };
  for (const score of scores) {
    counts.positive += score.positive;
    counts.neutral += score.neutral;
    counts.negative += score.negative;
  }

  const topics = extractTopics(texts, 10);
  const insight =
    ((settings?.ollama_enabled ?? true)
      ? await generateInsightWithOllama(
          countryCode ? countryCode.toUpperCase() : 'GLOBAL',
          counts,
          texts
        )
      : null) ||
    buildInsight(counts, texts, topics);
  const mood: CountryMood = {
    country_code: countryCode ? countryCode.toUpperCase() : 'GLOBAL',
    ...counts,
    topics,
    insight:
      texts.length < minPosts
        ? `${insight} This read is based on a limited sample of available posts.`
        : insight,
    computed_at: new Date().toISOString(),
  };

  cache.set(key, { at: Date.now(), value: mood });
  return mood;
}

export function clearCountryMoodCache(): void {
  cache.clear();
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
