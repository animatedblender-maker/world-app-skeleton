alter table public.conversation_members
  add column if not exists archived_at timestamptz,
  add column if not exists deleted_at timestamptz;

create index if not exists conversation_members_inbox_idx
  on public.conversation_members (user_id, archived_at, deleted_at);