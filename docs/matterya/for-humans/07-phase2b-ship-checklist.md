# Phase 2b ship checklist — close before “fun”

**Goal:** MIND understanding (Voyage) + correct Hubs/Feed attribution + usable Hubs catalog are live end-to-end.

## Done in code / data
- [x] Voyage title/body backfill (~38k embeddings) — DONE  
- [x] Auto-embed on upload + pipeline seed  
- [x] `/cron/mind-embeddings` catch-up route (no paid Render Cron)  
- [x] `/mind` People dossier (real users only)  
- [x] Archive name fix (iOS)  
- [x] Bigger equal bottom tabs (iOS)  
- [x] Hubs caps toward ~1900 (iOS + API)  
- [x] Docs pack in `docs/matterya/`

## Your finish clicks (required)
1. **Render `matterya-api`**
   - Env has **`VOYAGE_API_KEY`**
   - Latest `ios-native` deploy finished (`addcd44`+ People filter, `755a505` hubs limits, iOS commit for clients)
2. **`/mind` → Live**
   - Line like: `Voyage voyage-4-lite · embed rows ~38k · **ANN ON**`
3. **`/mind` → People**
   - Most active = real humans only (Amr, Mona, … — no Linda Gibson seeds)
4. **Rebuild iOS** from `ios-native`
   - Feed names correct (not everything “The Archive”)
   - Bottom tabs large / equal
   - Hubs scrolls toward full LongForm set
5. **Home theme test**
   - Watch 3–5 same-theme clips → scroll Home → more related feel

## Explicitly deferred (after fun / later)
- Multimodal Voyage  
- Paid Render Cron for embeds  
- Cold start product polish  
- Trust/safety ops queue  
- Creator dashboard  
- GraphQL FeedItem / ads / ML eval  

When checklist 1–5 are green → Phase 2b ship is **closed**. Then fun.
