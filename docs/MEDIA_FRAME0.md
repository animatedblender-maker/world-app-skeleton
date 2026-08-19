# Frame 0 Poster — Instant Playback Media Rule

## Hard rule

```text
poster pixel content
        =
video's first displayed frame
```

Extract at **timestamp = 0** / the first decodable displayed frame.  
Do **not** choose a later “meaningful”, scene-detected, or YouTube `hqdefault` frame for Matterya-owned video.

## Target layout (beside original)

```text
{packOrAssetPrefix}/video.mp4
{packOrAssetPrefix}/frame0_256.webp
{packOrAssetPrefix}/frame0_512.webp   ← default list / Sparks / Hubs poster
{packOrAssetPrefix}/frame0_1080.webp
{packOrAssetPrefix}/variants/…        ← later (PR6)
{packOrAssetPrefix}/hls/master.m3u8   ← later (PR6)
```

## Pipeline

```text
Client → resumable upload → R2
  → media.upload.completed (Kafka topic matterya.media)
  → media worker (in-process consumer today; dedicated Render worker later)
  → validate / inspect
  → extract FRAME 0
  → encode frame0_{256,512,1080}.webp
  → (later) streaming variants + HLS
  → mark READY (soft: progressive MP4 stays playable)
```

Catalog Sparks/LongForm follow the same Frame 0 path after ingest:

```text
content-pipeline insert original
  → enqueue MediaProcessRequested
  → same worker
```

## Kafka (`matterya.media`)

| Event | When |
|-------|------|
| `media.upload.completed` | Object landed in R2 (user or catalog) |
| `MediaProcessRequested` | Backfill / reprocess / catalog post-insert |
| `MediaReady` | Frame 0 (and later ABR/HLS) written; `thumb_url` updated |
| `MediaFailed` | Validation or ffmpeg failure |

Do **not** put media jobs on `matterya.r2.ingest` — that topic is catalog flood only.

## DB writes (no migration for Frame 0)

- `posts.thumb_url` → playable URL of `frame0_512.webp`
- `posts.thumb_path` → `r2:{bucket}/{prefix}/frame0_512.webp`
- `posts.media_url` JSON may gain `posters: { "256", "512", "1080" }`
- Shares (`shared_post_id = origin`) inherit the same thumb fields

## ffmpeg extract (canonical)

```bash
ffmpeg -y -ss 0 -i "$SRC" -frames:v 1 -vf "scale=W:-2" "frame0_W.webp"
```

Sizes: long-edge **256 / 512 / 1080**. Never `-ss` after a scenic seek.

## Client

- Prefer `thumb_url` / embedded `posters.512` before any fallback.
- YouTube `hqdefault` is **not** Frame 0 — demote once server posters exist.
- Optimistic upload thumb must also be **t=0** (iOS already does).

## Ops

- Worker runs **in-process** with `matterya-api` when `KAFKA_ENABLED=true` (ffmpeg on PATH).
- Dedicated Render Background Worker + Docker image: **ask before deploy**.
- Backfill: `npm run media:frame0-backfill` in `apps/api` (enqueue only; consumer does work).
