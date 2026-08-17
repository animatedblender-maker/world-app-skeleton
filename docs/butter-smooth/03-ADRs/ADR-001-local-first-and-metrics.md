# ADR-001: Local-first launch + client metrics pipeline

## Status

Accepted (program start)

## Context

Returning users must not wait on network for shell. Product metrics require user-perceived milestones, not only server latency.

## Decision

1. Hydrate session from disk in `AppState.init` (already shipped).  
2. Feed first paint from local snapshot (max 24h); soft-refresh without blanking.  
3. Emit milestones via `PerformanceTelemetry` → `POST /v1/metrics/batch`.  
4. Grafana is the human dashboard; API stores short-term aggregates until remote_write is wired.

## Consequences

- Slight risk of stale first paint (mitigated by soft-refresh + privacy invalidation).  
- Metrics volume must be sampled/batched (client: max ~40 events/flush).
