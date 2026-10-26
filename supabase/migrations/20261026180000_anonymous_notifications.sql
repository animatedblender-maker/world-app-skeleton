-- Masquerade in-app notifications (replies, mentions, space alerts).
-- Separate from public.notifications (Matterya social).

create table if not exists anonymous.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_profile_id uuid not null references anonymous.profiles (id) on delete cascade,
  actor_profile_id uuid references anonymous.profiles (id) on delete set null,
  kind text not null,
  title text,
  body text,
  space_id uuid references anonymous.spaces (id) on delete set null,
  post_id uuid references anonymous.posts (id) on delete cascade,
  comment_id uuid references anonymous.comments (id) on delete set null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists anonymous_notifications_recipient_created_idx
  on anonymous.notifications (recipient_profile_id, created_at desc);

create index if not exists anonymous_notifications_recipient_unread_idx
  on anonymous.notifications (recipient_profile_id)
  where read_at is null;

comment on table anonymous.notifications is
  'Masquerade-only alerts (replies etc). Never mix with Matterya social notifications.';
