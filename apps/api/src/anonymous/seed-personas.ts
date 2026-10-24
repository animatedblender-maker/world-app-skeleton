/**
 * Fake Masquerade authors for seeded / mirrored posts.
 *
 * Policy: prefer one post per persona; occasionally allow a second;
 * never more than two. Real user profiles (account-linked) are never used.
 */
import { randomInt } from 'node:crypto';
import { pool } from '../db.js';
import { generateSafeUsername } from './usernames.js';

const AVATAR_PREFIX = 'seed-persona-v1:';
const MAX_POSTS_PER_PERSONA = 2;
/** Chance to assign a second post to someone who already has exactly one. */
const SECOND_POST_CHANCE = 0.12;

export type SeedPersona = { id: string; username: string; postCount: number };

function isSeedAvatar(seed: string | null | undefined): boolean {
  const s = String(seed || '');
  return s.startsWith(AVATAR_PREFIX) || s === 'seed-archive-whisper-v1';
}

async function insertPersona(): Promise<SeedPersona | null> {
  for (let attempt = 0; attempt < 12; attempt++) {
    const username = generateSafeUsername();
    const avatar = `${AVATAR_PREFIX}${username}`;
    try {
      const { rows } = await pool.query<{ id: string }>(
        `
        insert into anonymous.profiles (
          username, normalized_username, avatar_seed, state, age_attested_at
        )
        values ($1, $1, $2, 'active', now())
        on conflict (normalized_username) do nothing
        returning id
        `,
        [username, avatar]
      );
      if (rows[0]?.id) {
        return { id: rows[0].id, username, postCount: 0 };
      }
    } catch {
      // collision / race — retry with a new username
    }
  }
  return null;
}

/** Load seed personas with active post counts (excludes real account-linked profiles). */
export async function listSeedPersonas(): Promise<SeedPersona[]> {
  const { rows } = await pool.query<{
    id: string;
    username: string;
    post_count: number;
  }>(
    `
    select p.id::text as id,
           p.username,
           coalesce((
             select count(*)::int
             from anonymous.posts a
             where a.author_profile_id = p.id and a.state = 'active'
           ), 0) as post_count
    from anonymous.profiles p
    where p.state = 'active'
      and (
        p.avatar_seed like $1
        or p.avatar_seed = 'seed-archive-whisper-v1'
      )
      and not exists (
        select 1 from identity_vault.account_anonymous_links al
        where al.anon_profile_id = p.id
        limit 1
      )
    order by post_count asc, p.created_at asc
    `,
    [`${AVATAR_PREFIX}%`]
  );
  return rows.map((r) => ({
    id: r.id,
    username: r.username,
    postCount: Number(r.post_count) || 0,
  }));
}

/**
 * Ensure at least `minAvailable` seed personas with fewer than MAX posts.
 * Creates new adj_noun_#### profiles as needed.
 */
export async function ensureSeedPersonas(minAvailable = 32): Promise<SeedPersona[]> {
  let personas = await listSeedPersonas();
  let available = personas.filter((p) => p.postCount < MAX_POSTS_PER_PERSONA).length;
  let guard = 0;
  while (available < minAvailable && guard < minAvailable + 40) {
    guard += 1;
    const created = await insertPersona();
    if (!created) break;
    personas.push(created);
    available += 1;
  }
  return personas;
}

/**
 * Pick an author for a new seeded/mirrored post.
 * Prefers 0-post personas; rarely (~12%) allows a second post; never a third.
 * Never assigns to archive_whisper (legacy monoculture seed).
 */
export async function pickSeedAuthor(): Promise<string | null> {
  let personas = (await ensureSeedPersonas(24)).filter(
    (p) => p.username !== 'archive_whisper'
  );
  const zero = personas.filter((p) => p.postCount === 0);
  const one = personas.filter((p) => p.postCount === 1);

  let poolPick: SeedPersona[] = zero;
  if (zero.length === 0 || (one.length > 0 && Math.random() < SECOND_POST_CHANCE)) {
    poolPick = one.length > 0 ? one : zero;
  }
  if (poolPick.length === 0) {
    const created = await insertPersona();
    if (!created) return null;
    return created.id;
  }
  const pick = poolPick[randomInt(poolPick.length)]!;
  return pick.id;
}

export { AVATAR_PREFIX, MAX_POSTS_PER_PERSONA, isSeedAvatar };
