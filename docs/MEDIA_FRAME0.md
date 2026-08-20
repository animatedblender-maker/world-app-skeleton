# Frame 0 Poster — Zero-Worker Architecture

## Hard rule

```text
poster pixel content
        =
video's first displayed frame
```

Extract the **first frame normal playback displays** from the start of the asset.  
Do **not** choose a later “meaningful”, scene-detected, or YouTube `hqdefault` frame.

If that frame is black → poster is black.

## Two paths (no permanent media worker)

| Media | How Frame 0 is created | Cost |
|-------|------------------------|------|
| **Existing R2 catalog** | One-time **CLI backfill** on Mac/CI | $0 ongoing |
| **New uploads** | Client extracts Frame 0 before upload (later PR) | $0 server decode |

Do **not** run a permanent FFmpeg Background Worker on Render for Frame 0.

---

## Target layout (beside original)

```text
{packOrAssetPrefix}/video.mp4
{packOrAssetPrefix}/frame0_256.webp
{packOrAssetPrefix}/frame0_512.webp   ← default list / Sparks / Hubs poster
{packOrAssetPrefix}/frame0_1080.webp
```

User media (later): `media/{mediaId}/original.mp4` + `frame0.webp`.

---

## Ops — CLI backfill (existing videos)

From a machine with `DATABASE_URL`, `R2_*`, and ffmpeg (`ffmpeg-static` is bundled):

```bash
cd apps/api
npm run media:frame0-backfill:dry -- --limit=20
npm run media:frame0-backfill -- --limit=20
npm run media:frame0-backfill -- --limit=200 --concurrency=4
```

Flags:

| Flag | Meaning |
|------|---------|
| `--limit=N` | Max posts to claim (default 50) |
| `--concurrency=N` | Parallel extracts, max 8 (default 4) |
| `--dry-run` | List only |
| `--via-kafka` | Enqueue only (needs in-process consumer — not zero-worker) |

Idempotent: existing `frame0_*.webp` → refresh DB thumbs only; skip re-encode.

### Progress page

Live catalog % + current batch counters + log tail (same password as `/pipeline` / `/reports`):

```bash
cd apps/api
npm run media:frame0-progress
# → http://127.0.0.1:4091/frame0
```

On the API host after deploy: `https://api.matterya.com/frame0`

Progress files: `/tmp/matterya-frame0/progress.json` + `backfill.log` (override with `FRAME0_PROGRESS_DIR`).

Env for zero-worker API (optional after backfill):

```env
FRAME0_ZERO_WORKER=true
MEDIA_WORKER_INPROCESS=false
```

With `FRAME0_ZERO_WORKER=true`, catalog ingest **does not** enqueue Kafka Frame 0 jobs (run CLI periodically or after big R2 imports).

---

## DB writes (no migration required)

- `posts.thumb_url` → URL of `frame0_512.webp`
- `posts.thumb_path` → `r2:{bucket}/{prefix}/frame0_512.webp`
- `posts.media_url` JSON may include `posters` / `poster_rule: frame0`
- Shares inherit thumbs from origin when processed

Optional later: `media_assets` table — **ask before Supabase migration**.

---

## New uploads (next phase)

```text
device: normalize MP4 → extract Frame 0 from FINAL asset
  → signed R2 PUT (video + frame0.webp)
  → POST complete → thumb_url READY
```

iOS already extracts t=0 JPEG for optimistic thumbs; move to WebP + R2 with signed session.

---

## Client playback (already in app)

- Prefer `thumb_url` / `posters.512`
- Hold poster until **first painted video frame** (not merely `play()`)
- Home: conservative prep; Sparks: small player pool (N / N+1)

---

## Kafka

Topic `matterya.media` may still carry analytics (`MediaReady` etc.).  
It is **not** required for Frame 0 compute under zero-worker mode.

Emergency: `MEDIA_WORKER_INPROCESS=true` + `FRAME0_ZERO_WORKER=false` re-enables the in-process consumer.

---

## ffmpeg extract (canonical)

```bash
# Normalize SAR so poster aspect == on-screen video (AVPlayer), then fit long edge.
ffmpeg -y -ss 0 -i "$SRC" -frames:v 1 \
  -vf "scale=iw*sar:ih,setsar=1,scale=W:W:force_original_aspect_ratio=decrease" \
  -c:v libwebp -quality 80 "frame0_W.webp"
```

Long-edge **256 / 512 / 1080**. Seek before `-i`; never scene-detect.  
Re-extract wrong-aspect posters: `npm run media:frame0-backfill -- --force --limit=50`
