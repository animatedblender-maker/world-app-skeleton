import { pool } from '../db.js';

export type AnonymousAction =
  | 'VIEW_METADATA'
  | 'VIEW_CONTENT'
  | 'POST'
  | 'COMMENT'
  | 'VOTE'
  | 'JOIN'
  | 'LEAVE'
  | 'MODERATE'
  | 'CREATE_SPACE';

export type SpaceRow = {
  id: string;
  visibility: string;
  admission: string;
  billing_mode: string;
  status: string;
  owner_profile_id: string | null;
};

export type ProfileRow = {
  id: string;
  state: string;
  age_attested_at: Date | string | null;
};

export type Eligibility =
  | { eligible: true; birthdate: string; age: number }
  | { eligible: false; reason: string; code: string };

function ageFromBirthdate(iso: string, now = new Date()): number {
  const birth = new Date(`${iso}T00:00:00.000Z`);
  let age = now.getUTCFullYear() - birth.getUTCFullYear();
  const m = now.getUTCMonth() - birth.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < birth.getUTCDate())) age -= 1;
  return age;
}

/** Authoritative adult check from public.profiles.birthdate (18+). */
export async function checkAdultEligibility(accountId: string): Promise<Eligibility> {
  const { rows } = await pool.query<{ birthdate: Date | string | null }>(
    `select birthdate from public.profiles where user_id = $1::uuid limit 1`,
    [accountId]
  );
  const raw = rows[0]?.birthdate;
  if (raw == null) {
    return { eligible: false, reason: 'Birthdate required for Anonymous.', code: 'missing_birthdate' };
  }
  const iso =
    raw instanceof Date ? raw.toISOString().slice(0, 10) : String(raw).trim().slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(iso)) {
    return { eligible: false, reason: 'Invalid birthdate on file.', code: 'invalid_birthdate' };
  }
  const age = ageFromBirthdate(iso);
  if (age < 18) {
    return { eligible: false, reason: 'Anonymous is 18+ only.', code: 'under_18' };
  }
  return { eligible: true, birthdate: iso, age };
}

export async function isBannedFromSpace(
  profileId: string,
  spaceId: string,
  now = new Date()
): Promise<boolean> {
  const { rows } = await pool.query<{ until: Date | string | null }>(
    `
    select until
    from anonymous.space_bans
    where space_id = $1::uuid and anon_profile_id = $2::uuid
    limit 1
    `,
    [spaceId, profileId]
  );
  if (!rows[0]) return false;
  const until = rows[0].until;
  if (until == null) return true;
  const t = until instanceof Date ? until : new Date(String(until));
  return t.getTime() > now.getTime();
}

export async function hasActiveMembership(profileId: string, spaceId: string): Promise<boolean> {
  const { rows } = await pool.query(
    `
    select 1
    from anonymous.space_memberships
    where space_id = $1::uuid
      and anon_profile_id = $2::uuid
      and state = 'active'
    limit 1
    `,
    [spaceId, profileId]
  );
  return rows.length > 0;
}

export async function hasPaidEntitlement(
  profileId: string,
  spaceId: string,
  now = new Date()
): Promise<boolean> {
  if (process.env.ANONYMOUS_PAID_ENABLED !== 'true') return false;
  const { rows } = await pool.query(
    `
    select 1
    from billing.entitlements
    where profile_id = $1::uuid
      and space_id = $2::uuid
      and state in ('active', 'grace')
      and (expires_at is null or expires_at > $3::timestamptz)
    limit 1
    `,
    [profileId, spaceId, now.toISOString()]
  );
  return rows.length > 0;
}

export type PolicyDecision = { allow: true } | { allow: false; code: string; reason: string };

/**
 * Server-side authorization for Anonymous actions.
 * Never trust client UI hiding alone.
 */
export async function canAccess(opts: {
  profile: ProfileRow | null;
  space: SpaceRow | null;
  action: AnonymousAction;
  ageEligible: boolean;
  ageAttested: boolean;
}): Promise<PolicyDecision> {
  const { profile, space, action, ageEligible, ageAttested } = opts;

  if (!ageEligible) {
    return { allow: false, code: 'under_18', reason: 'Anonymous is 18+ only.' };
  }
  if (!ageAttested) {
    return { allow: false, code: 'age_attestation_required', reason: 'Age attestation required.' };
  }
  if (!profile || profile.state !== 'active') {
    return { allow: false, code: 'profile_inactive', reason: 'Anonymous profile not active.' };
  }

  if (action === 'CREATE_SPACE') {
    return { allow: true };
  }

  if (!space) {
    return { allow: false, code: 'space_not_found', reason: 'Space not found.' };
  }

  if (!['active', 'read_only'].includes(space.status)) {
    if (action === 'VIEW_METADATA' && space.status === 'suspended') {
      return { allow: false, code: 'space_suspended', reason: 'Space is suspended.' };
    }
    if (space.status !== 'active' && space.status !== 'read_only') {
      return { allow: false, code: 'space_unavailable', reason: 'Space is not available.' };
    }
  }

  if (await isBannedFromSpace(profile.id, space.id)) {
    return { allow: false, code: 'banned', reason: 'You are banned from this Space.' };
  }

  if (action === 'VIEW_METADATA') {
    if (space.visibility === 'private') {
      const member = await hasActiveMembership(profile.id, space.id);
      if (!member) {
        return { allow: false, code: 'private_space', reason: 'Private Space.' };
      }
    }
    return { allow: true };
  }

  const member = await hasActiveMembership(profile.id, space.id);

  if (space.visibility === 'private' && !member) {
    return { allow: false, code: 'private_space', reason: 'Private Space requires membership.' };
  }

  if (action === 'VIEW_CONTENT') {
    if (space.visibility === 'restricted' && !member) {
      // restricted: listing ok elsewhere; content may require membership
      return { allow: false, code: 'members_only', reason: 'Members only.' };
    }
    if (space.admission === 'paid' || space.admission === 'paid_plus_approval') {
      const entitled = member || (await hasPaidEntitlement(profile.id, space.id));
      if (!entitled) {
        return { allow: false, code: 'paid_required', reason: 'Paid entitlement required.' };
      }
    }
    return { allow: true };
  }

  if (action === 'JOIN') {
    if (member) return { allow: true };
    if (space.admission === 'paid' || space.admission === 'paid_plus_approval') {
      if (process.env.ANONYMOUS_PAID_ENABLED !== 'true') {
        return { allow: false, code: 'paid_disabled', reason: 'Paid Spaces are not enabled yet.' };
      }
    }
    return { allow: true };
  }

  if (action === 'LEAVE') {
    return { allow: true };
  }

  if (['POST', 'COMMENT', 'VOTE'].includes(action)) {
    if (space.status === 'read_only') {
      return { allow: false, code: 'read_only', reason: 'Space is read-only.' };
    }
    if (!member) {
      return { allow: false, code: 'not_member', reason: 'Join this Space to participate.' };
    }
    if (space.admission === 'paid' || space.admission === 'paid_plus_approval') {
      const entitled = await hasPaidEntitlement(profile.id, space.id);
      // Free membership path for free admission; paid admission needs entitlement
      if (space.billing_mode !== 'free' && !entitled) {
        return { allow: false, code: 'paid_required', reason: 'Paid entitlement required.' };
      }
    }
    return { allow: true };
  }

  if (action === 'MODERATE') {
    if (!member) {
      return { allow: false, code: 'forbidden', reason: 'Not a moderator.' };
    }
    const { rows } = await pool.query(
      `
      select 1
      from anonymous.space_memberships m
      join anonymous.space_roles r on r.membership_id = m.id
      where m.space_id = $1::uuid
        and m.anon_profile_id = $2::uuid
        and m.state = 'active'
        and r.role in ('owner', 'moderator')
      limit 1
      `,
      [space.id, profile.id]
    );
    if (!rows.length) {
      return { allow: false, code: 'forbidden', reason: 'Not a moderator.' };
    }
    return { allow: true };
  }

  return { allow: false, code: 'forbidden', reason: 'Not allowed.' };
}

export function isPaidEnabled(): boolean {
  return process.env.ANONYMOUS_PAID_ENABLED === 'true';
}
