# What we built (plain checklist)

This is the **operator view** of recent Matterya work.  
Dates are around late October 2026 unless noted.

---

## A. Recommendation brain (MIND)

- [x] Admin console at `/mind`
- [x] Delivery ledger (remember what was shown)
- [x] Engagement events (like / watch / hide / …)
- [x] Candidates + interest features
- [x] Masquerade isolation (public ≠ anonymous)
- [x] Topics from transcripts (Phase 2a)
- [x] Voyage title/body embeddings + similar-posts lane (Phase 2b)
- [x] Policy version on production health: `mind.phase2.v2`

## B. Voyage embeddings

- [x] Chose Voyage (`voyage-4-lite`) after SpaceXAI Explore had no embedding models
- [x] Store vectors in Postgres (`mind_content_embeddings` + pgvector)
- [x] One-time Mac backfill for ~39k existing posts  
      Progress page: **http://127.0.0.1:8789/**
- [x] Payment method on Voyage unlocks faster rate limits (credits alone were still slow)
- [x] **New posts auto-embed** after upload or pipeline seed  
      → you do **not** re-run the big backfill for every batch
- [x] Catch-up API exists: `POST /cron/mind-embeddings`  
- [x] **Skipped** a paid Render Cron Job (needs a card) — not required  
      Inline embeds + optional manual curl are enough

## C. Feed names (“The Archive” disaster)

- [x] Found the bug: every Hubs-stamped post was treated like an Internet Archive seed
- [x] Fixed so:
  - **Sparks** show the **uploading person**
  - **Hubs on feed** show the **person who shared**, with “Shared from …” the real channel (Dokumentar AL, The Archive, …)
  - Only true Archive **seeds** use the channel name **The Archive**
- [ ] **Rebuild the iOS app** so the fix appears on device (code is in `ios-native`)

## D. Ops / money / infra notes

- Supabase Disk IO: prefer prune/cache first; upgrade compute only if still stuck  
- Voyage free tier is large enough for this text pass; speed needed a payment method  
- Multimodal Voyage (images/frames) = **later**, not next  
- Render web service needs `VOYAGE_API_KEY` for live embeds

## E. Product direction we agreed

Near-term Matterya “next level” order:
1. Finish + ship text ANN live  
2. Butter-smooth clients (always)  
3. Cold start for new users  
4. Creator clarity (attribution, tools, simple stats)  
5. Trust/safety loop (report → review → action)  

Skip for now: embedding every LongForm frame; full ads auction; TikTok-scale T&S org overnight.
