# Local Video Moderation (Masquerade)

**Status:** code on `ios-native` — runs after anonymous post create.  
**Privacy:** frames are sampled with ffmpeg on the API host and scored with an on-box `@xenova/transformers` NSFW classifier. **Nothing is uploaded to OpenAI or other third parties.**

## Why not OpenAI Moderation?

OpenAI’s free Moderation endpoint documents no training on inputs and (for `/v1/moderations`) no abuse-log retention. Frames would still **transit** OpenAI briefly. Matterya uses a fully local path instead.

## Pipeline

```
create anonymous post (video)
  → scheduleAnonymousModeration (fire-and-forget)
      → local spam rules + adult keyword / NSFW frames
      → FLAG on platform (posts.flagged_at) — stays visible + Flagged badge
      → open anonymous.reports (reason auto:…) for human review
      → human at /reports/masquerade → Remove / Flag / Skip
```

Temp frame files are deleted in `finally`. Spam/scam still sets `state = held` (hidden). NSFW does **not** auto-hide.

## Human review

`https://api.matterya.com/reports/masquerade` (same password as `/reports`)

| Action | Effect |
|--------|--------|
| **Remove** | `posts.state = removed`, report resolved |
| **Flag** | keep `flagged_at`, report resolved |
| **Skip** | clear flag (policy OK / false positive), report dismissed |

## Policy (Masquerade is 18+)

| Signal | Effect |
|--------|--------|
| Spam / scam local rules | `held` (hidden) |
| Adult keywords in text | platform **Flagged** + open report |
| NSFW video ≥ threshold | platform **Flagged** + open report (all spaces) |
| Classifier / ffmpeg failure | `auto_scan_video_failed` action only (no mass-flag) |

## Env

| Key | Default | Meaning |
|-----|---------|---------|
| `MODERATION_ANON_ENABLED` | `true` | Kill switch for Masquerade auto-mod |
| `MODERATION_VIDEO_ENABLED` | `true` | Kill switch for frame NSFW path |
| `MODERATION_VIDEO_NSFW_THRESHOLD` | `0.85` | Max frame NSFW score to treat as hit |
| `MODERATION_VIDEO_MODEL` | `AdamCodd/vit-base-nsfw-detector` | Transformers.js image-classification model (ONNX) |
| `MODERATION_ANON_SCHEDULE_TIMEOUT_MS` | `90000` | Cap for background job |
| `HF_ACCESS_TOKEN` / `HUGGINGFACE_TOKEN` | — | Optional; helps model download rate limits |

First cold start downloads the model into the transformers cache (under `/tmp/matterya-transformers-cache` when unset).

## Admin / review

- Actions land in `anonymous.moderation_actions` (`actor_profile_id` null = system).
- Held posts: `anonymous.posts.state = 'held'`.
- Human restore: set `state` back to `active` (existing mod tools / SQL).

## Limits

- Soft NSFW (lingerie, suggestive) can false-positive; threshold is tunable.
- Short / corrupt packs may yield fewer than 3 frames.
- Does not detect CSAM-specific taxonomy beyond generic NSFW — escalate reports to human review.
- Seeded historical videos are not backfilled until a separate scan job is run.
