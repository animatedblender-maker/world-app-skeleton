# Runbook — Admin MIND console

## Open

1. Visit https://api.matterya.com/mind
2. Enter the Ops password (same as Pipeline / Reports / Frame 0)
3. You land on the illustrated console; numbers refresh about every 5 seconds

## What the panels mean

| Panel | Green / healthy | Amber / attention | Red / broken |
|---|---|---|---|
| Ledger | Reservations increasing; low conflict rate | Cursor fallback often | Schema missing / all cursor |
| Rank | `modelVersion` present; latency stable | Cache cold | Errors in status |
| Masquerade isolation | Namespace checks pass | N/A | Public path reading anon prefs |
| Seed | Media/text progressing | Stalled progress line | Process dead mid-phase |
| Gap matrix | Phase 1 greens | Partials | Unexpected missing for Phase 1 |

## Live feedback

- **Status JSON:** `GET /mind/api/status` (cookie required)
- **SSE stream:** `GET /mind/api/stream` pushes sanitized log/decision lines
- Seed progress on API hosts without the Matterya SSD shows “local seed N/A”

## Safe actions

This console is **read-mostly**. It does not run training jobs or mutate user data. Pipeline/Frame 0 actions stay on their own tabs.

## Incident hints

1. Feeds repeating content → check ledger panel + `deliveryPolicy` on a sample feed response.
2. Masquerade empty → check room post counts + seed panel; confirm `anonymous` feature on `/health`.
3. Rank weirdness → note `POLICY_VERSION` / `modelVersion` and recent engagement volume.
