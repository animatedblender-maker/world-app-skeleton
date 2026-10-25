import { pool } from '../../../db.js';
import { deleteAuthUser, supabaseAdminConfigured } from '../../../supabase-admin.js';

export type AccountStatus = 'active' | 'deactivated' | 'deleted';

export type MessagePrivacy = 'everyone' | 'following' | 'requests';

export type ProfileRow = {
  user_id: string;
  email: string | null;
  display_name: string | null;
  username: string | null;
  avatar_url: string | null;
  country_name: string;
  country_code: string | null;
  city_name: string | null;
  bio: string | null;
  /** YYYY-MM-DD — owner-only via redactForViewer */
  birthdate: string | null;
  is_private: boolean;
  message_privacy: MessagePrivacy;
  is_verified?: boolean;
  account_status: AccountStatus;
  deactivated_at: string | null;
  deleted_at: string | null;
  created_at: string;
  updated_at: string;
};

export type AccountActionResult = {
  ok: boolean;
  action: string;
  message: string | null;
  account_status: AccountStatus;
};

type UpdateProfileInput = {
  display_name?: string | null;
  username?: string | null;
  avatar_url?: string | null;
  country_name?: string | null;
  country_code?: string | null;
  city_name?: string | null;
  bio?: string | null;
  birthdate?: string | null;
  is_private?: boolean | null;
  message_privacy?: string | null;
};

/** Parse YYYY-MM-DD; reject invalid / future / pre-1900 dates. */
export function normalizeBirthdate(raw: unknown): string | null {
  if (raw == null) return null;
  const s = String(raw).trim();
  if (!s) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) {
    throw Object.assign(new Error('Birthdate must be YYYY-MM-DD.'), {
      code: 'INVALID_BIRTHDATE',
      status: 400,
    });
  }
  const d = new Date(`${s}T00:00:00.000Z`);
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== s) {
    throw Object.assign(new Error('Enter a valid birthdate.'), {
      code: 'INVALID_BIRTHDATE',
      status: 400,
    });
  }
  const min = new Date('1900-01-01T00:00:00.000Z');
  const today = new Date();
  const todayUtc = new Date(
    Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate())
  );
  if (d < min || d > todayUtc) {
    throw Object.assign(new Error('Enter a valid birthdate.'), {
      code: 'INVALID_BIRTHDATE',
      status: 400,
    });
  }
  // Under-18 policy TBD — store for now; do not reject.
  return s;
}

function normalizeMessagePrivacy(raw: unknown): MessagePrivacy {
  const v = String(raw ?? 'everyone').trim().toLowerCase();
  if (v === 'following' || v === 'requests') return v;
  return 'everyone';
}

export class ProfilesService {
  /** Owner always sees full data; birthdate is always owner-only. */
  redactForViewer(profile: ProfileRow | null, viewerId: string | null): ProfileRow | null {
    if (!profile) return null;
    const isPrivate = !!profile.is_private;
    const isOwner = !!viewerId && viewerId === profile.user_id;
    if (isOwner) {
      return {
        ...profile,
        is_private: isPrivate,
      };
    }
    // Birthdate is never public (age-gate later).
    const withoutBirth: ProfileRow = { ...profile, birthdate: null, is_private: isPrivate };
    if (!isPrivate) {
      return withoutBirth;
    }
    return {
      ...profile,
      is_private: true,
      avatar_url: null,
      bio: null,
      city_name: null,
      email: null,
      birthdate: null,
    };
  }

  async getMeProfile(userId: string): Promise<ProfileRow | null> {
    return await this.getProfileByIdRaw(userId);
  }

  async getProfileByIdRaw(userId: string): Promise<ProfileRow | null> {
    const { rows } = await pool.query(
      `select * from public.profiles where user_id = $1 limit 1`,
      [userId]
    );
    return this.normalize(rows[0] as ProfileRow | undefined);
  }

  /** Public lookup — hide deactivated/deleted accounts from everyone except owner. */
  async getProfileById(userId: string, viewerId: string | null = null): Promise<ProfileRow | null> {
    const raw = await this.getProfileByIdRaw(userId);
    if (!raw) return null;
    if (raw.account_status !== 'active' && viewerId !== raw.user_id) return null;
    return this.redactForViewer(raw, viewerId);
  }

  async getProfileByUsername(
    username: string,
    viewerId: string | null = null
  ): Promise<ProfileRow | null> {
    const { rows } = await pool.query(
      `
      select * from public.profiles
      where lower(username) = lower($1)
      limit 1
      `,
      [username]
    );
    const raw = this.normalize(rows[0] as ProfileRow | undefined);
    if (!raw) return null;
    if (raw.account_status !== 'active' && viewerId !== raw.user_id) return null;
    return this.redactForViewer(raw, viewerId);
  }

  async getAccountStatus(userId: string): Promise<AccountStatus> {
    const profile = await this.getProfileByIdRaw(userId);
    return profile?.account_status ?? 'active';
  }

  async assertAccountActive(userId: string): Promise<void> {
    const status = await this.getAccountStatus(userId);
    if (status === 'deactivated') {
      const err = new Error('ACCOUNT_DEACTIVATED');
      (err as any).code = 'ACCOUNT_DEACTIVATED';
      throw err;
    }
    if (status === 'deleted') {
      const err = new Error('ACCOUNT_DELETED');
      (err as any).code = 'ACCOUNT_DELETED';
      throw err;
    }
  }

  async deactivateAccount(userId: string): Promise<AccountActionResult> {
    await pool.query(
      `insert into public.profiles (user_id, country_name)
       values ($1, 'Unknown')
       on conflict (user_id) do nothing`,
      [userId]
    );

    const { rows } = await pool.query(
      `
      update public.profiles
      set
        account_status = 'deactivated',
        deactivated_at = now(),
        updated_at = now()
      where user_id = $1
        and account_status <> 'deleted'
      returning *
      `,
      [userId]
    );
    if (!rows[0]) {
      throw new Error('ACCOUNT_DEACTIVATE_FAILED');
    }

    // Best-effort offline + push cleanup. Do NOT ban auth.users — the user must
    // be able to sign back in so reactivateAccount can run.
    await pool.query(
      `update public.user_presence set is_online = false, updated_at = now() where user_id = $1`,
      [userId]
    ).catch(() => undefined);
    await pool.query(`delete from public.ios_device_tokens where user_id = $1`, [userId]).catch(
      () => undefined
    );

    return {
      ok: true,
      action: 'deactivate',
      message: 'Your account is deactivated. Sign in again to reactivate.',
      account_status: 'deactivated',
    };
  }

  async reactivateAccount(userId: string): Promise<AccountActionResult> {
    const existing = await this.getProfileByIdRaw(userId);
    if (existing?.account_status === 'deleted') {
      throw Object.assign(new Error('ACCOUNT_DELETED'), { code: 'ACCOUNT_DELETED' });
    }

    const { rows } = await pool.query(
      `
      update public.profiles
      set
        account_status = 'active',
        deactivated_at = null,
        updated_at = now()
      where user_id = $1
        and account_status = 'deactivated'
      returning *
      `,
      [userId]
    );

    // Already active is fine (idempotent).
    if (!rows[0] && existing?.account_status === 'active') {
      return {
        ok: true,
        action: 'reactivate',
        message: 'Account is already active.',
        account_status: 'active',
      };
    }
    if (!rows[0]) {
      throw new Error('ACCOUNT_REACTIVATE_FAILED');
    }

    return {
      ok: true,
      action: 'reactivate',
      message: 'Welcome back — your account is active again.',
      account_status: 'active',
    };
  }

  /**
   * Permanent deletion:
   * 1) Anonymize + tombstone profile
   * 2) Soft-delete posts
   * 3) Clear tokens / presence / follows (best-effort)
   * 4) Delete auth.users via service role (cascades remaining FKs)
   *
   * `confirmation` must be "DELETE" (case-insensitive) or the account username.
   */
  async deleteAccount(userId: string, confirmation: string): Promise<AccountActionResult> {
    const profile = await this.getProfileByIdRaw(userId);
    const confirm = (confirmation ?? '').trim();
    const username = (profile?.username ?? '').trim();
    const okConfirm =
      confirm.toUpperCase() === 'DELETE' ||
      (!!username && confirm.toLowerCase() === username.toLowerCase());
    if (!okConfirm) {
      throw Object.assign(
        new Error('Type DELETE or your username to confirm permanent deletion.'),
        { code: 'CONFIRMATION_REQUIRED' }
      );
    }

    const client = await pool.connect();
    try {
      await client.query('begin');

      // Soft-delete posts so content disappears even if auth delete is delayed.
      await client.query(
        `
        update public.posts
        set moderation_status = 'deleted', updated_at = now()
        where author_id = $1
          and coalesce(moderation_status, 'active') <> 'deleted'
        `,
        [userId]
      ).catch(() => undefined);

      // Anonymize profile before auth cascade (username unique constraint).
      const tombstoneUsername = `deleted_${userId.replace(/-/g, '').slice(0, 16)}`;
      await client.query(
        `
        update public.profiles
        set
          email = null,
          display_name = 'Deleted account',
          username = $2,
          avatar_url = null,
          bio = null,
          city_name = null,
          account_status = 'deleted',
          deleted_at = now(),
          deactivated_at = coalesce(deactivated_at, now()),
          updated_at = now()
        where user_id = $1
        `,
        [userId, tombstoneUsername]
      );

      await client.query(
        `update public.user_presence set is_online = false, updated_at = now() where user_id = $1`,
        [userId]
      ).catch(() => undefined);
      await client.query(`delete from public.ios_device_tokens where user_id = $1`, [userId]).catch(
        () => undefined
      );
      await client.query(
        `delete from public.user_follows where follower_id = $1 or following_id = $1`,
        [userId]
      ).catch(() => undefined);

      await client.query('commit');
    } catch (err) {
      await client.query('rollback').catch(() => undefined);
      throw err;
    } finally {
      client.release();
    }

    // Hard-delete auth user last (cascades remaining tables with ON DELETE CASCADE).
    let authDeleted = false;
    if (supabaseAdminConfigured()) {
      try {
        await deleteAuthUser(userId);
        authDeleted = true;
      } catch (err) {
        console.warn('[account] auth user delete failed:', (err as Error)?.message ?? err);
      }
    }

    return {
      ok: true,
      action: 'delete',
      message: authDeleted
        ? 'Your account has been permanently deleted.'
        : 'Your account has been deleted. Auth purge will complete when admin is available.',
      account_status: 'deleted',
    };
  }

  async updateProfile(userId: string, input: UpdateProfileInput): Promise<ProfileRow> {
    await this.assertAccountActive(userId);
    // ensure row exists
    await pool.query(
      `insert into public.profiles (user_id, country_name)
       values ($1, 'Unknown')
       on conflict (user_id) do nothing`,
      [userId]
    );

    const messagePrivacy =
      input.message_privacy != null && String(input.message_privacy).trim() !== ''
        ? normalizeMessagePrivacy(input.message_privacy)
        : null;

    // When birthdate is present in the input, require a valid YYYY-MM-DD (do not clear).
    let birthdate: string | null = null;
    let setBirthdate = false;
    if (input.birthdate !== undefined) {
      birthdate = normalizeBirthdate(input.birthdate);
      if (!birthdate) {
        throw Object.assign(new Error('Birthdate is required. Enter your date of birth.'), {
          code: 'BIRTHDATE_REQUIRED',
          status: 400,
        });
      }
      setBirthdate = true;
    }

    try {
      // Prefer full update including privacy + birthdate columns when they exist.
      const { rows } = await pool.query(
        `
        update public.profiles
        set
          display_name = coalesce($2, display_name),
          username     = coalesce($3, username),
          avatar_url   = coalesce($4, avatar_url),
          country_name = coalesce($5, country_name),
          country_code = coalesce($6, country_code),
          city_name    = coalesce($7, city_name),
          bio          = coalesce($8, bio),
          is_private   = coalesce($9, is_private),
          message_privacy = coalesce($10, message_privacy),
          birthdate    = case when $12::boolean then $11::date else birthdate end,
          updated_at   = now()
        where user_id = $1
        returning *
        `,
        [
          userId,
          input.display_name ?? null,
          input.username ?? null,
          input.avatar_url ?? null,
          input.country_name ?? null,
          input.country_code ?? null,
          input.city_name ?? null,
          input.bio ?? null,
          typeof input.is_private === 'boolean' ? input.is_private : null,
          messagePrivacy,
          birthdate,
          setBirthdate,
        ]
      );

      if (!rows[0]) throw new Error('PROFILE_UPDATE_FAILED');
      return this.normalize(rows[0] as ProfileRow)!;
    } catch (err: any) {
      if (err?.code === '23505' && String(err?.constraint ?? '').includes('profiles_username')) {
        throw new Error('Handle already taken.');
      }
      // Column missing (migration not applied yet) — update without privacy columns.
      const msg = String(err?.message ?? '');
      if (
        err?.code === '42703' ||
        msg.includes('is_private') ||
        msg.includes('message_privacy')
      ) {
        const { rows } = await pool.query(
          `
          update public.profiles
          set
            display_name = coalesce($2, display_name),
            username     = coalesce($3, username),
            avatar_url   = coalesce($4, avatar_url),
            country_name = coalesce($5, country_name),
            country_code = coalesce($6, country_code),
            city_name    = coalesce($7, city_name),
            bio          = coalesce($8, bio),
            updated_at   = now()
          where user_id = $1
          returning *
          `,
          [
            userId,
            input.display_name ?? null,
            input.username ?? null,
            input.avatar_url ?? null,
            input.country_name ?? null,
            input.country_code ?? null,
            input.city_name ?? null,
            input.bio ?? null,
          ]
        );
        if (!rows[0]) throw new Error('PROFILE_UPDATE_FAILED');
        return this.normalize(rows[0] as ProfileRow)!;
      }
      throw err;
    }
  }

  async searchProfiles(
    query: string,
    limit: number,
    viewerId: string | null = null,
    offset = 0
  ): Promise<ProfileRow[]> {
    const raw = (query || '').trim().replace(/^@+/, '');
    if (!raw) return [];
    const q = raw.toLowerCase();
    const escaped = q.replace(/[%_\\]/g, '\\$&');
    const prefix = `${escaped}%`;
    const contains = `%${escaped}%`;
    const max = Math.max(1, Math.min(100, limit));
    const start = Math.max(0, Math.min(400, offset || 0));

    const { rows } = await pool.query(
      `
      select *
      from public.profiles
      where coalesce(account_status, 'active') = 'active'
        and (
          lower(coalesce(username, '')) = $1
          or lower(coalesce(username, '')) like $2 escape '\\'
          or lower(coalesce(display_name, '')) like $2 escape '\\'
          or ($4::int >= 3 and (
            lower(coalesce(username, '')) like $3 escape '\\'
            or lower(coalesce(display_name, '')) like $3 escape '\\'
          ))
        )
      order by
        case
          when lower(coalesce(username, '')) = $1 then 0
          when lower(coalesce(username, '')) like $2 escape '\\' then 1
          when lower(coalesce(display_name, '')) like $2 escape '\\' then 2
          else 3
        end,
        username nulls last
      limit $5
      offset $6
      `,
      [q, prefix, contains, q.length, max, start]
    );

    return (rows as ProfileRow[])
      .map((row) => this.normalize(row)!)
      .map((row) => this.redactForViewer(row, viewerId)!);
  }

  async browseProfiles(
    limit: number,
    offset: number,
    viewerId: string | null = null
  ): Promise<ProfileRow[]> {
    const max = Math.max(1, Math.min(200, limit));
    const start = Math.max(0, offset);
    const { rows } = await pool.query(
      `
      select *
      from public.profiles
      where coalesce(account_status, 'active') = 'active'
      order by updated_at desc nulls last, created_at desc, username nulls last
      limit $1
      offset $2
      `,
      [max, start]
    );
    return (rows as ProfileRow[])
      .map((row) => this.normalize(row)!)
      .map((row) => this.redactForViewer(row, viewerId)!);
  }

  private normalize(row: ProfileRow | undefined | null): ProfileRow | null {
    if (!row) return null;
    const statusRaw = String((row as any).account_status ?? 'active').toLowerCase();
    const account_status: AccountStatus =
      statusRaw === 'deactivated' || statusRaw === 'deleted' ? statusRaw : 'active';
    const rawBirth = (row as any).birthdate;
    let birthdate: string | null = null;
    if (rawBirth instanceof Date && !Number.isNaN(rawBirth.getTime())) {
      birthdate = rawBirth.toISOString().slice(0, 10);
    } else if (typeof rawBirth === 'string' && rawBirth.trim()) {
      birthdate = rawBirth.trim().slice(0, 10);
    }
    return {
      ...row,
      birthdate,
      is_private: !!(row as any).is_private,
      message_privacy: normalizeMessagePrivacy((row as any).message_privacy),
      is_verified: !!(row as any).is_verified,
      account_status,
      deactivated_at: (row as any).deactivated_at ?? null,
      deleted_at: (row as any).deleted_at ?? null,
    };
  }
}
