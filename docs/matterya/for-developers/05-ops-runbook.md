# Ops runbook (developer)

## MIND console
- Prod: https://api.matterya.com/mind  
- Auth: Ops password cookie (`matterya_pipeline_auth`)  
- Status: `GET /mind/api/status` (cached ~20s)

## Content pipeline
- UI: https://api.matterya.com/pipeline  
- Cron: `POST /cron/content-pipeline` every 6h (`matterya-content-pipeline`)  
- Docs: `docs/CONTENT_PIPELINE.md`

## Embeddings catch-up
```bash
curl -sS -X POST \
  'https://api.matterya.com/cron/mind-embeddings?limit=400' \
  -H "x-cron-secret: $CONTENT_CRON_SECRET" \
  -H 'content-type: application/json' -d '{}'
```

Expect JSON `{ ok, scanned, upserted, tokensApprox, … }`.  
`401` → wrong/missing secret. `404` → API build without `fa44852+`.

**Render Cron Job for this route is optional and was skipped** (billing card). Use curl or a Mac LaunchAgent if you want a schedule without Render Cron.

## Mac embed backfill
```bash
# status
curl -s http://127.0.0.1:8789/status.json | jq .

# restart (example)
DIR=/Volumes/MatteryaSSD/Development/tmp/mind-embed
PY=/Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.9/Resources/Python.app/Contents/MacOS/Python
kill $(cat $DIR/backfill.pid) 2>/dev/null
nohup $PY -u $DIR/backfill_voyage.py >> $DIR/backfill.log 2>&1 &
echo $! > $DIR/backfill.pid
```

## Disk IO (Supabase)
Prefer: outbox prune, `/mind` status cache, avoid huge COUNT storms.  
Upgrade compute only if budget stays exhausted under normal traffic.  
Project ref in memory: `bpdkltgikgbnfjswdbaj`.

## Smoke checks after API deploy
```bash
curl -sS https://api.matterya.com/health | jq '.features.mindPolicyVersion'
curl -sS -o /dev/null -w '%{http_code}\n' -X POST https://api.matterya.com/cron/mind-embeddings
# expect 401 (route exists) not 404
```
