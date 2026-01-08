drop extension if exists "pg_net";


  create table "public"."categories" (
    "id" uuid not null default gen_random_uuid(),
    "slug" text not null,
    "title" text not null,
    "description" text,
    "icon" text,
    "is_global" boolean not null default true,
    "country_code" text,
    "created_by" uuid,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."categories" enable row level security;


  create table "public"."interactions" (
    "id" uuid not null default gen_random_uuid(),
    "actor_id" uuid not null default auth.uid(),
    "type" text not null,
    "country_id" integer,
    "country_code" text,
    "entity_type" text,
    "entity_id" uuid,
    "payload" jsonb,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."interactions" enable row level security;


  create table "public"."notifications" (
    "id" uuid not null default gen_random_uuid(),
    "user_id" uuid not null,
    "actor_id" uuid,
    "type" text not null,
    "entity_type" text,
    "entity_id" uuid,
    "payload" jsonb,
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."notifications" enable row level security;


  create table "public"."post_bookmarks" (
    "user_id" uuid not null,
    "post_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."post_bookmarks" enable row level security;


  create table "public"."post_comments" (
    "id" uuid not null default gen_random_uuid(),
    "post_id" uuid not null,
    "author_id" uuid not null,
    "body" text not null,
    "parent_id" uuid,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."post_comments" enable row level security;


  create table "public"."post_deletes" (
    "id" uuid not null default gen_random_uuid(),
    "original_post_id" uuid not null,
    "deleted_by" uuid not null,
    "deleted_at" timestamp with time zone not null default now(),
    "author_id" uuid not null,
    "category_id" uuid not null,
    "country_name" text not null,
    "country_code" text,
    "city_name" text,
    "title" text,
    "body" text,
    "media_type" text not null,
    "media_url" text,
    "thumb_url" text,
    "visibility" text not null,
    "like_count" integer not null,
    "comment_count" integer not null,
    "created_at" timestamp with time zone not null,
    "updated_at" timestamp with time zone not null,
    "media_path" text,
    "thumb_path" text
      );



  create table "public"."post_likes" (
    "post_id" uuid not null,
    "user_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."post_likes" enable row level security;


  create table "public"."post_reports" (
    "id" uuid not null default gen_random_uuid(),
    "post_id" uuid not null,
    "reporter_id" uuid not null,
    "reason" text not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."post_reports" enable row level security;


  create table "public"."posts" (
    "id" uuid not null default gen_random_uuid(),
    "author_id" uuid not null,
    "category_id" uuid not null,
    "country_name" text not null,
    "country_code" text,
    "city_name" text,
    "title" text,
    "body" text,
    "media_type" text not null default 'none'::text,
    "media_url" text,
    "thumb_url" text,
    "visibility" text not null default 'public'::text,
    "like_count" integer not null default 0,
    "comment_count" integer not null default 0,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "media_path" text,
    "thumb_path" text
      );


alter table "public"."posts" enable row level security;


  create table "public"."presence" (
    "user_id" uuid not null,
    "country_code" text,
    "last_seen_at" timestamp with time zone not null default now(),
    "country_id" integer,
    "country_name" text,
    "city_name" text,
    "last_seen" timestamp with time zone not null default now(),
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "country_iso" text
      );


alter table "public"."presence" enable row level security;


  create table "public"."profiles" (
    "user_id" uuid not null,
    "email" text,
    "display_name" text,
    "username" text,
    "avatar_url" text,
    "country_name" text not null,
    "country_code" text,
    "city_name" text,
    "bio" text,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now(),
    "last_seen" timestamp with time zone
      );


alter table "public"."profiles" enable row level security;


  create table "public"."user_follows" (
    "follower_id" uuid not null,
    "following_id" uuid not null,
    "created_at" timestamp with time zone not null default now()
      );


alter table "public"."user_follows" enable row level security;


  create table "public"."user_location_precise" (
    "user_id" uuid not null,
    "lat" double precision not null,
    "lng" double precision not null,
    "accuracy_m" integer,
    "consent_given_at" timestamp with time zone not null default now(),
    "expires_at" timestamp with time zone not null,
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."user_location_precise" enable row level security;


  create table "public"."user_presence" (
    "user_id" uuid not null,
    "country_code" text,
    "country_name" text,
    "city_name" text,
    "last_seen_at" timestamp with time zone not null default now(),
    "is_online" boolean not null default true,
    "created_at" timestamp with time zone not null default now(),
    "updated_at" timestamp with time zone not null default now()
      );


alter table "public"."user_presence" enable row level security;

CREATE INDEX bookmarks_post_idx ON public.post_bookmarks USING btree (post_id);

CREATE INDEX bookmarks_user_idx ON public.post_bookmarks USING btree (user_id);

CREATE INDEX categories_country_idx ON public.categories USING btree (country_code);

CREATE UNIQUE INDEX categories_pkey ON public.categories USING btree (id);

CREATE UNIQUE INDEX categories_slug_key ON public.categories USING btree (slug);

CREATE INDEX follows_follower_idx ON public.user_follows USING btree (follower_id);

CREATE INDEX follows_following_idx ON public.user_follows USING btree (following_id);

CREATE INDEX idx_posts_category ON public.posts USING btree (category_id);

CREATE INDEX idx_posts_country_code ON public.posts USING btree (country_code);

CREATE INDEX idx_posts_created_at ON public.posts USING btree (created_at DESC);

CREATE INDEX idx_presence_country ON public.user_presence USING btree (country_code);

CREATE INDEX idx_presence_country_iso ON public.presence USING btree (country_iso);

CREATE INDEX idx_presence_last_seen ON public.user_presence USING btree (last_seen_at DESC);

CREATE INDEX idx_user_presence_country ON public.user_presence USING btree (country_code);

CREATE INDEX idx_user_presence_last_seen ON public.user_presence USING btree (last_seen_at DESC);

CREATE INDEX idx_user_presence_online ON public.user_presence USING btree (is_online);

CREATE UNIQUE INDEX interactions_pkey ON public.interactions USING btree (id);

CREATE UNIQUE INDEX notifications_pkey ON public.notifications USING btree (id);

CREATE INDEX notifications_user_id_created_at_idx ON public.notifications USING btree (user_id, created_at DESC);

CREATE INDEX notifications_user_id_read_at_idx ON public.notifications USING btree (user_id, read_at);

CREATE UNIQUE INDEX post_bookmarks_pkey ON public.post_bookmarks USING btree (user_id, post_id);

CREATE INDEX post_comments_author_idx ON public.post_comments USING btree (author_id);

CREATE INDEX post_comments_created_idx ON public.post_comments USING btree (created_at DESC);

CREATE UNIQUE INDEX post_comments_pkey ON public.post_comments USING btree (id);

CREATE INDEX post_comments_post_idx ON public.post_comments USING btree (post_id);

CREATE INDEX post_deletes_original_post_id_idx ON public.post_deletes USING btree (original_post_id);

CREATE UNIQUE INDEX post_deletes_pkey ON public.post_deletes USING btree (id);

CREATE UNIQUE INDEX post_likes_pkey ON public.post_likes USING btree (post_id, user_id);

CREATE INDEX post_likes_post_idx ON public.post_likes USING btree (post_id);

CREATE INDEX post_likes_user_idx ON public.post_likes USING btree (user_id);

CREATE UNIQUE INDEX post_reports_pkey ON public.post_reports USING btree (id);

CREATE INDEX posts_author_idx ON public.posts USING btree (author_id);

CREATE INDEX posts_category_idx ON public.posts USING btree (category_id);

CREATE INDEX posts_country_code_idx ON public.posts USING btree (country_code);

CREATE INDEX posts_country_idx ON public.posts USING btree (country_code);

CREATE INDEX posts_created_idx ON public.posts USING btree (created_at DESC);

CREATE UNIQUE INDEX posts_pkey ON public.posts USING btree (id);

CREATE INDEX presence_country_id_idx ON public.presence USING btree (country_id);

CREATE INDEX presence_country_idx ON public.user_presence USING btree (country_code);

CREATE INDEX presence_country_iso_idx ON public.presence USING btree (country_iso);

CREATE INDEX presence_country_last_seen_idx ON public.presence USING btree (country_code, last_seen_at DESC);

CREATE INDEX presence_last_seen_idx ON public.user_presence USING btree (last_seen_at DESC);

CREATE UNIQUE INDEX presence_pkey ON public.presence USING btree (user_id);

CREATE INDEX profiles_city_idx ON public.profiles USING btree (city_name);

CREATE INDEX profiles_country_code_idx ON public.profiles USING btree (country_code);

CREATE INDEX profiles_country_idx ON public.profiles USING btree (country_code);

CREATE INDEX profiles_last_seen_idx ON public.profiles USING btree (last_seen);

CREATE UNIQUE INDEX profiles_pkey ON public.profiles USING btree (user_id);

CREATE UNIQUE INDEX profiles_username_key ON public.profiles USING btree (username);

CREATE INDEX user_follows_following_idx ON public.user_follows USING btree (following_id);

CREATE UNIQUE INDEX user_follows_pkey ON public.user_follows USING btree (follower_id, following_id);

CREATE INDEX user_location_expires_idx ON public.user_location_precise USING btree (expires_at);

CREATE UNIQUE INDEX user_location_precise_pkey ON public.user_location_precise USING btree (user_id);

CREATE UNIQUE INDEX user_presence_pkey ON public.user_presence USING btree (user_id);

alter table "public"."categories" add constraint "categories_pkey" PRIMARY KEY using index "categories_pkey";

alter table "public"."interactions" add constraint "interactions_pkey" PRIMARY KEY using index "interactions_pkey";

alter table "public"."notifications" add constraint "notifications_pkey" PRIMARY KEY using index "notifications_pkey";

alter table "public"."post_bookmarks" add constraint "post_bookmarks_pkey" PRIMARY KEY using index "post_bookmarks_pkey";

alter table "public"."post_comments" add constraint "post_comments_pkey" PRIMARY KEY using index "post_comments_pkey";

alter table "public"."post_deletes" add constraint "post_deletes_pkey" PRIMARY KEY using index "post_deletes_pkey";

alter table "public"."post_likes" add constraint "post_likes_pkey" PRIMARY KEY using index "post_likes_pkey";

alter table "public"."post_reports" add constraint "post_reports_pkey" PRIMARY KEY using index "post_reports_pkey";

alter table "public"."posts" add constraint "posts_pkey" PRIMARY KEY using index "posts_pkey";

alter table "public"."presence" add constraint "presence_pkey" PRIMARY KEY using index "presence_pkey";

alter table "public"."profiles" add constraint "profiles_pkey" PRIMARY KEY using index "profiles_pkey";

alter table "public"."user_follows" add constraint "user_follows_pkey" PRIMARY KEY using index "user_follows_pkey";

alter table "public"."user_location_precise" add constraint "user_location_precise_pkey" PRIMARY KEY using index "user_location_precise_pkey";

alter table "public"."user_presence" add constraint "user_presence_pkey" PRIMARY KEY using index "user_presence_pkey";

alter table "public"."categories" add constraint "categories_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL not valid;

alter table "public"."categories" validate constraint "categories_created_by_fkey";

alter table "public"."categories" add constraint "categories_scope_check" CHECK ((((is_global = true) AND (country_code IS NULL)) OR ((is_global = false) AND (country_code IS NOT NULL)))) not valid;

alter table "public"."categories" validate constraint "categories_scope_check";

alter table "public"."categories" add constraint "categories_slug_key" UNIQUE using index "categories_slug_key";

alter table "public"."notifications" add constraint "notifications_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES auth.users(id) ON DELETE SET NULL not valid;

alter table "public"."notifications" validate constraint "notifications_actor_id_fkey";

alter table "public"."notifications" add constraint "notifications_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."notifications" validate constraint "notifications_user_id_fkey";

alter table "public"."post_bookmarks" add constraint "post_bookmarks_post_id_fkey" FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE not valid;

alter table "public"."post_bookmarks" validate constraint "post_bookmarks_post_id_fkey";

alter table "public"."post_bookmarks" add constraint "post_bookmarks_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."post_bookmarks" validate constraint "post_bookmarks_user_id_fkey";

alter table "public"."post_comments" add constraint "post_comments_author_id_fkey" FOREIGN KEY (author_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."post_comments" validate constraint "post_comments_author_id_fkey";

alter table "public"."post_comments" add constraint "post_comments_body_check" CHECK (((char_length(body) >= 1) AND (char_length(body) <= 5000))) not valid;

alter table "public"."post_comments" validate constraint "post_comments_body_check";

alter table "public"."post_comments" add constraint "post_comments_parent_id_fkey" FOREIGN KEY (parent_id) REFERENCES public.post_comments(id) ON DELETE SET NULL not valid;

alter table "public"."post_comments" validate constraint "post_comments_parent_id_fkey";

alter table "public"."post_comments" add constraint "post_comments_post_id_fkey" FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE not valid;

alter table "public"."post_comments" validate constraint "post_comments_post_id_fkey";

alter table "public"."post_deletes" add constraint "post_deletes_deleted_by_fkey" FOREIGN KEY (deleted_by) REFERENCES auth.users(id) not valid;

alter table "public"."post_deletes" validate constraint "post_deletes_deleted_by_fkey";

alter table "public"."post_likes" add constraint "post_likes_post_id_fkey" FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE not valid;

alter table "public"."post_likes" validate constraint "post_likes_post_id_fkey";

alter table "public"."post_likes" add constraint "post_likes_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."post_likes" validate constraint "post_likes_user_id_fkey";

alter table "public"."post_reports" add constraint "post_reports_post_id_fkey" FOREIGN KEY (post_id) REFERENCES public.posts(id) ON DELETE CASCADE not valid;

alter table "public"."post_reports" validate constraint "post_reports_post_id_fkey";

alter table "public"."post_reports" add constraint "post_reports_reason_check" CHECK (((char_length(reason) >= 1) AND (char_length(reason) <= 2000))) not valid;

alter table "public"."post_reports" validate constraint "post_reports_reason_check";

alter table "public"."post_reports" add constraint "post_reports_reporter_id_fkey" FOREIGN KEY (reporter_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."post_reports" validate constraint "post_reports_reporter_id_fkey";

alter table "public"."posts" add constraint "posts_author_id_fkey" FOREIGN KEY (author_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."posts" validate constraint "posts_author_id_fkey";

alter table "public"."posts" add constraint "posts_category_id_fkey" FOREIGN KEY (category_id) REFERENCES public.categories(id) ON DELETE RESTRICT not valid;

alter table "public"."posts" validate constraint "posts_category_id_fkey";

alter table "public"."posts" add constraint "posts_media_type_check" CHECK ((media_type = ANY (ARRAY['none'::text, 'image'::text, 'video'::text, 'link'::text]))) not valid;

alter table "public"."posts" validate constraint "posts_media_type_check";

alter table "public"."posts" add constraint "posts_visibility_check" CHECK ((visibility = ANY (ARRAY['public'::text, 'country'::text, 'followers'::text, 'private'::text]))) not valid;

alter table "public"."posts" validate constraint "posts_visibility_check";

alter table "public"."profiles" add constraint "profiles_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."profiles" validate constraint "profiles_user_id_fkey";

alter table "public"."profiles" add constraint "profiles_username_key" UNIQUE using index "profiles_username_key";

alter table "public"."user_follows" add constraint "user_follows_check" CHECK ((follower_id <> following_id)) not valid;

alter table "public"."user_follows" validate constraint "user_follows_check";

alter table "public"."user_follows" add constraint "user_follows_follower_id_fkey" FOREIGN KEY (follower_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."user_follows" validate constraint "user_follows_follower_id_fkey";

alter table "public"."user_follows" add constraint "user_follows_following_id_fkey" FOREIGN KEY (following_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."user_follows" validate constraint "user_follows_following_id_fkey";

alter table "public"."user_location_precise" add constraint "user_location_precise_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."user_location_precise" validate constraint "user_location_precise_user_id_fkey";

alter table "public"."user_presence" add constraint "user_presence_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE not valid;

alter table "public"."user_presence" validate constraint "user_presence_user_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
begin
  insert into public.profiles (user_id, email, country_name)
  values (new.id, new.email, 'Unknown')
  on conflict (user_id) do nothing;

  insert into public.user_presence (user_id, country_name, last_seen_at, is_online)
  values (new.id, 'Unknown', now(), true)
  on conflict (user_id) do nothing;

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_display_name text;
  v_username text;
  v_country_code text;
  v_country_name text;
  v_city_name text;
  v_avatar_url text;
  v_bio text;
begin
  v_display_name :=
    coalesce(
      nullif(new.raw_user_meta_data->>'display_name', ''),
      split_part(coalesce(new.email, ''), '@', 1),
      'New User'
    );

  v_username := nullif(new.raw_user_meta_data->>'username', '');

  v_country_code := upper(nullif(new.raw_user_meta_data->>'country_code', ''));
  v_country_name := nullif(new.raw_user_meta_data->>'country_name', '');

  v_city_name := nullif(new.raw_user_meta_data->>'city_name', '');
  v_avatar_url := nullif(new.raw_user_meta_data->>'avatar_url', '');
  v_bio := nullif(new.raw_user_meta_data->>'bio', '');

  -- country_name is NOT NULL in your schema, so we must always provide something
  if v_country_name is null then
    v_country_name := 'Unknown';
  end if;

  insert into public.profiles (
    user_id, email, display_name, username,
    avatar_url, country_name, country_code, city_name, bio
  )
  values (
    new.id, new.email, v_display_name, v_username,
    v_avatar_url, v_country_name, v_country_code, v_city_name, v_bio
  )
  on conflict (user_id) do update
    set email        = excluded.email,
        display_name = excluded.display_name,
        username     = coalesce(excluded.username, public.profiles.username),
        avatar_url   = coalesce(excluded.avatar_url, public.profiles.avatar_url),
        country_name = coalesce(excluded.country_name, public.profiles.country_name),
        country_code = coalesce(excluded.country_code, public.profiles.country_code),
        city_name    = coalesce(excluded.city_name, public.profiles.city_name),
        bio          = coalesce(excluded.bio, public.profiles.bio),
        updated_at   = now();

  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.on_comment_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if (tg_op = 'INSERT') then
    update public.posts set comment_count = comment_count + 1 where id = new.post_id;
  elsif (tg_op = 'DELETE') then
    update public.posts set comment_count = greatest(comment_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.on_like_change()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if (tg_op = 'INSERT') then
    update public.posts set like_count = like_count + 1 where id = new.post_id;
  elsif (tg_op = 'DELETE') then
    update public.posts set like_count = greatest(like_count - 1, 0) where id = old.post_id;
  end if;
  return null;
end;
$function$
;

create or replace view "public"."online_users_per_country" as  SELECT COALESCE(country_code, ''::text) AS country_code,
    COALESCE(country_name, ''::text) AS country_name,
    (count(*))::integer AS online_count
   FROM public.user_presence
  WHERE ((is_online = true) AND (last_seen_at > (now() - '00:05:00'::interval)))
  GROUP BY country_code, country_name
  ORDER BY ((count(*))::integer) DESC;


create or replace view "public"."post_comment_counts" as  SELECT post_id,
    (count(*))::integer AS comment_count
   FROM public.post_comments
  GROUP BY post_id;


create or replace view "public"."post_like_counts" as  SELECT post_id,
    (count(*))::integer AS like_count
   FROM public.post_likes
  GROUP BY post_id;


create or replace view "public"."posts_per_category" as  SELECT c.slug,
    c.title,
    (count(p.id))::integer AS post_count
   FROM (public.categories c
     LEFT JOIN public.posts p ON (((p.category_id = c.id) AND (p.visibility = 'public'::text))))
  GROUP BY c.slug, c.title
  ORDER BY ((count(p.id))::integer) DESC;


create or replace view "public"."posts_per_country" as  SELECT COALESCE(country_code, ''::text) AS country_code,
    COALESCE(country_name, ''::text) AS country_name,
    (count(*))::integer AS post_count
   FROM public.posts
  WHERE (visibility = 'public'::text)
  GROUP BY country_code, country_name
  ORDER BY ((count(*))::integer) DESC;


CREATE OR REPLACE FUNCTION public.rpc_online_per_country()
 RETURNS TABLE(country_name text, country_code text, online_count integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    coalesce(up.country_name,'') as country_name,
    coalesce(up.country_code,'') as country_code,
    count(*)::int as online_count
  from public.user_presence up
  where up.is_online = true
    and up.last_seen_at > now() - interval '2 minutes'
  group by up.country_name, up.country_code
  order by online_count desc;
$function$
;

CREATE OR REPLACE FUNCTION public.rpc_users_per_country()
 RETURNS TABLE(country_name text, country_code text, user_count integer)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    p.country_name,
    coalesce(p.country_code,'') as country_code,
    count(*)::int as user_count
  from public.profiles p
  group by p.country_name, p.country_code
  order by user_count desc;
$function$
;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.sync_post_comment_count()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if (tg_op = 'INSERT') then
    update public.posts
    set comment_count = comment_count + 1
    where id = new.post_id;
    return new;
  elsif (tg_op = 'DELETE') then
    update public.posts
    set comment_count = greatest(comment_count - 1, 0)
    where id = old.post_id;
    return old;
  end if;
  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.sync_post_like_count()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  if (tg_op = 'INSERT') then
    update public.posts
    set like_count = like_count + 1
    where id = new.post_id;
    return new;
  elsif (tg_op = 'DELETE') then
    update public.posts
    set like_count = greatest(like_count - 1, 0)
    where id = old.post_id;
    return old;
  end if;
  return null;
end;
$function$
;

create or replace view "public"."user_follow_counts" as  SELECT id AS user_id,
    ( SELECT (count(*))::integer AS count
           FROM public.user_follows f
          WHERE (f.following_id = u.id)) AS follower_count,
    ( SELECT (count(*))::integer AS count
           FROM public.user_follows f
          WHERE (f.follower_id = u.id)) AS following_count
   FROM auth.users u;


create or replace view "public"."users_per_country" as  SELECT country_name,
    COALESCE(country_code, ''::text) AS country_code,
    (count(*))::integer AS user_count
   FROM public.profiles
  GROUP BY country_name, country_code
  ORDER BY ((count(*))::integer) DESC;


create or replace view "public"."v_country_counts" as  SELECT COALESCE(country_code, 'ZZ'::text) AS country_code,
    (count(*))::integer AS total_users,
    (count(*) FILTER (WHERE (is_online = true)))::integer AS online_now
   FROM public.user_presence
  GROUP BY COALESCE(country_code, 'ZZ'::text);


create or replace view "public"."v_global_counts" as  SELECT (count(*))::integer AS total_users,
    (count(*) FILTER (WHERE (is_online = true)))::integer AS online_now
   FROM public.user_presence;


grant select on table "public"."profiles" to "anon";

grant select on table "public"."profiles" to "authenticated";

grant select on table "public"."user_presence" to "anon";

grant insert on table "public"."user_presence" to "authenticated";

grant select on table "public"."user_presence" to "authenticated";

grant update on table "public"."user_presence" to "authenticated";


  create policy "categories read"
  on "public"."categories"
  as permissive
  for select
  to authenticated
using (true);



  create policy "categories select auth"
  on "public"."categories"
  as permissive
  for select
  to authenticated
using (true);



  create policy "categories_delete_own"
  on "public"."categories"
  as permissive
  for delete
  to authenticated
using ((auth.uid() = created_by));



  create policy "categories_insert_authed"
  on "public"."categories"
  as permissive
  for insert
  to public
with check (((auth.uid() IS NOT NULL) AND (created_by = auth.uid())));



  create policy "categories_select_authed"
  on "public"."categories"
  as permissive
  for select
  to authenticated
using (true);



  create policy "categories_select_public"
  on "public"."categories"
  as permissive
  for select
  to public
using (true);



  create policy "categories_update_own"
  on "public"."categories"
  as permissive
  for update
  to public
using ((created_by = auth.uid()))
with check ((created_by = auth.uid()));



  create policy "interactions_insert_own"
  on "public"."interactions"
  as permissive
  for insert
  to authenticated
with check ((actor_id = auth.uid()));



  create policy "interactions_select_own"
  on "public"."interactions"
  as permissive
  for select
  to authenticated
using ((actor_id = auth.uid()));



  create policy "notifications_insert_service"
  on "public"."notifications"
  as permissive
  for insert
  to public
with check ((auth.role() = 'service_role'::text));



  create policy "notifications_select_own"
  on "public"."notifications"
  as permissive
  for select
  to public
using ((auth.uid() = user_id));



  create policy "notifications_update_own"
  on "public"."notifications"
  as permissive
  for update
  to public
using ((auth.uid() = user_id))
with check ((auth.uid() = user_id));



  create policy "bookmarks_delete_own"
  on "public"."post_bookmarks"
  as permissive
  for delete
  to public
using ((auth.uid() = user_id));



  create policy "bookmarks_insert_own"
  on "public"."post_bookmarks"
  as permissive
  for insert
  to public
with check ((auth.uid() = user_id));



  create policy "bookmarks_select_own"
  on "public"."post_bookmarks"
  as permissive
  for select
  to public
using ((auth.uid() = user_id));



  create policy "post_bookmarks_delete_own"
  on "public"."post_bookmarks"
  as permissive
  for delete
  to authenticated
using ((auth.uid() = user_id));



  create policy "post_bookmarks_insert_own"
  on "public"."post_bookmarks"
  as permissive
  for insert
  to authenticated
with check ((auth.uid() = user_id));



  create policy "post_bookmarks_select_own"
  on "public"."post_bookmarks"
  as permissive
  for select
  to authenticated
using ((auth.uid() = user_id));



  create policy "comments_delete_own"
  on "public"."post_comments"
  as permissive
  for delete
  to public
using ((auth.uid() = author_id));



  create policy "comments_insert_authed"
  on "public"."post_comments"
  as permissive
  for insert
  to public
with check ((auth.uid() = author_id));



  create policy "comments_insert_if_can_read_post"
  on "public"."post_comments"
  as permissive
  for insert
  to public
with check (((auth.uid() = author_id) AND (EXISTS ( SELECT 1
   FROM public.posts p
  WHERE ((p.id = post_comments.post_id) AND ((p.visibility = 'public'::text) OR ((p.visibility = 'private'::text) AND (p.author_id = auth.uid())) OR ((p.visibility = 'country'::text) AND (EXISTS ( SELECT 1
           FROM public.profiles pr
          WHERE ((pr.user_id = auth.uid()) AND (pr.country_code = p.country_code)))))))))));



  create policy "comments_select_allowed"
  on "public"."post_comments"
  as permissive
  for select
  to public
using (true);



  create policy "comments_select_if_can_read_post"
  on "public"."post_comments"
  as permissive
  for select
  to public
using ((EXISTS ( SELECT 1
   FROM public.posts p
  WHERE ((p.id = post_comments.post_id) AND ((p.visibility = 'public'::text) OR ((p.visibility = 'private'::text) AND (p.author_id = auth.uid())) OR ((p.visibility = 'country'::text) AND (auth.uid() IS NOT NULL) AND (EXISTS ( SELECT 1
           FROM public.profiles pr
          WHERE ((pr.user_id = auth.uid()) AND (pr.country_code = p.country_code))))))))));



  create policy "comments_update_own"
  on "public"."post_comments"
  as permissive
  for update
  to public
using ((auth.uid() = author_id))
with check ((auth.uid() = author_id));



  create policy "post_comments_delete_own"
  on "public"."post_comments"
  as permissive
  for delete
  to authenticated
using ((auth.uid() = author_id));



  create policy "post_comments_insert_own"
  on "public"."post_comments"
  as permissive
  for insert
  to authenticated
with check ((auth.uid() = author_id));



  create policy "post_comments_select_if_post_readable"
  on "public"."post_comments"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM public.posts p
  WHERE (p.id = post_comments.post_id))));



  create policy "post_comments_update_own"
  on "public"."post_comments"
  as permissive
  for update
  to authenticated
using ((auth.uid() = author_id))
with check ((auth.uid() = author_id));



  create policy "likes_delete_own"
  on "public"."post_likes"
  as permissive
  for delete
  to public
using ((auth.uid() = user_id));



  create policy "likes_insert_if_can_read_post"
  on "public"."post_likes"
  as permissive
  for insert
  to public
with check (((auth.uid() = user_id) AND (EXISTS ( SELECT 1
   FROM public.posts p
  WHERE ((p.id = post_likes.post_id) AND ((p.visibility = 'public'::text) OR ((p.visibility = 'private'::text) AND (p.author_id = auth.uid())) OR ((p.visibility = 'country'::text) AND (EXISTS ( SELECT 1
           FROM public.profiles pr
          WHERE ((pr.user_id = auth.uid()) AND (pr.country_code = p.country_code)))))))))));



  create policy "likes_insert_own"
  on "public"."post_likes"
  as permissive
  for insert
  to public
with check ((auth.uid() = user_id));



  create policy "likes_select_authed"
  on "public"."post_likes"
  as permissive
  for select
  to public
using ((auth.uid() IS NOT NULL));



  create policy "likes_select_own"
  on "public"."post_likes"
  as permissive
  for select
  to public
using ((auth.uid() = user_id));



  create policy "post_likes_delete_own"
  on "public"."post_likes"
  as permissive
  for delete
  to authenticated
using ((auth.uid() = user_id));



  create policy "post_likes_insert_own"
  on "public"."post_likes"
  as permissive
  for insert
  to authenticated
with check ((auth.uid() = user_id));



  create policy "post_likes_select_authed"
  on "public"."post_likes"
  as permissive
  for select
  to authenticated
using (true);



  create policy "reports_insert_authed"
  on "public"."post_reports"
  as permissive
  for insert
  to public
with check ((auth.uid() = reporter_id));



  create policy "reports_select_none"
  on "public"."post_reports"
  as permissive
  for select
  to public
using (false);



  create policy "posts insert self"
  on "public"."posts"
  as permissive
  for insert
  to authenticated
with check ((author_id = auth.uid()));



  create policy "posts read public"
  on "public"."posts"
  as permissive
  for select
  to authenticated
using (((visibility = 'public'::text) OR (author_id = auth.uid())));



  create policy "posts update self"
  on "public"."posts"
  as permissive
  for update
  to authenticated
using ((author_id = auth.uid()))
with check ((author_id = auth.uid()));



  create policy "posts_delete_own"
  on "public"."posts"
  as permissive
  for delete
  to public
using ((auth.uid() = author_id));



  create policy "posts_insert_authed"
  on "public"."posts"
  as permissive
  for insert
  to public
with check ((auth.uid() = author_id));



  create policy "posts_insert_own"
  on "public"."posts"
  as permissive
  for insert
  to authenticated
with check ((auth.uid() = author_id));



  create policy "posts_select_country_scoped"
  on "public"."posts"
  as permissive
  for select
  to public
using (((visibility = 'country'::text) AND (auth.uid() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = auth.uid()) AND (p.country_code = posts.country_code))))));



  create policy "posts_select_private_own"
  on "public"."posts"
  as permissive
  for select
  to public
using (((visibility = 'private'::text) AND (auth.uid() = author_id)));



  create policy "posts_select_public"
  on "public"."posts"
  as permissive
  for select
  to public
using ((visibility = 'public'::text));



  create policy "posts_select_visibility"
  on "public"."posts"
  as permissive
  for select
  to public
using (((visibility = 'public'::text) OR ((visibility = 'private'::text) AND (auth.uid() = author_id)) OR ((visibility = 'country'::text) AND (auth.uid() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.user_id = auth.uid()) AND (p.country_code IS NOT NULL) AND (p.country_code = posts.country_code)))))));



  create policy "posts_update_own"
  on "public"."posts"
  as permissive
  for update
  to public
using ((auth.uid() = author_id))
with check ((auth.uid() = author_id));



  create policy "presence_read_authenticated"
  on "public"."presence"
  as permissive
  for select
  to authenticated
using (true);



  create policy "profiles read public"
  on "public"."profiles"
  as permissive
  for select
  to authenticated
using (true);



  create policy "profiles_insert_own"
  on "public"."profiles"
  as permissive
  for insert
  to authenticated
with check ((auth.uid() = user_id));



  create policy "profiles_read_anon"
  on "public"."profiles"
  as permissive
  for select
  to anon
using (true);



  create policy "profiles_read_authenticated"
  on "public"."profiles"
  as permissive
  for select
  to authenticated
using (true);



  create policy "profiles_select_all"
  on "public"."profiles"
  as permissive
  for select
  to anon, authenticated
using (true);



  create policy "profiles_select_auth"
  on "public"."profiles"
  as permissive
  for select
  to authenticated
using (true);



  create policy "profiles_select_own"
  on "public"."profiles"
  as permissive
  for select
  to authenticated
using ((user_id = auth.uid()));



  create policy "profiles_select_public"
  on "public"."profiles"
  as permissive
  for select
  to authenticated
using (true);



  create policy "profiles_update_own"
  on "public"."profiles"
  as permissive
  for update
  to authenticated
using ((auth.uid() = user_id))
with check ((auth.uid() = user_id));



  create policy "follows delete self"
  on "public"."user_follows"
  as permissive
  for delete
  to authenticated
using ((auth.uid() = follower_id));



  create policy "follows insert self"
  on "public"."user_follows"
  as permissive
  for insert
  to authenticated
with check ((auth.uid() = follower_id));



  create policy "follows read self"
  on "public"."user_follows"
  as permissive
  for select
  to authenticated
using (((auth.uid() = follower_id) OR (auth.uid() = following_id)));



  create policy "follows_delete_own"
  on "public"."user_follows"
  as permissive
  for delete
  to public
using ((auth.uid() = follower_id));



  create policy "follows_insert_own"
  on "public"."user_follows"
  as permissive
  for insert
  to public
with check ((auth.uid() = follower_id));



  create policy "follows_select_authed"
  on "public"."user_follows"
  as permissive
  for select
  to public
using ((auth.uid() IS NOT NULL));



  create policy "follows_select_related"
  on "public"."user_follows"
  as permissive
  for select
  to public
using (((auth.uid() IS NOT NULL) AND ((auth.uid() = follower_id) OR (auth.uid() = following_id))));



  create policy "user_follows_delete_own"
  on "public"."user_follows"
  as permissive
  for delete
  to authenticated
using ((auth.uid() = follower_id));



  create policy "user_follows_insert_own"
  on "public"."user_follows"
  as permissive
  for insert
  to authenticated
with check (((auth.uid() = follower_id) AND (follower_id <> following_id)));



  create policy "user_follows_select_authed"
  on "public"."user_follows"
  as permissive
  for select
  to authenticated
using (true);



  create policy "location_insert_own"
  on "public"."user_location_precise"
  as permissive
  for insert
  to public
with check ((auth.uid() = user_id));



  create policy "location_select_own"
  on "public"."user_location_precise"
  as permissive
  for select
  to public
using ((auth.uid() = user_id));



  create policy "location_update_own"
  on "public"."user_location_precise"
  as permissive
  for update
  to public
using ((auth.uid() = user_id))
with check ((auth.uid() = user_id));



  create policy "precise_location_delete_own"
  on "public"."user_location_precise"
  as permissive
  for delete
  to public
using ((auth.uid() = user_id));



  create policy "precise_location_select_own"
  on "public"."user_location_precise"
  as permissive
  for select
  to public
using ((auth.uid() = user_id));



  create policy "precise_location_update_own"
  on "public"."user_location_precise"
  as permissive
  for update
  to public
using ((auth.uid() = user_id))
with check ((auth.uid() = user_id));



  create policy "precise_location_upsert_own"
  on "public"."user_location_precise"
  as permissive
  for insert
  to public
with check ((auth.uid() = user_id));



  create policy "user_location_precise_delete_own"
  on "public"."user_location_precise"
  as permissive
  for delete
  to authenticated
using ((auth.uid() = user_id));



  create policy "user_location_precise_select_own"
  on "public"."user_location_precise"
  as permissive
  for select
  to authenticated
using ((auth.uid() = user_id));



  create policy "user_location_precise_update_own"
  on "public"."user_location_precise"
  as permissive
  for update
  to authenticated
using ((auth.uid() = user_id))
with check ((auth.uid() = user_id));



  create policy "user_location_precise_upsert_own"
  on "public"."user_location_precise"
  as permissive
  for insert
  to authenticated
with check ((auth.uid() = user_id));



  create policy "presence_delete_own"
  on "public"."user_presence"
  as permissive
  for delete
  to public
using ((auth.uid() = user_id));



  create policy "presence_read_all"
  on "public"."user_presence"
  as permissive
  for select
  to anon, authenticated
using (true);



  create policy "presence_select_all"
  on "public"."user_presence"
  as permissive
  for select
  to anon, authenticated
using (true);



  create policy "presence_select_authed"
  on "public"."user_presence"
  as permissive
  for select
  to public
using ((auth.uid() IS NOT NULL));



  create policy "presence_select_public"
  on "public"."user_presence"
  as permissive
  for select
  to authenticated
using (true);



  create policy "presence_update_own"
  on "public"."user_presence"
  as permissive
  for update
  to authenticated
using ((user_id = auth.uid()))
with check ((user_id = auth.uid()));



  create policy "presence_upsert_own"
  on "public"."user_presence"
  as permissive
  for insert
  to authenticated
with check ((user_id = auth.uid()));



  create policy "presence_write_own"
  on "public"."user_presence"
  as permissive
  for insert
  to authenticated
with check ((auth.uid() = user_id));



  create policy "user_presence_insert_own"
  on "public"."user_presence"
  as permissive
  for insert
  to authenticated
with check ((user_id = auth.uid()));



  create policy "user_presence_read_anon"
  on "public"."user_presence"
  as permissive
  for select
  to anon
using (true);



  create policy "user_presence_read_authenticated"
  on "public"."user_presence"
  as permissive
  for select
  to authenticated
using (true);



  create policy "user_presence_select_auth"
  on "public"."user_presence"
  as permissive
  for select
  to authenticated
using (true);



  create policy "user_presence_select_own"
  on "public"."user_presence"
  as permissive
  for select
  to authenticated
using ((auth.uid() = user_id));



  create policy "user_presence_update_own"
  on "public"."user_presence"
  as permissive
  for update
  to authenticated
using ((user_id = auth.uid()))
with check ((user_id = auth.uid()));



  create policy "user_presence_upsert_own"
  on "public"."user_presence"
  as permissive
  for insert
  to authenticated
with check ((auth.uid() = user_id));


CREATE TRIGGER trg_comment_change AFTER INSERT OR DELETE ON public.post_comments FOR EACH ROW EXECUTE FUNCTION public.on_comment_change();

CREATE TRIGGER trg_comments_updated_at BEFORE UPDATE ON public.post_comments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_post_comments_count AFTER INSERT OR DELETE ON public.post_comments FOR EACH ROW EXECUTE FUNCTION public.sync_post_comment_count();

CREATE TRIGGER trg_like_change AFTER INSERT OR DELETE ON public.post_likes FOR EACH ROW EXECUTE FUNCTION public.on_like_change();

CREATE TRIGGER trg_post_likes_count AFTER INSERT OR DELETE ON public.post_likes FOR EACH ROW EXECUTE FUNCTION public.sync_post_like_count();

CREATE TRIGGER trg_posts_updated_at BEFORE UPDATE ON public.posts FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_location_updated_at BEFORE UPDATE ON public.user_location_precise FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER trg_user_presence_updated_at BEFORE UPDATE ON public.user_presence FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

CREATE TRIGGER on_auth_user_created_profile AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();


  create policy "avatars_delete_own"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));



  create policy "avatars_read_public"
  on "storage"."objects"
  as permissive
  for select
  to public
using ((bucket_id = 'avatars'::text));



  create policy "avatars_update_own"
  on "storage"."objects"
  as permissive
  for update
  to authenticated
using (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)))
with check (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));



  create policy "avatars_write_own"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));



  create policy "posts_delete_own"
  on "storage"."objects"
  as permissive
  for delete
  to authenticated
using (((bucket_id = 'posts'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));



  create policy "posts_insert_own"
  on "storage"."objects"
  as permissive
  for insert
  to authenticated
with check (((bucket_id = 'posts'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));



  create policy "posts_read_own_only"
  on "storage"."objects"
  as permissive
  for select
  to authenticated
using (((bucket_id = 'posts'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));



  create policy "posts_update_own"
  on "storage"."objects"
  as permissive
  for update
  to authenticated
using (((bucket_id = 'posts'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)))
with check (((bucket_id = 'posts'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text)));



