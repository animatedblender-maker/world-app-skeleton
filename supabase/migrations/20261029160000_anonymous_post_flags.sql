-- Masquerade: platform flags + auto reports for human review
-- Flagged posts stay visible (state=active) with a Flagged badge.
-- Open reports feed /reports/masquerade (Remove / Flag / Skip).

alter table anonymous.posts
  add column if not exists flagged_at timestamptz,
  add column if not exists flag_reason text;

create index if not exists anonymous_posts_flagged_at_idx
  on anonymous.posts (flagged_at desc nulls last)
  where flagged_at is not null;

-- System auto-mod has no anonymous profile.
alter table anonymous.reports
  alter column reporter_profile_id drop not null;

create index if not exists anonymous_reports_open_created_idx
  on anonymous.reports (created_at desc)
  where state = 'open';
