# Strikes and removal notices

When a content ticket resolves to **remove** (via the policy decision tree):

1. The **author** gets a removal notice.
2. **User reporters** get a “thanks, we took action” notice.
3. The author receives a **strike**.
4. Accounts may enter the separate **account Claim-next queue**.

Mark / dismiss outcomes do **not** create strikes or account tickets.

## Queues

| Queue | URL | Filter |
|---|---|---|
| Content | `/reports` | `moderation_tickets.queue = 'content'` |
| Accounts | `/reports/accounts` | `moderation_tickets.queue = 'account'` |

Same password cookie as Insights / pipeline.

## Severity

Policy leaves with `outcome: 'remove'` carry `severity: 'mild' | 'severe'` (default mild).

**Severe** → open an account-review ticket immediately (in addition to recording the strike).

**Mild** → `+1` open strike; when open strikes reach **3**, open an account-review ticket.

Tune severity on leaves in `apps/api/src/moderation/policy-tree.ts` via `leaf(..., { severity: 'severe' })`.

Current severe set (see source for the live list): threats, sexual blackmail / stalking, dehumanizing hate / slurs / praise, CSAM-adjacent, gore / animal cruelty / violence incitement, self-harm promotion, financial scam / impersonation, hard PII / intimate / workplace doxxing.

## Strikes table

`public.account_strikes` — one row per remove. Open = `cleared_at is null`.

Subject kinds:

- `user` — feed / sparks / hubs (`profiles.user_id`)
- `anonymous_profile` — Masquerade (`anonymous.profiles.id`)

Account tickets reuse `moderation_tickets` with `target_kind = 'profile'` and `queue = 'account'`. Upsert is idempotent while an open/claimed ticket already exists for that profile.

## Notifications

| Audience | Feed type | Masquerade kind | Copy |
|---|---|---|---|
| Author | `moderation_removal` | `moderation_removal` | Your post was removed for [category]. |
| Reporter | `moderation_report_resolved` | `moderation_report_resolved` | Thanks — we removed content you reported. |

Auto-flag rows (`reason like 'auto:%'`) do not get reporter thanks.

iOS: `NotificationsPanelView` + Masquerade `AnonymousNotification.displayTitle` handle these kinds.

## Account queue actions

1. Clear strikes — no account action  
2. Warn — notify + clear strikes  
3. Restrict — notify + clear strikes (v1 record-only)  
4. Suspend — deactivate feed profile (`account_status = deactivated`) or notify Masquerade; clear strikes  
5. Pass — same `passed_by` handoff as content

Flash stays “Decision recorded”.

## Thresholds

- Mild escalate at: **3** open strikes (`MILD_STRIKE_THRESHOLD` in `enforcement.ts`)
- Strike expiry / appeals: out of scope for v1

## Wiring

- `resolveTicket({ leafId })` archives on remove, commits, then `applyRemovalEnforcement` (best-effort).
- Content claim filters `queue = 'content'` so account tickets never appear on `/reports`.
