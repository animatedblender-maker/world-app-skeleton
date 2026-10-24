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
import { MessagesService } from './graphql/modules/messages/messages.service.js';

const DEFAULT_EMAIL = 'official@matterya.com';
const DEFAULT_USERNAME = 'matterya';
const DEFAULT_DISPLAY = 'Matterya';

export const WELCOME_MESSAGE = [
  'Hey — welcome to Matterya.',
  '',
  'This is the official account.',
  '',
  'In Masquerade you’re anonymous: Spaces, posts, and replies stay behind your handle. Your real Matterya chats never mix into Masquerade Inbox.',
  '',
  'Hit reply if something’s off.',
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
    values ($1::uuid, $2, $3, $4, 'Global', true, 'everyone')
    on conflict (user_id) do update
      set email = excluded.email,
          display_name = excluded.display_name,
          username = excluded.username,
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

  // Idempotency: already welcomed? Refresh body if we find an older welcome draft.
  const prior = await pool.query<{ conversation_id: string; message_id: string; body: string }>(
    `
    select c.id::text as conversation_id, m.id::text as message_id, m.body
    from public.conversations c
    join public.conversation_members a on a.conversation_id = c.id and a.user_id = $1::uuid
    join public.conversation_members b on b.conversation_id = c.id and b.user_id = $2::uuid
    join public.messages m on m.conversation_id = c.id and m.sender_id = $1::uuid
    where c.is_direct = true
      and (
        m.body like 'Welcome to Matterya.%'
        or m.body like 'Hey — welcome to Matterya.%'
        or m.body like 'Hey - welcome to Matterya.%'
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
  const convo = await startOfficialConversation(officialId, recipientUserId);
  const msg = await svc.sendMessage(convo, officialId, { body });
  return { conversationId: convo, messageId: msg.id, created: true };
}

async function startOfficialConversation(
  officialId: string,
  recipientId: string
): Promise<string> {
  const existing = await pool.query<{ id: string }>(
    `
    select c.id::text as id
    from public.conversations c
    join public.conversation_members m1 on m1.conversation_id = c.id and m1.user_id = $1::uuid
    join public.conversation_members m2 on m2.conversation_id = c.id and m2.user_id = $2::uuid
    where c.is_direct = true
    limit 1
    `,
    [officialId, recipientId]
  );
  if (existing.rows[0]?.id) return existing.rows[0].id;

  const client = await pool.connect();
  try {
    await client.query('begin');
    const inserted = await client.query<{ id: string }>(
      `insert into public.conversations (is_direct) values (true) returning id::text as id`
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

/** Default avatar path from the iOS app icon asset. */
export function defaultOfficialAvatarPath(): string {
  const here = path.dirname(fileURLToPath(import.meta.url));
  return path.resolve(
    here,
    '../../mobile/ios/WorldApp/WorldApp/Assets.xcassets/MatteryaAppIcon.imageset/AppIcon.png'
  );
}
