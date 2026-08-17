# ADR-002: Versioned remote config for kill switches

## Status

Accepted

## Context

Prefetch depth, player pool, thin feed path must be remotely killable without App Store release. At large scale, flags cannot hit Postgres per request.

## Decision

- `GET /v1/config?v=` returns versioned JSON blob.  
- Server caches in-process; clients cache by version.  
- Source of truth: in-code defaults + optional env overrides initially; table later if needed.  
- Contract compatible with future LaunchDarkly/Unleash backends.

## Consequences

- Flag changes may take one TTL (default 60s) to propagate.  
- No per-user targeting in v1 (global + percentage optional later).
