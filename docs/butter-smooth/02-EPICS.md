# Epics (iOS + API)

UI appearance and product expectations stay unchanged. Epics are infrastructure and reliability.

## E0 — Program & gates

- Locked decisions, SLOs, ADR index, 90-day tickets  
- Architecture review template enforced for new sync hops  

## E1 — Observability (Days 1–30)

- Client milestones + batch upload  
- Server accept metrics; Prometheus-friendly export for Grafana  
- Trace ID on critical APIs  
- Inventory: sync chains, OFFSET, N+1, main-thread hotspots  

## E2 — Client platform layer (Days 31–60)

- Shared network client: dedupe, cancel, priority, deadline  
- Entity store + local cache policy (24h feed snapshot rules)  
- Mutation outbox (like/save/follow/mute)  
- Feature flags via `/v1/config`  

## E3 — Feed & lists (Days 31–60)

- Feed session + opaque cursor (no OFFSET)  
- Rank references → batch hydrate  
- Tab state restore (scroll anchor) without visual redesign  
- Bounded window / virtualization already present — harden  

## E4 — Media (Days 61–90)

- Prefetch coordinator (direction/velocity/network)  
- Player pool states (current/next/prev) — no look change  
- Startup telemetry split (manifest / network / decode / first frame)  

## E5 — Messaging

- Local insert &lt; 50 ms (keep)  
- Outbox + idempotency for send  
- Ack path metrics  

## E6 — Search / Profile / Composer

- Search suggestion budget  
- Profile interactive milestone  
- Resumable upload (existing path) + draft durability  

## E7 — SRE / scale (ongoing)

- Deadlines, partial results, kill switches  
- Cache stampede / TTL jitter  
- Load shed priority list  

## E8 — Grafana

- Step-by-step Cloud setup (when agent asks)  
- Dashboards per surface milestone  
