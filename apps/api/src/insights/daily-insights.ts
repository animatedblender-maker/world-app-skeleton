import { pool } from '../db.js';
import { runAllCountryMoods } from '../graphql/modules/insights/insights.service.js';

type CaptionResult = {
  post_id: string;
  caption: string;
};

const HF_TOKEN = process.env.HF_ACCESS_TOKEN || process.env.HUGGINGFACE_TOKEN || '';
const HF_CAPTION_URL =
  process.env.HF_CAPTION_URL ||
  'https://router.huggingface.co/hf-inference/models/Salesforce/blip-image-captioning-base';

const MAX_CAPTIONS_PER_RUN = Number(process.env.MAX_CAPTIONS_PER_RUN ?? 120);
const FETCH_TIMEOUT_MS = Number(process.env.CAPTION_FETCH_TIMEOUT_MS ?? 15000);

async function fetchImageBytes(url: string): Promise<ArrayBuffer> {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(url, { signal: controller.signal });
    if (!res.ok) throw new Error(`image_fetch_failed:${res.status}`);
    const arrayBuffer = await res.arrayBuffer();
    return arrayBuffer;
  } finally {
    clearTimeout(timeout);
  }
}

async function captionImage(url: string): Promise<string> {
  if (!HF_TOKEN) throw new Error('missing_hf_token');
  const bytes = await fetchImageBytes(url);
  const res = await fetch(HF_CAPTION_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${HF_TOKEN}`,
      'Content-Type': 'application/octet-stream',
    },
    body: bytes as ArrayBuffer,
  });
  if (!res.ok) {
    const msg = await res.text().catch(() => '');
    throw new Error(`caption_failed:${res.status}:${msg}`);
  }
  const json: any = await res.json().catch(() => null);
  if (Array.isArray(json)) {
    const text = String(json[0]?.generated_text ?? '').trim();
    if (text) return text;
  }
  const single = String(json?.generated_text ?? '').trim();
  if (single) return single;
  throw new Error('caption_empty');
}

async function fetchPostsNeedingCaptions(): Promise<Array<{ id: string; media_url: string | null; thumb_url: string | null; media_type: string }>> {
  const { rows } = await pool.query<{
    id: string;
    media_url: string | null;
    thumb_url: string | null;
    media_type: string;
  }>(
    `
    select p.id, p.media_url, p.thumb_url, p.media_type
    from public.posts p
    left join public.post_media_captions c on c.post_id = p.id
    where p.media_type in ('image','video')
      and p.media_url is not null
      and (c.caption is null or c.caption = '')
    order by p.created_at desc
    limit $1
    `,
    [MAX_CAPTIONS_PER_RUN]
  );
  return rows;
}

async function saveCaptions(captions: CaptionResult[]): Promise<void> {
  if (!captions.length) return;
  const values: string[] = [];
  const params: any[] = [];
  captions.forEach((row, idx) => {
    const base = idx * 2;
    values.push(`($${base + 1}, $${base + 2})`);
    params.push(row.post_id, row.caption);
  });
  await pool.query(
    `
    insert into public.post_media_captions (post_id, caption)
    values ${values.join(',')}
    on conflict (post_id) do update set
      caption = excluded.caption,
      updated_at = now()
    `,
    params
  );
}

export async function runDailyInsights(): Promise<{ processed: number; failed: number }> {
  return await runAllCountryMoods();
}
