-- Migration: Add external news tables and extend posts for news sharing
-- Created: April 1, 2026

-- Create external_news_items table
CREATE TABLE external_news_items (
  id uuid primary key default gen_random_uuid(),
  provider text not null default 'reliefweb',
  provider_item_id text not null,
  title text not null,
  url text not null,
  source_name text,
  published_at timestamptz,
  country_codes text[] not null default '{}',
  country_names text[] not null default '{}',
  disaster_types text[] not null default '{}',
  theme_names text[] not null default '{}',
  format text,
  language text,
  snippet text,
  image_url text,
  raw jsonb not null default '{}'::jsonb,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Indexes for external_news_items
CREATE UNIQUE INDEX idx_external_news_items_provider_item ON external_news_items(provider, provider_item_id);
CREATE INDEX idx_external_news_items_country_codes ON external_news_items USING gin(country_codes);
CREATE INDEX idx_external_news_items_published_at ON external_news_items(published_at desc);

-- Create external_news_comments table
CREATE TABLE external_news_comments (
  id uuid primary key default gen_random_uuid(),
  news_item_id uuid not null references external_news_items(id) on delete cascade,
  parent_id uuid null references external_news_comments(id) on delete cascade,
  author_id uuid not null references auth.users(id),
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Extend posts table with link fields for sharing external news
ALTER TABLE posts ADD COLUMN external_ref_type text;
ALTER TABLE posts ADD COLUMN external_ref_id uuid;
ALTER TABLE posts ADD COLUMN link_url text;
ALTER TABLE posts ADD COLUMN link_title text;
ALTER TABLE posts ADD COLUMN link_source_name text;
ALTER TABLE posts ADD COLUMN link_published_at timestamptz;
ALTER TABLE posts ADD COLUMN link_image_url text;
ALTER TABLE posts ADD COLUMN link_snippet text;

-- Add constraint for external_ref_type
ALTER TABLE posts ADD CONSTRAINT chk_external_ref_type CHECK (external_ref_type IN ('news'));

-- Add foreign key for external_ref_id when type is 'news'
-- Note: Since FK can't be conditional, we'll handle validation in application code
-- For now, add the FK assuming external_ref_id is only set for 'news'
ALTER TABLE posts ADD CONSTRAINT fk_posts_external_news FOREIGN KEY (external_ref_id) REFERENCES external_news_items(id);
