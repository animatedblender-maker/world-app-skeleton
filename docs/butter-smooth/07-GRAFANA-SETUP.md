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

## Step 3 — First dashboard (YOU — prefer Import)

**Do this now.** Prefer the Import path (3A). Manual panels are only a fallback (3B).

### Before you open Grafana (fills empty panels)

1. **Rebuild iOS** from latest `ios-native` (handoff + swipe milestones).  
2. Use the app ~60s: open feed, tap a playing Spark, swipe Sparks, open a Hub from feed.  
3. **Optional seed** (no phone needed) — in Terminal, with your Render secret:

```bash
cd /path/to/world-app-skeleton
chmod +x scripts/seed-metrics-sample.sh
METRICS_SUMMARY_SECRET='YOUR_SECRET' ./scripts/seed-metrics-sample.sh
```

You should see `"ok":true` and a `rows` array with names like `sparks_feed_handoff_first_frame`.

### 3A. Import dashboard (recommended)

1. Open `https://maroonbroccoli500.grafana.net/`
2. Left menu → **Dashboards** → **New** → **Import**
3. Upload / paste JSON from the repo file:  
   `docs/butter-smooth/grafana/matterya-butter-smooth-slos.json`  
   (open the file → Select All → Copy → paste into Grafana **Import via panel json**)
4. When asked for a data source, pick **Matterya Metrics** (your Infinity DS from Step 2)  
   - If the dropdown is empty: cancel, confirm Infinity DS name, re-import.
5. **Import**
6. Open the dashboard → gear (⚙️) → **Auto refresh** → `30s` → **Save dashboard**  
   Title should stay: **`Matterya Butter-Smooth SLOs`**

**Expected panels**

| Panel | Milestone |
|-------|-----------|
| Table | all `name / count / p50 / p95 / p99` |
| Stat | `sparks_feed_handoff_first_frame` p95 |
| Stat | `reel_swipe_first_frame` p95 |
| Stat | `hubs_feed_handoff_first_frame` p95 |
| Stat | `app_start_to_feed_visible` p95 |
| Stat | `hubs_first_useful` / `message_local_visible` / `app_start_to_shell` / `sparks_open_first_frame` |

If Stat panels say N/A: table may still work — filter by name after the seed/smoke. Infinity filter syntax varies by plugin version; the **table** is the source of truth.

### 3B. Manual fallback (only if Import fails)

1. **Dashboards** → **New** → **New dashboard** → **Add visualization**
2. Data source → **Matterya Metrics**
3. Type **JSON** · URL `https://api.matterya.com/v1/metrics/summary` · Method **GET**  
   Root / Rows selector: `rows` · Format **Table** · Run query
4. Title: `Client milestones p50/p95/p99 (ms)` → Apply → Save as `Matterya Butter-Smooth SLOs`
5. Auto refresh `30s`

### Step 3 done gate

Reply in chat: **`grafana step3 done`**  
(optional: paste that the table shows handoff/swipe rows, or a screenshot)

---

## Step 3 status

- [ ] Dashboard imported / created: `Matterya Butter-Smooth SLOs`
- [ ] Auto-refresh 30s
- [ ] Table shows live rows after iOS smoke or seed script

---

## Notes

- Metrics live **in API memory** until we add long-term storage: Render redeploy **clears** samples.  
- Multiple Render instances would split memory (fine for early SLOs).  
- Empty `rows` until the **new iOS build** uploads milestones (or you run the seed script).  
- Infinity import may ask you to **re-select** `Matterya Metrics` if the UID differs from the JSON placeholder.

---

## Ops check (optional, no Grafana)

After using the app for a minute:

```bash
curl -sS -H "x-cron-secret: YOUR_SECRET" \
  https://api.matterya.com/v1/metrics/summary | head -c 800
```

Or call with a logged-in user Bearer token.
