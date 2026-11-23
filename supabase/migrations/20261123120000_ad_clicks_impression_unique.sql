-- One click attribution row per impression (blocks click-farm duplicates).
-- Deduplicate existing rows, keeping the earliest click per impression.

delete from public.ad_clicks a
using public.ad_clicks b
where a.impression_id = b.impression_id
  and a.created_at > b.created_at;

delete from public.ad_clicks a
using public.ad_clicks b
where a.impression_id = b.impression_id
  and a.created_at = b.created_at
  and a.id > b.id;

create unique index if not exists ad_clicks_impression_unique
  on public.ad_clicks (impression_id);

comment on index public.ad_clicks_impression_unique is
  'At most one ad_clicks row per impression_id (Phase 2 T1).';
