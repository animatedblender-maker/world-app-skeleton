# Supabase Migrations

This folder is the source of truth for database changes.

## Workflow (recommended)
1. Install the Supabase CLI (once).
2. Link the project to your Supabase instance.
3. Create migrations for every schema/RLS change.

## Common commands
- `supabase db pull` to pull a baseline (use this once to create the initial migration).
- `supabase migration new <name>` to create a new migration.
- `supabase db push` to apply migrations to the linked project.

## Notes
- Keep migrations in `supabase/migrations` only.
- Treat the migrations as immutable history.
- Use a new migration for every change (no edits to old migrations).
