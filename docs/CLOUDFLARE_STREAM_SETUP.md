# Cloudflare Stream setup (Matterya Feed HLS)

R2 stores files. **Stream** is Cloudflare’s video CDN that serves **HLS** (`.m3u8`) worldwide — that is what Instagram-class Feed needs.

## 1. Enable Stream (dashboard)

1. Open [Cloudflare Dashboard](https://dash.cloudflare.com) → select the **Matterya** account.
2. Left sidebar → **Stream** (under “Platform” / search “Stream”).
3. If prompted, **Enable Stream** / start free trial / add billing (Stream is a paid product once you leave trial).
4. Open **Stream** → **Videos**. You should see an empty library.

## 2. Customer code (playback host)

1. Upload any tiny test MP4 (or skip until API copy works).
2. Open a video → copy the **HLS Manifest URL**. It looks like:

   `https://customer-XXXXXXXXXXXX.cloudflarestream.com/<VIDEO_UID>/manifest/video.m3u8`

3. The `XXXXXXXXXXXX` part is **`CF_STREAM_CUSTOMER_CODE`**.

## 3. API token

1. Dashboard → **My Profile** (or Account) → **API Tokens** → **Create Token**.
2. Use a custom token with:
   - Account → **Cloudflare Stream** → **Edit**
   - Include the Matterya account resource
3. Copy the token once → that is **`CF_STREAM_API_TOKEN`**.

## 4. Account ID

1. Dashboard right sidebar (any domain overview) → **Account ID**  
   or Stream API docs URL path `/accounts/<ACCOUNT_ID>/stream`  
   → **`CF_ACCOUNT_ID`**

## 5. Put env on the API (Render)

On **api.matterya.com** service → Environment:

```text
CF_ACCOUNT_ID=...
CF_STREAM_API_TOKEN=...
CF_STREAM_CUSTOMER_CODE=...
```

Redeploy after save. Locally add the same three keys to `apps/api/.env` (never commit).

## 6. Database

Apply migration `supabase/migrations/20261127230000_posts_stream_uid.sql`  
(`posts.stream_uid`, `posts.stream_ready_at`).

## 7. What the agent does after you paste env

- `apps/api/src/media/cloudflare-stream.ts` — copy from R2 → Stream, poll ready, save UID
- `/v1/feed` will expose `playback.hls` + poster when `stream_uid` is set
- iOS prefers HLS over progressive MP4

## 8. Hot-only ingest (do not mirror all of R2)

R2 stays the full archive. Stream only gets videos that **real users are about to see**.

1. Client calls `GET /v1/feed` or `GET /v1/sparks`
2. API returns the page immediately (R2 URL if not ingested yet)
3. In the background, `stream-hot-queue` copies any video on that page that still has no `stream_uid`
4. Deduped by R2 `video.mp4` key (share/original twins share one Stream asset)
5. Caps: **2** concurrent copies, **≤120** new copies per hour per API process
6. Next time that post is served → `playback.hls` is present → Instagram-class CDN play

Check: `GET /v1/stream/status` → `{ configured, posts_with_stream_uid, hot_queue }`

Optional bulk head-fill (CLI, not required for hot-only):

```bash
cd apps/api
npm run media:stream-ingest -- --limit=50
```

## Not the same as R2

| | **R2** | **Stream** |
|---|--------|------------|
| What | Object storage (mp4/webp) | Transcoded HLS CDN |
| Catalog | Keep everything | Only hot Feed/Sparks traffic |
| Env you already have | `R2_*` | `CF_ACCOUNT_ID` / `CF_STREAM_*` |
