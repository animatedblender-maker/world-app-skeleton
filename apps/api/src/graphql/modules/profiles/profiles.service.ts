import { pool } from '../../../db.js';

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
  is_private: boolean;
  created_at: string;
  updated_at: string;
};

type UpdateProfileInput = {
  display_name?: string | null;
  username?: string | null;
  avatar_url?: string | null;
  country_name?: string | null;
  country_code?: string | null;
  city_name?: string | null;
  bio?: string | null;
  is_private?: boolean | null;
};

export class ProfilesService {
  /** Owner always sees full data; others lose avatar (and bio/city) when private. */
  redactForViewer(profile: ProfileRow | null, viewerId: string | null): ProfileRow | null {
    if (!profile) return null;
    const isPrivate = !!profile.is_private;
    const isOwner = !!viewerId && viewerId === profile.user_id;
    if (!isPrivate || isOwner) {
      return {
        ...profile,
        is_private: isPrivate,
      };
    }
    return {
      ...profile,
      is_private: true,
      avatar_url: null,
      bio: null,
      city_name: null,
      email: null,
    };
  }

  async getMeProfile(userId: string): Promise<ProfileRow | null> {
    return await this.getProfileByIdRaw(userId);
  }

  async getProfileById(userId: string, viewerId: string | null = null): Promise<ProfileRow | null> {
    return this.redactForViewer(await this.getProfileByIdRaw(userId), viewerId);
  }

  async getProfileByIdRaw(userId: string): Promise<ProfileRow | null> {
    const { rows } = await pool.query(
      `select * from public.profiles where user_id = $1 limit 1`,
      [userId]
    );
    return this.normalize(rows[0] as ProfileRow | undefined);
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
    return this.redactForViewer(this.normalize(rows[0] as ProfileRow | undefined), viewerId);
  }

  async updateProfile(userId: string, input: UpdateProfileInput): Promise<ProfileRow> {
    // ensure row exists
    await pool.query(
      `insert into public.profiles (user_id, country_name)
       values ($1, 'Unknown')
       on conflict (user_id) do nothing`,
      [userId]
    );

    try {
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
        ]
      );

      if (!rows[0]) throw new Error('PROFILE_UPDATE_FAILED');
      return this.normalize(rows[0] as ProfileRow)!;
    } catch (err: any) {
      if (err?.code === '23505' && String(err?.constraint ?? '').includes('profiles_username')) {
        throw new Error('Handle already taken.');
      }
      throw err;
    }
  }

  async searchProfiles(query: string, limit: number, viewerId: string | null = null): Promise<ProfileRow[]> {
    const raw = (query || '').trim();
    if (!raw) return [];
    const iso = raw.toLowerCase();
    const pattern = `%${iso}%`;
    const max = Math.max(1, Math.min(100, limit));

    const { rows } = await pool.query(
      `
      with q as (
        select websearch_to_tsquery('simple', $1) as tsq
      )
      select *,
        ts_rank_cd(
          to_tsvector('simple', coalesce(username, '') || ' ' || coalesce(display_name, '')),
          q.tsq
        ) as rank
      from public.profiles, q
      where (
        to_tsvector('simple', coalesce(username, '') || ' ' || coalesce(display_name, '')) @@ q.tsq
        or lower(coalesce(username, '')) like $2
        or lower(coalesce(display_name, '')) like $2
      )
      order by rank desc nulls last, username nulls last
      limit $3
      `,
      [raw, pattern, max]
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
    return {
      ...row,
      is_private: !!(row as any).is_private,
    };
  }
}
