-- Separate Masquerade Inbox threads from normal Messages.
-- surface: primary (default) | masquerade
alter table public.conversations
  add column if not exists surface text not null default 'primary';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'conversations_surface_check'
  ) then
    alter table public.conversations
      add constraint conversations_surface_check
      check (surface = any (array['primary'::text, 'masquerade'::text]));
  end if;
end $$;

create index if not exists conversations_surface_idx
  on public.conversations (surface);
