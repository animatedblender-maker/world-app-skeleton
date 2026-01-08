# Architecture Overview

## Monorepo layout
- `apps/web`: Angular web app.
- `apps/api`: GraphQL API (Node + Express + Yoga).
- `apps/mobile`: Ionic + Capacitor shell (iOS/Android packaging).
- `packages/shared`: shared types and utilities.
- `packages/api-client`: GraphQL operations + typed client (codegen target).
- `supabase/`: database migrations + seed data.

## Principles
- Keep DB changes in `supabase/migrations`.
- Keep shared types in `packages/shared`.
- Keep API contracts in `packages/api-client` (future codegen).
- Keep platform-specific UI in each app.
