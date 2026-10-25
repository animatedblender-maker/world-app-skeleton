# ADR 0004 — Phase 5 scale only after measured need

**Status:** Accepted (Phase 3a scaffolding)  
**Date:** 2026-10-25

## Context

Handbook §21 Phase 5 lists feature store, event-broker hardening, warehouse, ANN cluster, model-serving autoscaling, and multi-region. Building these early adds cost and ops load without proof that the current stack is the bottleneck.

## Decision

1. **Do not** start Phase 5 infrastructure until benchmarks show the current path is limiting (p95 latency, QPS, ANN recall under load, or warehouse lag).
2. Each Phase 5 piece requires its **own ADR** plus a cost projection before implementation.
3. Until then, measure with `/mind` live panels + `scripts/mind-offline-eval.ts` (§18 stub).
4. Preferred order when need appears: (a) warehouse/read replicas for eval, (b) dedicated ANN/search if Voyage+pgvector p95 regresses, (c) model serving only after MIND-016 ships behind a flag.

## Consequences

- Phase 5 stays **roadmap / not built** on `/mind` until evidence lands.
- Engineering effort stays on Phase 3 adaptive intelligence and Phase 4 surfaces.
- Agents must not invent Kubernetes/feature-store work from this ADR alone.
