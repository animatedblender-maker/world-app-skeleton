import { pool, type PoolClient } from '../db.js';
import {
  checkAdultEligibility,
  type Eligibility,
} from './policy.js';
import {
  generateSafeUsername,
  validateGeneratedCandidate,
} from './usernames.js';

export type AnonymousProfilePublic = {
  id: string;
  username: string;
  avatar_seed: string;
  state: string;
  age_attested_at: string | null;
  created_at: string;
};

type ProfileDb = {
  id: string;
  username: string;
  normalized_username: string;
  avatar_seed: string;
  state: string;
  age_attested_at: Date | string | null;
  created_at: Date | string;
};

function toPublic(row: ProfileDb): AnonymousProfilePublic {
  return {
    id: row.id,
    username: row.username,
    avatar_seed: row.avatar_seed,
    state: row.state,
    age_attested_at:
      row.age_attested_at == null
        ? null
        : row.age_attested_at instanceof Date
          ? row.age_attested_at.toISOString()
          : String(row.age_attested_at),
    created_at:
      row.created_at instanceof Date
        ? row.created_at.toISOString()
        : String(row.created_at),
  };
}

/** Resolve vault link → anonymous profile. Never returns account_id. */
export async function getProfileForAccount(
  accountId: string
): Promise<AnonymousProfilePublic | null> {
  const { rows } = await pool.query<ProfileDb>(
    `
    select p.id, p.username, p.normalized_username, p.avatar_seed, p.state,
           p.age_attested_at, p.created_at
    from identity_vault.account_anonymous_links l
    join anonymous.profiles p on p.id = l.anon_profile_id
    where l.account_id = $1::uuid
    limit 1
    `,
    [accountId]
  );
  return rows[0] ? toPublic(rows[0]) : null;
}

export async function getProfileById(
  profileId: string
): Promise<AnonymousProfilePublic | null> {
  const { rows } = await pool.query<ProfileDb>(
    `
    select id, username, normalized_username, avatar_seed, state,
           age_attested_at, created_at
    from anonymous.profiles
    where id = $1::uuid
    limit 1
    `,
    [profileId]
  );
  return rows[0] ? toPublic(rows[0]) : null;
}

/** Public Masquerade profile lookup by handle (never returns account_id). */
export async function getProfileByUsername(
  username: string
): Promise<AnonymousProfilePublic | null> {
  const raw = String(username || '')
    .trim()
    .replace(/^@+/, '')
    .toLowerCase();
  if (!raw || raw.length > 40) return null;
  const { rows } = await pool.query<ProfileDb>(
    `
    select id, username, normalized_username, avatar_seed, state,
           age_attested_at, created_at
    from anonymous.profiles
    where normalized_username = $1
      and state = 'active'
    limit 1
    `,
    [raw]
  );
  return rows[0] ? toPublic(rows[0]) : null;
}

async function loadOrdinaryProfileHints(accountId: string) {
  const { rows } = await pool.query<{
    display_name: string | null;
    username: string | null;
  }>(
    `select display_name, username from public.profiles where user_id = $1::uuid limit 1`,
    [accountId]
  );
  return rows[0] ?? null;
}

async function insertProfileWithLink(
  client: PoolClient,
  accountId: string,
  username: string,
  normalized: string
): Promise<ProfileDb> {
  const { rows } = await client.query<ProfileDb>(
    `
    insert into anonymous.profiles (username, normalized_username)
    values ($1, $2)
    returning id, username, normalized_username, avatar_seed, state,
              age_attested_at, created_at
    `,
    [username, normalized]
  );
  const profile = rows[0]!;
  await client.query(
    `
    insert into identity_vault.account_anonymous_links (account_id, anon_profile_id)
    values ($1::uuid, $2::uuid)
    `,
    [accountId, profile.id]
  );
  return profile;
}

/**
 * Get existing Anonymous profile or create one with a generated (or preferred) username.
 * Exactly one profile per account. Never returns account_id.
 */
export async function getOrCreateProfile(
  accountId: string,
  opts?: { regenerate?: boolean; username?: string | null }
): Promise<
  | { ok: true; profile: AnonymousProfilePublic; created: boolean }
  | { ok: false; code: string; reason: string }
> {
  const existing = await getProfileForAccount(accountId);
  if (existing) {
    if (opts?.regenerate) {
      return {
        ok: false,
        code: 'username_immutable',
        reason: 'Anonymous username cannot be changed.',
      };
    }
    return { ok: true, profile: existing, created: false };
  }

  const eligibility = await checkAdultEligibility(accountId);
  if (!eligibility.eligible) {
    return { ok: false, code: eligibility.code, reason: eligibility.reason };
  }

  const hints = await loadOrdinaryProfileHints(accountId);
  const preferredRaw = typeof opts?.username === 'string' ? opts.username.trim() : '';
  if (preferredRaw) {
    const preferred = validateGeneratedCandidate(preferredRaw, hints);
    if (!preferred.ok) {
      return {
        ok: false,
        code: preferred.code === 'invalid_syntax' ? 'username_invalid' : preferred.code,
        reason: 'That username isn’t allowed. Try another suggestion.',
      };
    }
  }

  const client = await pool.connect();
  try {
    await client.query('begin');

    // Lock on account link row space via advisory + re-check
    await client.query(`select pg_advisory_xact_lock(hashtext($1))`, [`anon:${accountId}`]);

    const { rows: again } = await client.query<ProfileDb>(
      `
      select p.id, p.username, p.normalized_username, p.avatar_seed, p.state,
             p.age_attested_at, p.created_at
      from identity_vault.account_anonymous_links l
      join anonymous.profiles p on p.id = l.anon_profile_id
      where l.account_id = $1::uuid
      limit 1
      `,
      [accountId]
    );
    if (again[0]) {
      await client.query('commit');
      return { ok: true, profile: toPublic(again[0]), created: false };
    }

    const priorAttest = await client.query(
      `select 1 from identity_vault.age_attestations where account_id = $1::uuid limit 1`,
      [accountId]
    );
    const attestedAlready = priorAttest.rows.length > 0;

    let created: ProfileDb | null = null;
    const preferredValidated = preferredRaw
      ? validateGeneratedCandidate(preferredRaw, hints)
      : null;

    for (let attempt = 0; attempt < 12; attempt++) {
      const candidate =
        attempt === 0 && preferredValidated && preferredValidated.ok
          ? preferredValidated.normalized
          : generateSafeUsername();
      const validated = validateGeneratedCandidate(candidate, hints);
      if (!validated.ok) continue;

      // Tombstone / unique collision → retry
      const tomb = await client.query(
        `select 1 from anonymous.username_tombstones where normalized_username = $1 limit 1`,
        [validated.normalized]
      );
      if (tomb.rows.length) {
        if (attempt === 0 && preferredValidated && preferredValidated.ok) {
          await client.query('rollback');
          return {
            ok: false,
            code: 'username_taken',
            reason: 'That username was just taken. Try another suggestion.',
          };
        }
        continue;
      }

      try {
        created = await insertProfileWithLink(
          client,
          accountId,
          validated.normalized,
          validated.normalized
        );
        if (attestedAlready) {
          const { rows: updated } = await client.query<ProfileDb>(
            `
            update anonymous.profiles
            set age_attested_at = coalesce(age_attested_at, now()), updated_at = now()
            where id = $1::uuid
            returning id, username, normalized_username, avatar_seed, state,
                      age_attested_at, created_at
            `,
            [created.id]
          );
          created = updated[0]!;
        }
        break;
      } catch (err: any) {
        if (err?.code === '23505') {
          if (attempt === 0 && preferredValidated && preferredValidated.ok) {
            await client.query('rollback');
            return {
              ok: false,
              code: 'username_taken',
              reason: 'That username was just taken. Try another suggestion.',
            };
          }
          continue; // unique_violation
        }
        throw err;
      }
    }

    if (!created) {
      await client.query('rollback');
      return {
        ok: false,
        code: 'username_unavailable',
        reason: 'Could not allocate a username. Try again.',
      };
    }

    await client.query('commit');
    const pub = toPublic(created);
    // Fire-and-forget audit/outbox — never include account_id in meta.
    void import('./audit.js').then(({ writeAnonymousAudit, enqueueAnonymousOutbox }) => {
      void writeAnonymousAudit({
        actor: pub.id,
        action: 'anonymous.profile.created',
        target: pub.id,
        purpose: 'pseudonym_claim',
        meta: { username: pub.username },
      });
      void enqueueAnonymousOutbox('anonymous.profile.created', {
        profile_id: pub.id,
        username: pub.username,
      });
    });
    // Masquerade Inbox welcome from @matterya (separate from the normal-account welcome).
    void import('../matterya-official.js')
      .then(({ sendMatteryaMasqueradeWelcomeMessage }) =>
        sendMatteryaMasqueradeWelcomeMessage(accountId)
      )
      .catch((err) => {
        console.warn(
          '[anonymous] masquerade welcome failed',
          err instanceof Error ? err.message : err
        );
      });
    return { ok: true, profile: pub, created: true };
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

export async function hasAgeAttestation(accountId: string): Promise<boolean> {
  const vault = await pool.query(
    `select 1 from identity_vault.age_attestations where account_id = $1::uuid limit 1`,
    [accountId]
  );
  if (vault.rows.length) return true;
  const profile = await getProfileForAccount(accountId);
  return !!profile?.age_attested_at;
}

export async function attestAge(
  accountId: string
): Promise<
  | { ok: true; profile: AnonymousProfilePublic | null; age_attested: true }
  | { ok: false; code: string; reason: string }
> {
  const eligibility = await checkAdultEligibility(accountId);
  if (!eligibility.eligible) {
    return { ok: false, code: eligibility.code, reason: eligibility.reason };
  }

  await pool.query(
    `
    insert into identity_vault.age_attestations (account_id, attested_at)
    values ($1::uuid, now())
    on conflict (account_id) do nothing
    `,
    [accountId]
  );

  const profile = await getProfileForAccount(accountId);
  if (profile) {
    const { rows } = await pool.query<ProfileDb>(
      `
      update anonymous.profiles
      set age_attested_at = coalesce(age_attested_at, now()),
          updated_at = now()
      where id = $1::uuid
      returning id, username, normalized_username, avatar_seed, state,
                age_attested_at, created_at
      `,
      [profile.id]
    );
    return { ok: true, profile: toPublic(rows[0]!), age_attested: true };
  }

  return { ok: true, profile: null, age_attested: true };
}

export async function sessionForAccount(accountId: string): Promise<{
  eligible: boolean;
  reason?: string;
  code?: string;
  profile: AnonymousProfilePublic | null;
  age_attested: boolean;
  paid_enabled: boolean;
  eligibility: Eligibility;
}> {
  const eligibility = await checkAdultEligibility(accountId);
  const profile = await getProfileForAccount(accountId);
  const age_attested = eligibility.eligible ? await hasAgeAttestation(accountId) : false;
  const paid_enabled = process.env.ANONYMOUS_PAID_ENABLED === 'true';

  if (!eligibility.eligible) {
    return {
      eligible: false,
      reason: eligibility.reason,
      code: eligibility.code,
      profile: null,
      age_attested: false,
      paid_enabled,
      eligibility,
    };
  }

  return {
    eligible: true,
    profile,
    age_attested,
    paid_enabled,
    eligibility,
  };
}
