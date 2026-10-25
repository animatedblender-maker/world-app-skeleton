# MIND phases (developer)

Authoritative gap matrix: `docs/mind/01-gap-matrix.md` (rsync → `apps/api/docs/mind/`).  
Handbook: `docs/mind/Matterya_MIND_Engineering_Handbook.md`.

## Phase 1 — shipped
Ledger reuse (`feed_video_delivery`), events allowlist, candidates, interest (`entity_personality`, `recsys_user_creator_affinity`, `recsys_item_stats`), Masquerade isolation, observability panels, purpose/surfaces catalog.

Policy bumps: `mind.phase1.v3` … `v7`.

## Phase 2a — media features — shipped (`mind.phase2.v1`)
- Table: `public.mind_content_features`
- Source: `video_transcripts` + title/body lexicon topics
- Hook: after `transcribePost` ready → `upsertFeaturesForPost`
- Soft topic boost in `rank.service.ts`
- Commit: `3554fed`

## Phase 2b — embeddings / ANN — shipped (`mind.phase2.v2`)
- Table: `public.mind_content_embeddings` (`vector(1024)`, HNSW cosine)
- Model: `voyage-4-lite` / version string `voyage:voyage-4-lite`
- Source: `title_body`
- Soft ANN boost (~+1.35) via `annCandidates` → lane `home_ann_title`
- Module: `recommendation/mind-embeddings.ts`
- Commits: `cb549f7` (core), `fa44852` (incremental + cron route)

## Deferred
- §14 ads/economy  
- §15 GraphQL FeedItem (ADR 0002 keeps REST for v1)  
- §18 ML eval  
- Visual / multimodal embeds  
- Trained ranker  

## Naming
Do **not** rename live tables to handbook aliases. Show Matterya names beside handbook names on `/mind`.
