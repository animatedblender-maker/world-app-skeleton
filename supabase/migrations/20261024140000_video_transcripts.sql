-- Speech transcripts for Hubs / long-form videos (Groq Whisper, server-side).
-- App stays light: clients only fetch finished text / timed segments.

create table if not exists public.video_transcripts (
  post_id uuid primary key references public.posts (id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'ready', 'failed', 'skipped')),
  language text,
  model text,
  text text,
  segments jsonb,
  error text,
  source text,
  duration_seconds double precision,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists video_transcripts_status_updated_idx
  on public.video_transcripts (status, updated_at desc);

comment on table public.video_transcripts is
  'Automatic speech transcripts for video posts (Groq Whisper). Never ships models in the iOS app.';
