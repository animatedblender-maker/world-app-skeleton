# Matterya web Chat/Messages — launch audit

**Repo:** `/Volumes/MatteryaSSD/Development/Projects/World_App/world-app-skeleton`  
**Scope:** Web messages UI + `MessagesService` + API GraphQL messages module  
**Date:** 2026-10-16  
**Deploy:** not done (per request)

## Verdict

Core messaging path is wired correctly against production GraphQL (`https://api.matterya.com/graphql`): auth-gated queries/mutations exist and match the web client. Chat was launch-blocked by **polling UX bugs**, a **stale-thread race**, and **missing optimistic send** — not by wrong endpoints.

**P0/P1 fixes applied in** `apps/web/src/app/pages/messages.page.ts`. API modules left unchanged (schema/service already sound).

---

## E2E checklist

| # | Flow | Status | Notes |
|---|------|--------|-------|
| 1 | Inbox list loads | **OK** | `conversations` GraphQL + auth. Empty copy present. Errors surface in `conversationError` (no longer silent on first load). |
| 2 | Open thread | **OK (fixed)** | Clears prior messages on switch; race guard so late responses cannot overwrite the open thread. |
| 3 | Send text | **OK (fixed)** | Optimistic bubble (`pending-*`), Enter-to-send (Shift+Enter newline), rollback on failure. |
| 4 | Receive / realtime | **Partial → OK for launch** | No message websocket; **6s polling** (silent). Adequate for launch; not WhatsApp-grade latency. Call signaling uses `/ws`. |
| 5 | Media attach | **OK (dependency)** | Composer attach → Supabase `messages` bucket upload → `sendMessage` media fields → signed URL hydrate. Fails loudly on upload/policy errors. |
| 6 | Empty / error / auth | **OK (hardened)** | Route `authGuard`; page bails with “Sign in…” if `meId` missing; empty inbox/thread states; poll failures no longer flash thread errors. |
| 7 | Performance | **Improved** | Silent poll (no “Loading…” flash); conversation `trackBy`; skip message poll while sending/editing; silent poll fetches 80 msgs not 300. Keystroke still CD’s this large page (no OnPush split yet). |

---

## Live API smoke

```
Query: conversations, conversationById, messagesByConversation, messagesUnreadCount
Mutation: startConversation, sendMessage, updateMessage, deleteMessage, archiveConversation, deleteConversation, markConversationNotificationsRead
Unauthed conversations → UNAUTHENTICATED (expected)
```

Web client variable mapping (`$conversationId` → `conversation_id`, etc.) matches `typeDefs.ts`.

---

## Bugs found

### P0 — fixed

1. **Polling flashed inbox loading every 6s**  
   `startPolling` → `loadConversations()` always set `loadingConversations = true` → “Loading conversations…” on a timer.  
   **Fix:** `loadConversations(selectId?, silent=false)`; poll uses `silent=true`.

2. **Poll errors painted as hard thread failures**  
   Silent `loadMessages` wrote `messageError` on any network blip.  
   **Fix:** only set `messageError` / `conversationError` when not silent; warn to console on poll failure.

3. **Stale thread race**  
   Fast A→B switch could apply A’s response onto B.  
   **Fix:** `messagesLoadToken` + `activeConversationId` guards; clear messages when switching.

4. **No optimistic send (code already expected `pending-`)**  
   Send waited on network; felt broken vs iMessage/WhatsApp.  
   **Fix:** insert `pending-*` bubble immediately, replace on success, restore draft/media on failure; hide tools while pending.

### P1 — fixed

5. **Conversation list lacked `trackBy`** → DOM churn on CD/poll/keystroke.  
6. **Enter in composer inserted newline only** → added Enter-to-send.  
7. **Bottom tabs safe-area padding left a dead gap** with thread open → `.wrap.thread-open { padding-bottom:0 }`.  
8. **Heavy silent polls** while composing → skip message poll when `messageBusy` / `editBusy`; silent limit 80.

### P2 — open (not launch-blocking)

9. **Receive latency ~0–6s** (poll-only). Ideal: subscribe via Kafka/WS or Supabase realtime on `messages`.  
10. **Unread** driven by notification list, not `messagesUnreadCount` / `last_read_at` diff. Works; can drift if notifications fail.  
11. **`setActiveConversation` presence** unused on web (API exists) — no “in chat” presence for peers.  
12. **Signed media URL failures** return `null` silently in `MessagesService.getSignedUrl` — media bubble missing without explanation.  
13. **Page is a 3.2k-line monolith** — keystroke CD still re-evaluates inbox+thread. Split inbox child + `OnPush` for premium perf.  
14. **Calls** depend on LiveKit env + `/ws`; out of text-chat launch basics (separate risk).

---

## What was changed

**File:** `apps/web/src/app/pages/messages.page.ts`

- Silent conversation/message polling; no loading flash / no poll error banners  
- Message load generation token + active-conversation guards  
- Optimistic send + pending UI + Enter-to-send  
- `trackBy` on inbox; preserve pending rows in `mergeMessages`  
- Clear thread state on conversation switch / deep-link activate  
- Auth empty-state if session missing mid-page  
- Composer sticky already present; thread-open padding fix  

**Unchanged (verified OK):**

- `apps/web/src/app/core/services/messages.service.ts` — endpoints/auth via `GqlService` Bearer token; no silent `[]` on list/send  
- `apps/api/src/graphql/modules/messages/*` — auth, membership checks, send/list/unread  

---

## Premium polish status

| Item | Status |
|------|--------|
| Sticky composer | Already present (`position:sticky; bottom:0`) |
| Timestamps | Present (inbox + bubble meta + day separators) |
| Unread dots | Present (`unreadConversationIds` + bold row) |
| Optimistic send | **Added** |
| Read receipts | Present (`isLastReadOwn` → “Read”) via peer `last_read_at` |
| Keyboard send | **Added** (Enter send / Shift+Enter newline) |

---

## Manual QA before launch

1. Sign in → `/messages` → inbox loads or empty state (not spinner forever).  
2. Open a thread → messages load; switch threads quickly → no cross-talk.  
3. Send text → bubble appears immediately; survives refresh/poll.  
4. Second account/window → message appears within ~6s.  
5. Attach image → preview → send; confirm bubble media after signed URL.  
6. Kill network mid-poll → no red error flash; send with network down → error + draft restored.  
7. Logged-out hit `/messages` → auth redirect (guard).  

---

## Residual risk

Chat basics are in good shape for a premium-feeling **text** launch. Realtime receive and inbox `OnPush` split remain the main gaps vs WhatsApp/iMessage. Do not treat calls/LiveKit as verified by this audit.
