# ADR 0003 — Media features before pgvector

**Status:** Accepted (Phase 2a)  
**Date:** 2026-10-25

## Context

Handbook §7 / `mind_content_embeddings` assumes pgvector ANN. Production Postgres has **no** `vector` extension installed. We already have `public.video_transcripts` (Groq Whisper) with a small ready set.

## Decision

1. Reuse `video_transcripts` as the transcript stage.
2. Store derived rows in `public.mind_content_features` (language, topics lexicon, text fingerprint, pipeline version).
3. Soft-boost Public rank when topics intersect viewer hub bubbles; **never** demote missing transcripts (`UNKNOWN`).
4. Defer `CREATE EXTENSION vector`, embedding jobs, and ANN candidate lanes to **Phase 2b (MIND-012)** after a cost + ops gate.

## Consequences

- Gap matrix §7 can ship as Phase 2a without infra change.
- Topic quality is heuristic until embeddings land.
- Kill-switch: `MIND_MEDIA_FEATURES_ENABLED=false`.
