# Text Moderation MVP (Matterya)

**Status:** code on `ios-native` — apply SQL before `moderation_results` persists.  
**Scope:** posts + comments text only. NudeNet / Frame-0 video = Phase 2.

## Rule

```
Local spam rules → TextModerationProvider (stub | http Detoxify) → PolicyEngine
  → SAFE | LIMITED | REVIEW | HELD
  → posts.moderation_status (active | sensitive | hidden)
```

- Provider **failure never equals SAFE** → `REVIEW` / hidden from public feed.  
- Raw scores stored separately from policy decision.  
- Human admin actions (`moderation_actor` starting with `admin`) are not overwritten by auto path.

## Migration (YOU apply)

File:

`supabase/migrations/20260825120000_moderation_text_mvp.sql`

Creates `moderation_results`, adds comment moderation columns + `posts.moderation_policy_version`.

Until applied: scoring still runs; persist/queue may no-op or fall back for posts status only.

## Env / flags

| Key | Default | Meaning |
|-----|---------|---------|
| `MODERATION_TEXT_ENABLED` | `true` | Kill switch |
| `MODERATION_TEXT_PROVIDER` | `stub` | `stub` or `http` / `detoxify` |
| `MODERATION_TEXT_URL` | — | Sidecar POST URL when provider=http |
| `MODERATION_TEXT_TIMEOUT_MS` | `800` | Provider timeout |
| `MODERATION_POLICY_VERSION` | `text-mvp-1` | Version stamp |

Remote config flag: `moderation_text_enabled` (config version `2026-08-25.1`).

## Admin

- `GET /admin/moderation/queue` — recent limited/review/held  
- `GET /admin/moderation/metrics` — in-process counters  
- Existing `GET/POST /admin/reports…` for human hide/restore  

## License note

Detoxify / LibreTranslate-style stacks may carry AGPL or other obligations. **Do not enable `MODERATION_TEXT_PROVIDER=http` in production until legal/infra review.** Stub mode is fine for shipping the pipeline.

## Feed eligibility

Public Home / Sparks / Hubs queries already exclude `moderation_status in ('hidden','deleted')`. LIMITED → `sensitive` (still visible).
