# Checklists & steps (operator)

Print or keep this open while working.

---

## 1) Voyage API key on Render (required for live embeds)

1. Open https://dashboard.voyageai.com → create/copy an API key  
2. Open https://dashboard.render.com → service **`matterya-api`**  
3. **Environment** → add:
   - `VOYAGE_API_KEY` = (your key)  
   - Optional: `MIND_EMBEDDINGS_ENABLED` = `true`  
4. Save → wait for redeploy  
5. Confirm https://api.matterya.com/health still healthy  

**Do not paste keys into chat or commit them to git.**

---

## 2) Historical embed backfill (Mac — one time)

Already set up under:

`/Volumes/MatteryaSSD/Development/tmp/mind-embed/`

| Item | Path / URL |
|---|---|
| Progress page | http://127.0.0.1:8789/ |
| Status JSON | http://127.0.0.1:8789/status.json |
| Script | `backfill_voyage.py` |
| Log | `backfill.log` |

**If it stopped:** ask your engineer (or Grok) to restart it.  
**When it says DONE:** historical posts are embedded.

You do **not** re-run this for every new batch.

---

## 3) Optional catch-up (no paid Render Cron)

We **skipped** creating a Render Cron Job (it asked for a card). That is fine.

If you ever want a manual catch-up after a long outage:

```bash
curl -X POST 'https://api.matterya.com/cron/mind-embeddings?limit=400' \
  -H "x-cron-secret: YOUR_CONTENT_CRON_SECRET"
```

Use the **same secret** as the content-pipeline cron on Render.  
Ask your engineer if you don’t have it locally.

---

## 4) See MIND live

1. Open https://api.matterya.com/mind  
2. Log in with the Ops password (same as Pipeline / Reports)  
3. Check Overview + Live system + Gap matrix  
4. **People** tab → search a real user (name / @username / email / uuid) → open their interest dossier (hubs, countries, creators, engagement, deliveries, neighbors)

Local API (if running on the Mac): http://127.0.0.1:3000/mind  

---

## 5) iOS: Archive name fix

1. Pull / open branch **`ios-native`**  
2. Build WorldApp to a phone or simulator  
3. Check Home feed names:
   - Sparks → people  
   - Shares → person + “Shared from …”  
   - Live channels → Dokumentar AL etc.  
   - Only Archive seeds → The Archive  

---

## 6) Content pipeline (seeds)

1. https://api.matterya.com/pipeline  
2. Or cron already hits `/cron/content-pipeline` every 6h  
3. New seeds should auto-queue embeddings after API deploy with `VOYAGE_API_KEY`

---

## 7) When something feels wrong

| Symptom | First check |
|---|---|
| Feed names all “The Archive” | Rebuild iOS with the attribution fix |
| New posts never appear in “similar” | Is `VOYAGE_API_KEY` on Render? |
| Embed progress stuck | Open :8789 — running or stopped? |
| `/mind` won’t load | Ops password / API deploy |
| App feels laggy | Butter-smooth / Frame0 track (separate docs) |

---

## 8) Money decisions we already made

| Idea | Decision |
|---|---|
| Render Cron for hourly embeds | **Skip** (needs card) — not necessary |
| Voyage payment method | **Yes** if you want speed (unlocks rate limits) |
| Multimodal embeds next | **No** — later |
| Supabase upgrade | Only if Disk IO stays bad after prune/cache |
