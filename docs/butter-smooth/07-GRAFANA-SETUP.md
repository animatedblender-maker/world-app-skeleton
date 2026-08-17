# Grafana setup (step-by-step) — Matterya SLOs

You said you’re new to Grafana. We do this **one step at a time**.  
**Do only Step 1 now**, then reply `grafana step1 done` with your stack URL if you have it.

## What we’re building

```
iOS app → POST https://api.matterya.com/v1/metrics/batch
                ↓
         API in-memory summary (live now)
                ↓
         GET /v1/metrics/summary  (p50/p95/p99)
                ↓
         Grafana dashboard (you view charts)
```

Later we can wire Prometheus remote_write or Infinity plugin. First: account + datasource path.

---

## Step 1 — Create a free Grafana Cloud account (YOU)

1. Open: **https://grafana.com/auth/sign-up/create-user**  
2. Sign up with email/Google (free tier is enough).  
3. Finish onboarding until you see a **Grafana** home / stack.  
4. Note your stack URL, like:  
   `https://YOURNAME.grafana.net`  
5. Reply in chat: **`grafana step1 done`** and paste that URL if you see it.

**Do not** create dashboards yet. **Do not** install agents yet.  
Wait for Step 2 instructions after you confirm.

---

## Step 2 — (later, agent will guide)

- Add a data source that can poll or receive metrics  
- Or use Infinity plugin + JSON from `https://api.matterya.com/v1/metrics/summary`  
  (needs auth: Bearer or `x-cron-secret`)  

## Step 3 — (later)

- Panels for: `app_start_to_feed_visible`, `reel_swipe_first_frame`, `message_local_visible`, etc.

---

## Ops check (optional, no Grafana)

After using the app for a minute:

```bash
# If you set CONTENT_CRON_SECRET on Render:
curl -sS -H "x-cron-secret: YOUR_SECRET" \
  https://api.matterya.com/v1/metrics/summary | head -c 800
```

Or call with a logged-in user Bearer token.
