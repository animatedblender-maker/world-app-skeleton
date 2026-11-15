-- Hubs / Studio publish disclosures (YouTube-like Made for kids, promotion, AI).
alter table public.posts
  add column if not exists made_for_kids boolean,
  add column if not exists has_paid_promotion boolean not null default false,
  add column if not exists altered_content boolean not null default false;

comment on column public.posts.made_for_kids is
  'null = unset (legacy); true = made for kids; false = not made for kids';
comment on column public.posts.has_paid_promotion is
  'Creator disclosed paid promotion / sponsorship in the video.';
comment on column public.posts.altered_content is
  'Creator disclosed altered or AI-made content.';
