# Architecture decisions (Matterya)

Living ADRs. Full blueprints: `docs/reference/`.

---

## ADR-001 — Six-plane product architecture

**Status:** Accepted (2026-08-16)  
**Source:** butter-smooth architecture §0

Planes: (1) client experience, (2) edge/delivery, (3) API/domain, (4) data/event, (5) media/realtime/search, (6) reliability/control.

**Implication:** New features must declare plane ownership, cache policy, events, and failure mode before merge.

---

## ADR-002 — Five-plane recommendation architecture

**Status:** Accepted (2026-08-16)  
**Source:** social recommendation roadmap §0

Planes: (1) event/data, (2) feature/representation, (3) candidate/retrieval, (4) ranking/policy, (5) experimentation/observability.

**Implication:** Ranking models never bypass safety/eligibility. Surfaces use explicit policy objects (`RecommendationSurface`).

---

## ADR-003 — Two home policies: Following vs For you

**Status:** Accepted as product target; UI dual-chip optional  
**Source:** recsys roadmap BUILD DECISION §1.1

- **Following:** chronological/affinity, low exploration.  
- **For you:** multi-source discovery + exploration budget + diversity re-rank.

**Current code:** Home uses For you policy composition on top of follow-priority baseline. Explicit Following-only chip can ship when product confirms.

---

## ADR-004 — Immutable IDs under human-readable URLs

**Status:** Accepted  
**Source:** butter-smooth §5

Posts/users use immutable DB IDs; handles/slugs are presentation + redirects only. Never FK on mutable handles.

---

## ADR-005 — Cursor pagination only for dynamic feeds

**Status:** Accepted  
**Source:** butter-smooth §8

No offset pagination for home, Sparks, comments, messages, notifications.

---

## ADR-006 — Engagement as versioned event envelope → Kafka

**Status:** Accepted  
**Source:** recsys §2 + existing `docs/KAFKA.md`

Client batches events to `/v1/engagement/batch` → Postgres + outbox → `matterya.engagement`.  
Schema version carried in meta (`schemaVersion=1`). Impression ≠ viewport; both are logged.

---

## ADR-007 — Complexity only after measurement

**Status:** Accepted  
**Source:** both docs

No two-tower / foundation models until event quality, warehouse, and A/B platform exist. Phase 0 deterministic + composition engine first.

---

## ADR-008 — Direct media delivery (not API proxy)

**Status:** Accepted (in progress)  
**Source:** butter-smooth Phase 2

R2 public/signed playback; API coordinates metadata only. Upload pipeline remains resumable-target.
