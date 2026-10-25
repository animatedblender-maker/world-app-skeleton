/**
 * Render Cron entrypoint — catch-up Voyage title/body embeds for Public posts.
 * Env: CONTENT_CRON_SECRET (or INSIGHTS_CRON_SECRET), optional MIND_EMBEDDINGS_CRON_URL
 */
const secret = process.env.CONTENT_CRON_SECRET || process.env.INSIGHTS_CRON_SECRET || '';
const url =
  process.env.MIND_EMBEDDINGS_CRON_URL ||
  'https://api.matterya.com/cron/mind-embeddings?limit=400';

if (!secret) {
  console.error('Missing CONTENT_CRON_SECRET / INSIGHTS_CRON_SECRET');
  process.exit(1);
}

const res = await fetch(url, {
  method: 'POST',
  headers: {
    'x-cron-secret': secret,
    'content-type': 'application/json',
  },
  body: '{}',
});

const text = await res.text();
console.log(res.status, text);
if (!res.ok) process.exit(1);
