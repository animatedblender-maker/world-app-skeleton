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

## Step 1 status

- Stack: `https://maroonbroccoli500.grafana.net/` (product owner)

---

## Step 2 — Secret on Render + Infinity data source (YOU)

### 2a. Add a secret on Render (API service)

1. Open [Render Dashboard](https://dashboard.render.com) → service that serves **api.matterya.com**  
2. **Environment** → **Add Environment Variable**  
3. Key: `METRICS_SUMMARY_SECRET`  
4. Value: invent a long random string (example format):  
   `matterya_metrics_$(openssl rand -hex 16)`  
   or any password-like string **you will not share publicly**  
5. **Save** → wait for redeploy to finish  

### 2b. Confirm the API accepts the secret

In Terminal (replace `YOUR_SECRET`):

```bash
curl -sS -H "x-cron-secret: YOUR_SECRET" \
  "https://api.matterya.com/v1/metrics/summary" | head -c 400
```

You should see `"ok":true` (even if `rows` is empty until the app sends metrics).

### 2c. Install **Infinity** plugin in Grafana

1. Open `https://maroonbroccoli500.grafana.net/`  
2. Left menu → **Connections** (or **Administration** → **Plugins**)  
3. Search **Infinity**  
4. **Install** / enable (Grafana Cloud free includes it)  

### 2d. Add Infinity data source

1. **Connections** → **Data sources** → **Add data source**  
2. Choose **Infinity**  
3. Name: `Matterya Metrics`  
4. Under **Authentication** / **HTTP headers** (wording varies):  
   - Header name: `x-cron-secret`  
   - Header value: same as `METRICS_SUMMARY_SECRET`  
5. **Save & test**

### 2e. Quick Explore (optional)

1. **Explore** → data source **Matterya Metrics**  
2. Type: **JSON**  
3. URL: `https://api.matterya.com/v1/metrics/summary`  
4. Parser: root → path `rows`  
5. You should see columns like `name`, `p50`, `p95`, `p99` after the app has uploaded events  

Reply: **`grafana step2 done`** when 2a–2d work (or paste any error text).

---

## Step 2 status

- Stack: `https://maroonbroccoli500.grafana.net/`
- Data source: **Matterya Metrics** (Infinity, not the provisioned `grafanacloud-infinity`)
- Auth: `x-cron-secret` = `METRICS_SUMMARY_SECRET`

---

## Step 3 — First dashboard (YOU — follow exactly)

### 3a. Create dashboard

1. Open `https://maroonbroccoli500.grafana.net/`
2. Left menu → **Dashboards**
3. **New** → **New dashboard**
4. **Add visualization** (or **Add** → **Visualization**)

### 3b. Wire Infinity to Matterya summary

1. Top data source dropdown → **Matterya Metrics** (your custom one)
2. Query type: **JSON** (or **UQL** if shown; prefer JSON)
3. **URL**: `https://api.matterya.com/v1/metrics/summary`  
   (full URL; do not use relative path only)
4. Method: **GET**
5. Parser / Root:
   - Parsing options → **Rows/Root** (or “Root selector”): `rows`
6. Format: **Table**
7. **Run query** / refresh

**Expected:** table with columns like `name`, `count`, `p50`, `p95`, `p99`  
If empty: use the iOS app for 30–60s (feed, hubs, messages), then refresh the panel.

### 3c. Panel settings

1. Visualization type (right): **Table**
2. Title: `Client milestones p50/p95/p99 (ms)`
3. **Apply** (top right)

### 3d. Optional second panel — single milestone

1. **Add** → **Visualization** again  
2. Same data source + URL + root `rows`  
3. Visualization: **Stat** or **Bar gauge**  
4. Transform (if available): **Filter data by values** → Field `name` → equal `app_start_to_feed_visible`  
5. Show field: `p95`  
6. Title: `Feed visible p95 (ms)`  
7. Apply  

Repeat for: `app_start_to_shell`, `reel_swipe_first_frame`, `message_local_visible`, `message_server_ack` when those names appear in the table.

### 3e. Save

1. **Save dashboard** (top right)  
2. Name: `Matterya Butter-Smooth SLOs`  
3. Save  

### 3f. Auto-refresh

Dashboard settings (gear) → **Auto refresh** → `30s` or `1m` → Save  

---

## Notes

- Metrics live **in API memory** until we add long-term storage: Render redeploy **clears** samples.  
- Multiple Render instances would split memory (fine for early SLOs).  
- Empty `rows` until the **new iOS build** uploads milestones.

---

## Ops check (optional, no Grafana)

After using the app for a minute:

```bash
# If you set CONTENT_CRON_SECRET on Render:
curl -sS -H "x-cron-secret: YOUR_SECRET" \
  https://api.matterya.com/v1/metrics/summary | head -c 800
```

Or call with a logged-in user Bearer token.
