# 90-day ticket backlog

Format: `ID | Epic | Title | Depends | Ship gate | Your action?`

## Days 1–30

| ID | Epic | Title | Depends | Gate | You? |
|----|------|-------|---------|------|------|
| BS-001 | E0 | Program pack (this folder) | — | docs exist | — |
| BS-002 | E1 | iOS PerformanceTelemetry milestones | BS-001 | events emit on start/feed | — |
| BS-003 | E1 | API POST /v1/metrics/batch | BS-001 | 200 + accepted count | **push ios-native** |
| BS-004 | E1 | Wire shell + feed milestones (no UI change) | BS-002 | cold start metrics | smoke phone |
| BS-005 | E1 | GET /v1/config flags | BS-001 | client reads version | **push** |
| BS-006 | E1 | Inventory doc: sync hops / N+1 / OFFSET | BS-001 | written | — |
| BS-007 | E8 | Grafana Cloud step 1 (account) | BS-003 | you have URL | **done** |
| BS-008 | E8 | Grafana Step 3 dashboard import | BS-007 | `Matterya Butter-Smooth SLOs` live | **done** (owner confirmed) |

## Days 31–60

| ID | Epic | Title | Depends | Gate | You? |
|----|------|-------|---------|------|------|
| BS-010 | E2 | Network cancel/dedupe layer | BS-005 | cancel on nav | — |
| BS-011 | E2 | Mutation outbox like/save/follow | BS-005 | offline kill-reopen test | migration if needed |
| BS-012 | E2 | Idempotency middleware API | BS-011 | duplicate key safe | migration |
| BS-013 | E3 | Feed session + opaque cursor | BS-005 | no OFFSET path | — |
| BS-014 | E3 | Batch hydrate posts | BS-013 | 1 batch/page | — |
| BS-015 | E3 | Tab scroll anchor restore | BS-013 | return to same offset | smoke |
| BS-016 | E5 | Message outbox same module | BS-011 | local &lt;50ms + ack | — |

## Days 61–90

| ID | Epic | Title | Depends | Gate | You? |
|----|------|-------|---------|------|------|
| BS-020 | E4 | Prefetch coordinator + kill flag | BS-005 | tunable | — |
| BS-021 | E4 | Player pool (no UI redesign) | BS-020 | rebuffer metrics | — |
| BS-022 | E4 | Video startup breakdown telemetry | BS-021 | dashboard | — |
| BS-023 | E7 | Deadline budgets on feed rank/hydrate | BS-014 | partial OK | — |
| BS-024 | E7 | Cache stampede / TTL jitter doc+code | BS-014 | — | — |
| BS-025 | E0 | Architecture review checklist enforced | all | PR template | — |
| BS-026 | E1 | iPhone 11 30-min scroll memory gate | BS-004 | no linear growth | **you run** |

## P0 interrupt rule

Any P0 (crash, auth wrong, black media, data loss) jumps the queue; foundations resume after.
