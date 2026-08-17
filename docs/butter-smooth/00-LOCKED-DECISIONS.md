# Butter-Smooth Program — Locked Decisions

**Status:** Mandatory for iOS + API  
**SLO owner:** Product owner (you)  
**Branch:** `ios-native`  
**API host:** Render → `api.matterya.com`  
**UI rule:** **No visual redesign.** Behavior and look stay as already shipped; work is latency, reliability, architecture, observability.

| # | Decision |
|---|----------|
| 1 | iOS + API mandatory; web/Android later |
| 2 | All surfaces: Feed, Hubs, Sparks, Messages, Search, Profile, Composer |
| 3 | Docs + code in parallel |
| 4 | You own SLOs / ship gates |
| 5 | You deploy (Render auto on push to `ios-native`); agent changes monorepo only |
| 6 | Migrations in `supabase/migrations/`; agent **asks you** before each apply |
| 7 | Grafana for p50/p95/p99 (setup guided step-by-step when ready) |
| 8 | Versioned `GET /v1/config` + TTL/edge-ready cache (flags/kill switches) |
| 9 | Device floor: iPhone 11 / iOS 17 |
| 10 | Feed: 24h max local snapshot; soft-refresh on open; ~10m soft-stale; privacy always wins |
| 11 | Outbox: like/save/follow/mute first; comments next; messages same module; upload = resumable/draft |
| 12 | P0 product bugs first; else foundations-first; never skip ship gates for cosmetics |

## When agent needs you

| Action | You do |
|--------|--------|
| API live | `git push origin ios-native` (or confirm auto-deploy) |
| SQL migration | Agent pastes file path + instructions → you run in Supabase |
| Grafana | Agent starts guided setup → you create free Grafana Cloud account when asked |
| Device smoke | Cold start / feed / Sparks / mini on real iPhone 11-class device |

## Non-goals (explicit)

- Changing layout, colors, copy, or product flows unless required for a P0 bug fix already agreed.
- Android / web implementation in this phase.
- Replacing ranking quality with a different product experience.
