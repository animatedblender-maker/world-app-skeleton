-- Idempotent ads revshare credits: one ledger row per ad impression.
create unique index if not exists studio_earn_ledger_source_ref_uidx
  on public.studio_earn_ledger (source_ref)
  where source_ref is not null and length(trim(source_ref)) > 0;
