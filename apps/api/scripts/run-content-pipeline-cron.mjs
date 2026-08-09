/**
 * Render Cron entrypoint — calls the live API so only one service holds R2 credentials.
 * Env: CONTENT_CRON_SECRET (or INSIGHTS_CRON_SECRET), optional CONTENT_PIPELINE_URL
 */
const secret = process.env.CONTENT_CRON_SECRET || process.env.INSIGHTS_CRON_SECRET || '';
const url =
  process.env.CONTENT_PIPELINE_URL ||
  'https://api.matterya.com/cron/content-pipeline';

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
