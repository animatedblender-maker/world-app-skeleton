# Architecture Overview

## Monorepo layout
- `apps/web`: Angular web app.
- `apps/api`: GraphQL API (Node + Express + Yoga).
- `apps/mobile`: Ionic + Capacitor shell (iOS/Android packaging).
- `packages/shared`: shared types and utilities.
- `packages/api-client`: GraphQL operations + typed client (codegen target).
- `supabase/`: database migrations + seed data.
- `infra/docker/`: local Redpanda (Kafka API) + console.

## Event backbone (Kafka / Redpanda)
- Domain events flow via **transactional outbox** (`kafka_outbox`) → Kafka → workers.
- Phase 1: chat `MessageSent` drives push notifications asynchronously.
- See [KAFKA.md](./KAFKA.md) for setup, topics, and cutover modes.

## Principles
- Keep DB changes in `supabase/migrations`.
- Keep shared types in `packages/shared`.
- Keep API contracts in `packages/api-client` (future codegen).
- Keep platform-specific UI in each app.
- Postgres is source of truth; Kafka is integration/fan-out, not a second source of truth.
