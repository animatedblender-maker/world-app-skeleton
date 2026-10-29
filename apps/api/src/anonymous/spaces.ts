import { pool } from '../db.js';
import { canAccess, type SpaceRow } from './policy.js';
import type { AnonymousProfilePublic } from './identity.js';

export type SpacePublic = {
  id: string;
  slug: string;
  title: string;
  description: string;
  category: string;
  tags: string[];
  visibility: string;
  admission: string;
  billing_mode: string;
  status: string;
  language: string;
  member_count: number;
  post_count: number;
  owner_username: string | null;
  joined: boolean;
  rules?: Array<{ position: number; text: string }>;
  created_at: string;
};

type SpaceDb = SpaceRow & {
  slug: string;
  title: string;
  description: string;
  category: string;
  tags: string[] | null;
  language: string;
  member_count: number;
  post_count: number;
  created_at: Date | string;
  owner_username?: string | null;
  joined?: boolean;
};

export function mapSpace(row: SpaceDb, joined = false): SpacePublic {
  return {
    id: row.id,
    slug: row.slug,
    title: row.title,
    description: row.description,
    category: row.category,
    tags: row.tags ?? [],
    visibility: row.visibility,
    admission: row.admission,
    billing_mode: row.billing_mode,
    status: row.status,
    language: row.language,
    member_count: Number(row.member_count) || 0,
    post_count: Number(row.post_count) || 0,
    owner_username: row.owner_username ?? null,
    joined: joined || !!row.joined,
    created_at:
      row.created_at instanceof Date
        ? row.created_at.toISOString()
        : String(row.created_at),
  };
}

export async function getSpaceById(id: string): Promise<SpaceDb | null> {
  const { rows } = await pool.query<SpaceDb>(
    `
    select s.id, s.slug, s.title, s.description, s.category, s.tags,
           s.visibility, s.admission, s.billing_mode, s.status, s.language,
           s.member_count, s.post_count, s.owner_profile_id, s.created_at,
           op.username as owner_username
    from anonymous.spaces s
    left join anonymous.profiles op on op.id = s.owner_profile_id
    where s.id = $1::uuid
    limit 1
    `,
    [id]
  );
  return rows[0] ?? null;
}

export async function getSpaceBySlug(slug: string): Promise<SpaceDb | null> {
  const normalized = slug.trim().toLowerCase();
  const { rows } = await pool.query<SpaceDb>(
    `
    select s.id, s.slug, s.title, s.description, s.category, s.tags,
           s.visibility, s.admission, s.billing_mode, s.status, s.language,
           s.member_count, s.post_count, s.owner_profile_id, s.created_at,
           op.username as owner_username
    from anonymous.spaces s
    left join anonymous.profiles op on op.id = s.owner_profile_id
    where s.normalized_slug = $1
    limit 1
    `,
    [normalized]
  );
  return rows[0] ?? null;
}

function decodeCursor(cursor?: string | null): { created_at: string; id: string } | null {
  if (!cursor) return null;
  try {
    const raw = Buffer.from(cursor, 'base64url').toString('utf8');
    const [created_at, id] = raw.split('|');
    if (!created_at || !id) return null;
    return { created_at, id };
  } catch {
    return null;
  }
}

function encodeCursor(created_at: string, id: string): string {
  return Buffer.from(`${created_at}|${id}`, 'utf8').toString('base64url');
}

export async function listSpaces(opts: {
  profile: AnonymousProfilePublic | null;
  filter: string;
  cursor?: string | null;
  limit: number;
  ageEligible: boolean;
  ageAttested: boolean;
}): Promise<{ spaces: SpacePublic[]; next_cursor: string | null }> {
  const limit = Math.min(Math.max(opts.limit || 20, 1), 50);
  const cur = decodeCursor(opts.cursor);
  const filter = (opts.filter || 'popular').toLowerCase();
  const profileId = opts.profile?.id ?? null;

  const params: unknown[] = [];
  let where = `s.status = 'active'`;
  // Never list private spaces unless joined
  where += ` and (
    s.visibility <> 'private'
    or (
      $1::uuid is not null and exists (
        select 1 from anonymous.space_memberships m
        where m.space_id = s.id and m.anon_profile_id = $1::uuid and m.state = 'active'
      )
    )
  )`;
  params.push(profileId);

  if (filter === 'joined') {
    where += ` and exists (
      select 1 from anonymous.space_memberships m
      where m.space_id = s.id and m.anon_profile_id = $1::uuid and m.state = 'active'
    )`;
  } else if (filter === 'free') {
    where += ` and s.billing_mode = 'free' and s.admission = 'free'`;
  } else if (filter === 'paid') {
    where += ` and (s.billing_mode <> 'free' or s.admission in ('paid', 'paid_plus_approval'))`;
  }

  if (cur) {
    params.push(cur.created_at, cur.id);
    where += ` and (s.created_at, s.id) < ($${params.length - 1}::timestamptz, $${params.length}::uuid)`;
  }

  let order = `s.member_count desc, s.created_at desc, s.id desc`;
  if (filter === 'newest') order = `s.created_at desc, s.id desc`;
  if (filter === 'for_you' || filter === 'popular') {
    order = `s.member_count desc, s.post_count desc, s.created_at desc, s.id desc`;
  }

  params.push(limit + 1);
  const { rows } = await pool.query<SpaceDb & { is_joined: boolean }>(
    `
    select s.id, s.slug, s.title, s.description, s.category, s.tags,
           s.visibility, s.admission, s.billing_mode, s.status, s.language,
           s.member_count, s.post_count, s.owner_profile_id, s.created_at,
           op.username as owner_username,
           exists (
             select 1 from anonymous.space_memberships m
             where m.space_id = s.id and m.anon_profile_id = $1::uuid and m.state = 'active'
           ) as is_joined
    from anonymous.spaces s
    left join anonymous.profiles op on op.id = s.owner_profile_id
    where ${where}
    order by ${order}
    limit $${params.length}
    `,
    params
  );

  const page = rows.slice(0, limit);
  const spaces = page.map((r) => mapSpace(r, !!r.is_joined));
  let next_cursor: string | null = null;
  if (rows.length > limit) {
    const last = page[page.length - 1]!;
    const created =
      last.created_at instanceof Date
        ? last.created_at.toISOString()
        : String(last.created_at);
    next_cursor = encodeCursor(created, last.id);
  }
  return { spaces, next_cursor };
}

export async function getSpaceDetail(
  slugOrId: string,
  profile: AnonymousProfilePublic | null,
  ageEligible: boolean,
  ageAttested: boolean
): Promise<
  | { ok: true; space: SpacePublic }
  | { ok: false; code: string; reason: string; status: number }
> {
  const uuidRe =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const space = uuidRe.test(slugOrId)
    ? await getSpaceById(slugOrId)
    : await getSpaceBySlug(slugOrId);
  if (!space) {
    return { ok: false, code: 'not_found', reason: 'Space not found.', status: 404 };
  }

  const decision = await canAccess({
    profile: profile
      ? { id: profile.id, state: profile.state, age_attested_at: profile.age_attested_at }
      : null,
    space,
    action: 'VIEW_METADATA',
    ageEligible,
    ageAttested,
  });
  if (!decision.allow) {
    return { ok: false, code: decision.code, reason: decision.reason, status: 403 };
  }

  const joined = profile
    ? (
        await pool.query(
          `select 1 from anonymous.space_memberships
           where space_id = $1::uuid and anon_profile_id = $2::uuid and state = 'active' limit 1`,
          [space.id, profile.id]
        )
      ).rows.length > 0
    : false;

  const { rows: rules } = await pool.query<{ position: number; text: string }>(
    `select position, text from anonymous.space_rules where space_id = $1::uuid order by position asc`,
    [space.id]
  );

  const mapped = mapSpace(space, joined);
  mapped.rules = rules;
  return { ok: true, space: mapped };
}

function slugify(title: string): string {
  return title
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 48) || 'space';
}

export async function createFreeSpace(opts: {
  profile: AnonymousProfilePublic;
  title: string;
  description?: string;
  category?: string;
  slug?: string;
  visibility?: string;
  rules?: string[];
  ageEligible: boolean;
  ageAttested: boolean;
}): Promise<
  | { ok: true; space: SpacePublic }
  | { ok: false; code: string; reason: string; status: number }
> {
  const decision = await canAccess({
    profile: {
      id: opts.profile.id,
      state: opts.profile.state,
      age_attested_at: opts.profile.age_attested_at,
    },
    space: null,
    action: 'CREATE_SPACE',
    ageEligible: opts.ageEligible,
    ageAttested: opts.ageAttested,
  });
  if (!decision.allow) {
    return { ok: false, code: decision.code, reason: decision.reason, status: 403 };
  }

  const title = String(opts.title || '').trim().slice(0, 80);
  if (title.length < 3) {
    return { ok: false, code: 'bad_title', reason: 'Title too short.', status: 400 };
  }
  const visibility = ['adult_public', 'restricted', 'private'].includes(
    String(opts.visibility || '')
  )
    ? String(opts.visibility)
    : 'adult_public';

  let base = (opts.slug ? slugify(opts.slug) : slugify(title)).slice(0, 40);
  if (!/^[a-z][a-z0-9_]{1,47}$/.test(base)) {
    return { ok: false, code: 'bad_slug', reason: 'Invalid slug.', status: 400 };
  }

  const client = await pool.connect();
  try {
    await client.query('begin');
    let slug = base;
    for (let i = 0; i < 8; i++) {
      const trySlug = i === 0 ? slug : `${base}_${i + 1}`.slice(0, 48);
      const clash = await client.query(
        `select 1 from anonymous.spaces where normalized_slug = $1 limit 1`,
        [trySlug]
      );
      if (!clash.rows.length) {
        slug = trySlug;
        break;
      }
      if (i === 7) {
        await client.query('rollback');
        return { ok: false, code: 'slug_taken', reason: 'Slug unavailable.', status: 409 };
      }
    }

    const { rows } = await client.query<SpaceDb>(
      `
      insert into anonymous.spaces (
        slug, normalized_slug, title, description, owner_profile_id,
        category, visibility, admission, billing_mode, status, member_count
      )
      values ($1, $1, $2, $3, $4::uuid, $5, $6, 'free', 'free', 'active', 1)
      returning id, slug, title, description, category, tags, visibility, admission,
                billing_mode, status, language, member_count, post_count,
                owner_profile_id, created_at
      `,
      [
        slug,
        title,
        String(opts.description || '').trim().slice(0, 2000),
        opts.profile.id,
        String(opts.category || 'general').trim().slice(0, 40) || 'general',
        visibility,
      ]
    );
    const space = rows[0]!;

    const { rows: mem } = await client.query<{ id: string }>(
      `
      insert into anonymous.space_memberships (space_id, anon_profile_id, state)
      values ($1::uuid, $2::uuid, 'active')
      returning id
      `,
      [space.id, opts.profile.id]
    );
    await client.query(
      `
      insert into anonymous.space_roles (membership_id, role, granted_by)
      values ($1::uuid, 'owner', $2::uuid)
      `,
      [mem[0]!.id, opts.profile.id]
    );

    const ruleTexts =
      opts.rules?.filter((t) => String(t).trim()).slice(0, 12) ??
      [
        'Be 18+. This entire section is adult-only.',
        'No doxxing, threats, scams, or illegal content.',
        'Do not share real names or your ordinary Matterya identity.',
      ];
    for (let i = 0; i < ruleTexts.length; i++) {
      await client.query(
        `insert into anonymous.space_rules (space_id, position, text) values ($1::uuid, $2, $3)`,
        [space.id, i, String(ruleTexts[i]).trim().slice(0, 500)]
      );
    }

    await client.query('commit');
    const mapped = mapSpace({ ...space, owner_username: opts.profile.username }, true);
    return { ok: true, space: mapped };
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

export async function joinSpace(opts: {
  profile: AnonymousProfilePublic;
  spaceId: string;
  ageEligible: boolean;
  ageAttested: boolean;
}): Promise<
  | { ok: true; membership: { space_id: string; state: string } }
  | { ok: false; code: string; reason: string; status: number }
> {
  const space = await getSpaceById(opts.spaceId);
  if (!space) {
    return { ok: false, code: 'not_found', reason: 'Space not found.', status: 404 };
  }
  const decision = await canAccess({
    profile: {
      id: opts.profile.id,
      state: opts.profile.state,
      age_attested_at: opts.profile.age_attested_at,
    },
    space,
    action: 'JOIN',
    ageEligible: opts.ageEligible,
    ageAttested: opts.ageAttested,
  });
  if (!decision.allow) {
    return { ok: false, code: decision.code, reason: decision.reason, status: 403 };
  }

  const client = await pool.connect();
  try {
    await client.query('begin');
    const { rows } = await client.query<{ state: string }>(
      `
      insert into anonymous.space_memberships (space_id, anon_profile_id, state, joined_at, left_at)
      values ($1::uuid, $2::uuid, 'active', now(), null)
      on conflict (space_id, anon_profile_id) do update
        set state = case
              when anonymous.space_memberships.state = 'banned' then 'banned'
              else 'active'
            end,
            joined_at = case
              when anonymous.space_memberships.state = 'banned' then anonymous.space_memberships.joined_at
              else now()
            end,
            left_at = case
              when anonymous.space_memberships.state = 'banned' then anonymous.space_memberships.left_at
              else null
            end
      returning state
      `,
      [space.id, opts.profile.id]
    );
    if (rows[0]?.state === 'banned') {
      await client.query('rollback');
      return { ok: false, code: 'banned', reason: 'You are banned from this Space.', status: 403 };
    }
    // Role first, then commit — never hold the txn open on a full member_count recount
    // (that locked joins for 45s+ while Masquerade seed hammered spaces/memberships).
    await client.query(
      `
      insert into anonymous.space_roles (membership_id, role)
      select m.id, 'member'
      from anonymous.space_memberships m
      where m.space_id = $1::uuid and m.anon_profile_id = $2::uuid
      on conflict (membership_id, role) do nothing
      `,
      [space.id, opts.profile.id]
    );
    await client.query('commit');
    // Cheap bump outside the txn — approximate until next recount; avoids Lock waits.
    try {
      await pool.query(
        `
        update anonymous.spaces
        set member_count = greatest(coalesce(member_count, 0) + 1, 1),
            updated_at = now()
        where id = $1::uuid
        `,
        [space.id]
      );
    } catch {
      /* non-fatal — membership already committed */
    }
    return { ok: true, membership: { space_id: space.id, state: 'active' } };
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

export async function leaveSpace(opts: {
  profile: AnonymousProfilePublic;
  spaceId: string;
  ageEligible: boolean;
  ageAttested: boolean;
}): Promise<
  | { ok: true }
  | { ok: false; code: string; reason: string; status: number }
> {
  const space = await getSpaceById(opts.spaceId);
  if (!space) {
    return { ok: false, code: 'not_found', reason: 'Space not found.', status: 404 };
  }
  const { rowCount } = await pool.query(
    `
    update anonymous.space_memberships
    set state = case when state = 'banned' then 'banned' else 'left' end,
        left_at = now()
    where space_id = $1::uuid and anon_profile_id = $2::uuid and state = 'active'
    `,
    [space.id, opts.profile.id]
  );
  if ((rowCount ?? 0) > 0) {
    try {
      await pool.query(
        `
        update anonymous.spaces
        set member_count = greatest(coalesce(member_count, 1) - 1, 0),
            updated_at = now()
        where id = $1::uuid
        `,
        [space.id]
      );
    } catch {
      /* non-fatal */
    }
  }
  return { ok: true };
}
