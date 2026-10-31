-- Add servitude (domestic helpers / forced labor) to mod_category check.
do $$
begin
  alter table public.moderation_tickets
    drop constraint if exists moderation_tickets_mod_category_check;
  alter table public.moderation_tickets
    add constraint moderation_tickets_mod_category_check
    check (
      mod_category is null
      or mod_category in (
        'spam', 'harassment', 'hate', 'mature', 'csam', 'solicitation', 'servitude',
        'violence', 'terrorism', 'self_harm', 'misinfo', 'scam', 'doxxing', 'other'
      )
    );
exception when others then
  raise notice 'mod_category check update skipped: %', sqlerrm;
end$$;
