# Env & deploy (developer)

## Required for Phase 2b live embeds
On Render **`matterya-api`** web service:

| Key | Notes |
|---|---|
| `VOYAGE_API_KEY` | From dashboard.voyageai.com — **required** |
| `MIND_EMBEDDINGS_ENABLED` | Optional; default on when key present |
| `DATABASE_URL` | Existing Supabase URL (pgvector enabled) |
| `CONTENT_CRON_SECRET` | Shared with pipeline cron |

Local: `apps/api/.env` (gitignored). Mode `0600` preferred. **Never commit keys.**

## Deploy API (ios-native)
```bash
cd /Volumes/MatteryaSSD/Development/Projects/World_App/world-app-skeleton
# Prefer minimal commits — stash unrelated WIP
git status -sb
cd apps/api && npx tsc --noEmit -p tsconfig.json
cd ../..
# stage only intended paths, commit, push origin ios-native
```

Render Root Directory = `apps/api`. Build command must be `npm run render-build` (see `docs/RENDER.md`). Dashboard often overrides Blueprint.

Auto-deploy usually follows push to `ios-native`. Confirm health + `/cron/mind-embeddings` → 401.

## iOS attribution fix
Client-side. Rebuild WorldApp from `ios-native` after Swift changes land. No Render step.

## Optional Render Cron (skipped)
`render.yaml` defines `matterya-mind-embeddings`, but creating it in Dashboard requires billing.  
**Skip unless you want paid Cron.** Endpoint + inline schedule remain.

## Docs vendoring
```bash
rsync -a --delete docs/mind/ apps/api/docs/mind/
```
`/mind` Docs tab reads `apps/api/docs/mind` first.
