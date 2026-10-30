-- Masquerade Spaces cleanup:
--   archive fake starter Spaces (general/advice/…)
--   add secrets (r/offmychest-shaped) + HighlyStrange (r/Paranormal-shaped)
--   ensure post media + import source_ref columns
-- Safe to re-run.

-- ── Post media (idempotent; same as 20261023140000) ─────────────────────────
alter table anonymous.posts add column if not exists media_type text;
alter table anonymous.posts add column if not exists media_url text;
alter table anonymous.posts add column if not exists thumb_url text;
alter table anonymous.posts add column if not exists source_ref text;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'anonymous_posts_media_type_check'
  ) then
    alter table anonymous.posts
      add constraint anonymous_posts_media_type_check
      check (media_type is null or media_type in ('image', 'video', 'gif'));
  end if;
end $$;

-- Multiple NULLs allowed; non-null source_ref values are unique (import idempotency).
create unique index if not exists anonymous_posts_source_ref_uidx
  on anonymous.posts (source_ref);

-- ── Archive fake seed Spaces (hidden from active directory) ─────────────────
update anonymous.spaces
set status = 'archived',
    updated_at = now()
where normalized_slug in (
  'general', 'advice', 'creative', 'tech', 'wellness', 'offbeat', 'careers', 'books'
)
  and status = 'active';

-- ── secrets ─────────────────────────────────────────────────────────────────
insert into anonymous.spaces (
  slug, normalized_slug, title, description, category, tags,
  visibility, admission, billing_mode, status, language
)
values (
  'secrets',
  'secrets',
  'secrets',
  'Anonymous confessions and things you needed to say out loud. Leave your identity outside.',
  'confessions',
  array['secrets', 'confessions', 'offmychest'],
  'adult_public',
  'free',
  'free',
  'active',
  'en'
)
on conflict (normalized_slug) do update
set title = excluded.title,
    description = excluded.description,
    category = excluded.category,
    tags = excluded.tags,
    visibility = excluded.visibility,
    admission = excluded.admission,
    billing_mode = excluded.billing_mode,
    status = 'active',
    updated_at = now();

-- ── HighlyStrange ───────────────────────────────────────────────────────────
insert into anonymous.spaces (
  slug, normalized_slug, title, description, category, tags,
  visibility, admission, billing_mode, status, language
)
values (
  'HighlyStrange',
  'highlystrange',
  'HighlyStrange',
  'Paranormal encounters, unexplained events, and highly strange stories — told under a mask.',
  'paranormal',
  array['paranormal', 'strange', 'unexplained'],
  'adult_public',
  'free',
  'free',
  'active',
  'en'
)
on conflict (normalized_slug) do update
set title = excluded.title,
    description = excluded.description,
    category = excluded.category,
    tags = excluded.tags,
    visibility = excluded.visibility,
    admission = excluded.admission,
    billing_mode = excluded.billing_mode,
    status = 'active',
    updated_at = now();

-- ── Rules for the two new Spaces (skip if already present) ──────────────────
insert into anonymous.space_rules (space_id, position, text, version)
select s.id, r.position, r.text, 1
from anonymous.spaces s
cross join (
  values
    (0, 'Be 18+. This entire section is adult-only.'),
    (1, 'No doxxing, threats, scams, or illegal content.'),
    (2, 'Do not share real names, contact info, or your ordinary Matterya identity.'),
    (3, 'Report abuse. Blocking and reporting are available to everyone.'),
    (4, 'Keep it real for this Space — confessions stay kind to bystanders; strange stories stay sincere.')
) as r(position, text)
where s.normalized_slug in ('secrets', 'highlystrange')
  and not exists (
    select 1 from anonymous.space_rules sr where sr.space_id = s.id
  );

-- ── Seed bot profile for imported archive posts (no account_id required) ────
insert into anonymous.profiles (
  username, normalized_username, avatar_seed, state, age_attested_at
)
values (
  'archive_whisper',
  'archive_whisper',
  'seed-archive-whisper-v1',
  'active',
  now()
)
on conflict (normalized_username) do nothing;
