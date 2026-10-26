/**
 * Official Matterya admin account + welcome DM for every new user.
 *
 * Env (optional overrides):
 *   MATTERYA_OFFICIAL_EMAIL
 *   MATTERYA_OFFICIAL_PASSWORD  (only used when creating the auth user)
 *   MATTERYA_OFFICIAL_USER_ID   (pin an existing user)
 */
import { promises as fs } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from './db.js';
import { createAuthUser, supabaseAdminConfigured, supabaseUrl } from './supabase-admin.js';
import {
  ensureConversationSurfaceColumn,
  MessagesService,
  type ConversationSurface,
} from './graphql/modules/messages/messages.service.js';

const DEFAULT_EMAIL = 'official@matterya.com';
const DEFAULT_USERNAME = 'matterya';
const DEFAULT_DISPLAY = 'Matterya';

/** Normal Messages welcome from @matterya after account creation. */
export const WELCOME_MESSAGE = [
  '**Hey, welcome to Matterya!**',
  '',
  "We're really glad you're here.",
  '',
  'We built Matterya with a simple idea in mind: everyone deserves a place to speak freely, question things, and form their own opinions without being told what to think.',
  '',
  "We don't belong to any political party, religious institution, or ideological movement, and we intend to keep it that way. With your help, we hope to make this a place where even the most unpopular opinions can find room for discussion.",
  '',
  "Whether you're here to share your thoughts, explore the world, meet new people, or just see what everyone else is up to, make yourself at home.",
  '',
  "We're still growing, and we'd love for you to help shape what Matterya becomes.",
  '',
  '**Thanks for being part of the beginning.**',
  '',
  '**Matterya Team**',
].join('\n');

/** First live @matterya feed post — every user should see once at the top of Home. */
export const OFFICIAL_POST_BODY = [
  '**Well, hello there. Welcome to Matterya!**',
  '',
  "We know, another social media platform. As if there weren't enough already, right?",
  '',
  'But we wanted to try something different.',
  '',
  'We believe the internet should be a place where people can speak their minds without having to follow the crowd or ask for permission to have an opinion.',
  '',
  'Matterya is independent of political parties, religious institutions, and ideological movements. We have no interest in telling you what to believe, which side to take, or what opinions you should hold. That\'s entirely up to you.',
  '',
  "We welcome disagreement, unpopular opinions, uncomfortable questions, and conversations that others might prefer to avoid. After all, you'd be surprised how much we have in common, even in those parts of ourselves we'd rather keep in the shadows.",
  '',
  "We won't always agree with what you say, and that's precisely the point. Freedom of speech means very little if it only applies to things everyone already agrees with.",
  '',
  "We're still growing, and with your help, we intend to stay true to that principle. We want Matterya to remain a place where ideas can be expressed freely, challenged openly, and judged on their own merits, not on how popular they happen to be.",
  '',
  "So, look around, make some friends, question things, and don't be afraid to be yourself.",
  '',
  '**This place is as much yours as it is ours. And we\'d like to keep it that way.**',
  '',
  '**Matterya Team**',
].join('\n');

/**
 * Masquerade Inbox welcome — lives on a separate conversation (`surface='masquerade'`).
 * Never mixed into normal Messages. Phrasing uses "Matterya" (never "the Matterya").
 */
export const MASQUERADE_WELCOME_MESSAGE = [
  '**Well, look who wandered in.**',
  '',
  'Welcome to Masquerade.',
  '',
  "It's a little different on this side of Matterya, isn't it?",
  '',
  "Out there, the world knows your name, your face, and perhaps the person you've spent years becoming. But in here, none of that matters.",
  '',
  "There's something rather fascinating about strangers behind masks. The stories they carry, the secrets they keep, and the things that only come to light when nobody knows who's speaking.",
  '',
  "We all have a side of ourselves the world rarely gets to meet. Perhaps you'll find yours here. Or perhaps you'll discover something entirely unexpected in someone else's shadows.",
  '',
  "We've given you a new name. What you do with it is entirely up to you.",
  '',
  'Now, go on. Have a look around, find a room that catches your interest, and see where the conversations take you.',
  '',
  'Just remember, not everything hidden is meant to be feared.',
  '',
  '**Enjoy the Masquerade.**',
  '',
  '**Matterya Team**',
  '',
  '*“Give him a mask, and he will tell you the truth.” — Oscar Wilde*',
].join('\n');

let cachedOfficialId: string | null = null;

function officialEmail(): string {
  return (process.env.MATTERYA_OFFICIAL_EMAIL ?? DEFAULT_EMAIL).trim().toLowerCase();
}

export async function ensureVerifiedColumn(): Promise<void> {
  await pool.query(`
    alter table public.profiles
      add column if not exists is_verified boolean not null default false
  `);
}

/** Resolve or create the official Matterya user id. */
export async function ensureMatteryaOfficialUser(opts?: {
  password?: string;
  avatarPath?: string;
}): Promise<string> {
  if (cachedOfficialId) return cachedOfficialId;
  await ensureVerifiedColumn();

  const pinned = process.env.MATTERYA_OFFICIAL_USER_ID?.trim();
  if (pinned) {
    await markOfficial(pinned, opts?.avatarPath);
    cachedOfficialId = pinned;
    return pinned;
  }

  const email = officialEmail();
  const { rows } = await pool.query<{ user_id: string }>(
    `
    select user_id::text as user_id
    from public.profiles
    where lower(email) = lower($1)
       or lower(username) = lower($2)
    order by case when lower(username) = lower($2) then 0 else 1 end
    limit 1
    `,
    [email, DEFAULT_USERNAME]
  );
  if (rows[0]?.user_id) {
    await markOfficial(rows[0].user_id, opts?.avatarPath);
    cachedOfficialId = rows[0].user_id;
    return rows[0].user_id;
  }

  // Auth lookup
  const authHit = await pool.query<{ id: string }>(
    `select id::text as id from auth.users where lower(email) = lower($1) limit 1`,
    [email]
  );
  if (authHit.rows[0]?.id) {
    await upsertOfficialProfile(authHit.rows[0].id, email, opts?.avatarPath);
    cachedOfficialId = authHit.rows[0].id;
    return authHit.rows[0].id;
  }

  if (!supabaseAdminConfigured()) {
    throw new Error('SUPABASE_ADMIN_NOT_CONFIGURED — cannot create official Matterya account');
  }
  const password =
    opts?.password?.trim() ||
    process.env.MATTERYA_OFFICIAL_PASSWORD?.trim() ||
    '';
  if (!password || password.length < 8) {
    throw new Error('MATTERYA_OFFICIAL_PASSWORD required to create official account');
  }

  const created = await createAuthUser({
    email,
    password,
    emailConfirm: true,
    userMetadata: { display_name: DEFAULT_DISPLAY, username: DEFAULT_USERNAME, role: 'admin' },
  });
  await upsertOfficialProfile(created.id, email, opts?.avatarPath);
  cachedOfficialId = created.id;
  return created.id;
}

async function upsertOfficialProfile(
  userId: string,
  email: string,
  avatarPath?: string
): Promise<void> {
  await pool.query(
    `
    insert into public.profiles (
      user_id, email, display_name, username, country_name, is_verified, message_privacy
    )
    values ($1::uuid, $2, $3, $4, '', true, 'everyone')
    on conflict (user_id) do update
      set email = excluded.email,
          display_name = excluded.display_name,
          username = excluded.username,
          country_name = '',
          is_verified = true,
          message_privacy = 'everyone',
          updated_at = now()
    `,
    [userId, email, DEFAULT_DISPLAY, DEFAULT_USERNAME]
  );
  if (avatarPath) {
    await uploadOfficialAvatar(userId, avatarPath);
  }
}

async function markOfficial(userId: string, avatarPath?: string): Promise<void> {
  await pool.query(
    `
    update public.profiles
    set display_name = coalesce(nullif(display_name, ''), $2),
        username = coalesce(username, $3),
        is_verified = true,
        message_privacy = 'everyone',
        updated_at = now()
    where user_id = $1::uuid
    `,
    [userId, DEFAULT_DISPLAY, DEFAULT_USERNAME]
  );
  // Force username matterya when free or already ours
  await pool.query(
    `
    update public.profiles
    set username = $2
    where user_id = $1::uuid
      and (
        username is null
        or lower(username) = lower($2)
        or not exists (
          select 1 from public.profiles p2
          where lower(p2.username) = lower($2) and p2.user_id <> $1::uuid
        )
      )
    `,
    [userId, DEFAULT_USERNAME]
  );
  if (avatarPath) {
    await uploadOfficialAvatar(userId, avatarPath);
  }
}

async function uploadOfficialAvatar(userId: string, filePath: string): Promise<void> {
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY ?? '';
  const base = supabaseUrl();
  if (!service || !base) return;
  const buf = await fs.readFile(filePath);
  const objectPath = `${userId}/matterya-official.png`;
  const url = `${base}/storage/v1/object/avatars/${objectPath}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      apikey: service,
      Authorization: `Bearer ${service}`,
      'Content-Type': 'image/png',
      'x-upsert': 'true',
    },
    body: buf,
  });
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    console.warn('[matterya-official] avatar upload failed', res.status, text.slice(0, 200));
    return;
  }
  const publicURL = `${base}/storage/v1/object/public/avatars/${objectPath}`;
  await pool.query(
    `update public.profiles set avatar_url = $2, updated_at = now() where user_id = $1::uuid`,
    [userId, publicURL]
  );
}

/** Send (or ensure) the welcome DM from Matterya → user. Idempotent per pair. */
export async function sendMatteryaWelcomeMessage(
  recipientUserId: string,
  body = WELCOME_MESSAGE
): Promise<{ conversationId: string; messageId: string; created: boolean }> {
  const officialId = await ensureMatteryaOfficialUser();
  if (!recipientUserId || recipientUserId === officialId) {
    throw new Error('invalid_recipient');
  }

  await ensureConversationSurfaceColumn();

  // Idempotency: already welcomed on the primary (Messages) surface?
  const prior = await pool.query<{ conversation_id: string; message_id: string; body: string }>(
    `
    select c.id::text as conversation_id, m.id::text as message_id, m.body
    from public.conversations c
    join public.conversation_members a on a.conversation_id = c.id and a.user_id = $1::uuid
    join public.conversation_members b on b.conversation_id = c.id and b.user_id = $2::uuid
    join public.messages m on m.conversation_id = c.id and m.sender_id = $1::uuid
    where c.is_direct = true
      and coalesce(c.surface, 'primary') = 'primary'
      and (
        ltrim(m.body) like 'Welcome to Matterya.%'
        or ltrim(m.body) like 'Hey — welcome to Matterya.%'
        or ltrim(m.body) like 'Hey - welcome to Matterya.%'
        or ltrim(m.body) like '**Hey, welcome to Matterya!**%'
        or ltrim(m.body) like 'Hey, welcome to Matterya!%'
        or ltrim(m.body) like '**Well, hello there. Welcome to Matterya!**%'
        or ltrim(m.body) like 'Well, hello there. Welcome to Matterya!%'
      )
    order by m.created_at asc
    limit 1
    `,
    [officialId, recipientUserId]
  );
  if (prior.rows[0]) {
    if (prior.rows[0].body !== body) {
      await pool.query(
        `update public.messages set body = $2, updated_at = now() where id = $1::uuid`,
        [prior.rows[0].message_id, body]
      );
    }
    return {
      conversationId: prior.rows[0].conversation_id,
      messageId: prior.rows[0].message_id,
      created: false,
    };
  }

  const svc = new MessagesService();
  // Bypass recipient privacy for the official welcome (start as Matterya → user).
  const convo = await startOfficialConversation(officialId, recipientUserId, 'primary');
  const msg = await svc.sendMessage(convo, officialId, { body });
  return { conversationId: convo, messageId: msg.id, created: true };
}

/** Send (or ensure) the Masquerade welcome DM after a handle is claimed. Idempotent per pair. */
export async function sendMatteryaMasqueradeWelcomeMessage(
  recipientUserId: string,
  body = MASQUERADE_WELCOME_MESSAGE
): Promise<{ conversationId: string; messageId: string; created: boolean }> {
  const officialId = await ensureMatteryaOfficialUser();
  if (!recipientUserId || recipientUserId === officialId) {
    throw new Error('invalid_recipient');
  }

  await ensureConversationSurfaceColumn();

  // Only match Masquerade-surface threads — never the normal Messages welcome.
  const prior = await pool.query<{ conversation_id: string; message_id: string; body: string }>(
    `
    select c.id::text as conversation_id, m.id::text as message_id, m.body
    from public.conversations c
    join public.conversation_members a on a.conversation_id = c.id and a.user_id = $1::uuid
    join public.conversation_members b on b.conversation_id = c.id and b.user_id = $2::uuid
    join public.messages m on m.conversation_id = c.id and m.sender_id = $1::uuid
    where c.is_direct = true
      and coalesce(c.surface, 'primary') = 'masquerade'
      and (
        ltrim(m.body) like '**Well, look who wandered in.**%'
        or ltrim(m.body) like 'Well, look who wandered in.%'
        or ltrim(m.body) like 'Welcome to Masquerade.%'
      )
    order by m.created_at asc
    limit 1
    `,
    [officialId, recipientUserId]
  );
  if (prior.rows[0]) {
    if (prior.rows[0].body !== body) {
      await pool.query(
        `update public.messages set body = $2, updated_at = now() where id = $1::uuid`,
        [prior.rows[0].message_id, body]
      );
    }
    return {
      conversationId: prior.rows[0].conversation_id,
      messageId: prior.rows[0].message_id,
      created: false,
    };
  }

  const svc = new MessagesService();
  const convo = await startOfficialConversation(officialId, recipientUserId, 'masquerade');
  const msg = await svc.sendMessage(convo, officialId, { body });
  return { conversationId: convo, messageId: msg.id, created: true };
}

async function startOfficialConversation(
  officialId: string,
  recipientId: string,
  surface: ConversationSurface = 'primary'
): Promise<string> {
  const hasSurface = await ensureConversationSurfaceColumn();
  const surfaceValue: ConversationSurface = surface === 'masquerade' ? 'masquerade' : 'primary';

  const existing = await pool.query<{ id: string }>(
    `
    select c.id::text as id
    from public.conversations c
    join public.conversation_members m1 on m1.conversation_id = c.id and m1.user_id = $1::uuid
    join public.conversation_members m2 on m2.conversation_id = c.id and m2.user_id = $2::uuid
    where c.is_direct = true
      ${hasSurface ? `and coalesce(c.surface, 'primary') = $3` : ''}
    limit 1
    `,
    hasSurface ? [officialId, recipientId, surfaceValue] : [officialId, recipientId]
  );
  if (existing.rows[0]?.id) return existing.rows[0].id;

  const client = await pool.connect();
  try {
    await client.query('begin');
    const inserted = await client.query<{ id: string }>(
      hasSurface
        ? `insert into public.conversations (is_direct, surface) values (true, $1) returning id::text as id`
        : `insert into public.conversations (is_direct) values (true) returning id::text as id`,
      hasSurface ? [surfaceValue] : []
    );
    const convoId = inserted.rows[0]?.id;
    if (!convoId) throw new Error('failed_create_conversation');
    try {
      await client.query(
        `
        insert into public.conversation_members (conversation_id, user_id, is_request, request_status)
        values
          ($1::uuid, $2::uuid, false, null),
          ($1::uuid, $3::uuid, false, null)
        `,
        [convoId, officialId, recipientId]
      );
    } catch {
      await client.query(
        `
        insert into public.conversation_members (conversation_id, user_id)
        values ($1::uuid, $2::uuid), ($1::uuid, $3::uuid)
        `,
        [convoId, officialId, recipientId]
      );
    }
    await client.query('commit');
    return convoId;
  } catch (err) {
    try {
      await client.query('rollback');
    } catch {
      /* ignore */
    }
    throw err;
  } finally {
    client.release();
  }
}

/**
 * Ensure the canonical @matterya Home feed welcome post exists and matches OFFICIAL_POST_BODY.
 * Returns the post id (for client one-time pin).
 */
export async function ensureOfficialWelcomePost(): Promise<string> {
  const officialId = await ensureMatteryaOfficialUser();
  const { rows: existing } = await pool.query<{ id: string; body: string | null }>(
    `
    select id::text as id, body
    from public.posts
    where author_id = $1::uuid
      and (
        ltrim(coalesce(body, '')) like '**Well, hello there. Welcome to Matterya!**%'
        or ltrim(coalesce(body, '')) like 'Well, hello there. Welcome to Matterya!%'
        or ltrim(coalesce(body, '')) like '**A few words about Matterya.**%'
        or ltrim(coalesce(body, '')) like 'A few words about Matterya.%'
      )
    order by created_at asc
    limit 1
    `,
    [officialId]
  );
  if (existing[0]?.id) {
    if (existing[0].body !== OFFICIAL_POST_BODY) {
      await pool.query(
        `update public.posts set body = $2, updated_at = now() where id = $1::uuid`,
        [existing[0].id, OFFICIAL_POST_BODY]
      );
    }
    return existing[0].id;
  }

  const { rows } = await pool.query<{ id: string }>(
    `
    insert into public.posts
      (author_id, country_name, country_code, title, body, visibility, moderation_status)
    values
      ($1::uuid, 'Global', 'GL', null, $2, 'public', 'active')
    returning id::text as id
    `,
    [officialId, OFFICIAL_POST_BODY]
  );
  const id = rows[0]?.id;
  if (!id) throw new Error('failed_create_official_welcome_post');
  return id;
}

/** Refresh every existing Matterya / Masquerade welcome DM body to the current copy. */
export async function refreshAllOfficialWelcomeBodies(): Promise<{
  primary: number;
  masquerade: number;
  feedPostId: string;
}> {
  const officialId = await ensureMatteryaOfficialUser();
  const primary = await pool.query(
    `
    update public.messages m
    set body = $2, updated_at = now()
    from public.conversations c
    where m.conversation_id = c.id
      and m.sender_id = $1::uuid
      and coalesce(c.surface, 'primary') = 'primary'
      and (
        ltrim(m.body) like 'Welcome to Matterya.%'
        or ltrim(m.body) like 'Hey — welcome to Matterya.%'
        or ltrim(m.body) like 'Hey - welcome to Matterya.%'
        or ltrim(m.body) like '**Hey, welcome to Matterya!**%'
        or ltrim(m.body) like 'Hey, welcome to Matterya!%'
        or ltrim(m.body) like '**Well, hello there. Welcome to Matterya!**%'
        or ltrim(m.body) like 'Well, hello there. Welcome to Matterya!%'
        or m.body like '%**Matterya Team**%'
      )
      and m.body is distinct from $2
    `,
    [officialId, WELCOME_MESSAGE]
  );
  const masquerade = await pool.query(
    `
    update public.messages m
    set body = $2, updated_at = now()
    from public.conversations c
    where m.conversation_id = c.id
      and m.sender_id = $1::uuid
      and coalesce(c.surface, 'primary') = 'masquerade'
      and (
        ltrim(m.body) like '**Well, look who wandered in.**%'
        or ltrim(m.body) like 'Well, look who wandered in.%'
        or ltrim(m.body) like 'Welcome to Masquerade.%'
        or m.body like '%Give him a mask%'
      )
      and m.body is distinct from $2
    `,
    [officialId, MASQUERADE_WELCOME_MESSAGE]
  );
  const feedPostId = await ensureOfficialWelcomePost();
  return {
    primary: primary.rowCount ?? 0,
    masquerade: masquerade.rowCount ?? 0,
    feedPostId,
  };
}

/** Default avatar path from the iOS app icon asset. */
export function defaultOfficialAvatarPath(): string {
  const here = path.dirname(fileURLToPath(import.meta.url));
  return path.resolve(
    here,
    '../../mobile/ios/WorldApp/WorldApp/Assets.xcassets/MatteryaAppIcon.imageset/AppIcon.png'
  );
}
