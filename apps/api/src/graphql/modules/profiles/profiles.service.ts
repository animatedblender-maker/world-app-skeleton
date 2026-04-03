import { pool, supabaseAdmin, withRequestContext } from '../../../db.js';

type ProfileRow = {
  user_id: string;
  email: string | null;
  display_name: string | null;
  username: string | null;
  avatar_url: string | null;
  country_name: string;
  country_code: string | null;
  city_name: string | null;
  bio: string | null;
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
};

export class ProfilesService {
  private normalize(row: ProfileRow | null | undefined): ProfileRow | null {
    if (!row) return null;
    return {
      ...row,
      country_name: row.country_name ?? 'Unknown',
    };
  }

  async getMeProfile(userId: string): Promise<ProfileRow | null> {
    return await this.getProfileById(userId);
  }

  async getProfileById(userId: string): Promise<ProfileRow | null> {
    const profile = await this.findProfileById(userId);
    return this.normalize(profile);
  }

  async getProfileByUsername(username: string): Promise<ProfileRow | null> {
    const profile = await this.findProfileByUsername(username);
    return this.normalize(profile);
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
      return rows[0] as ProfileRow;
    } catch (err: any) {
      if (err?.code === '23505' && String(err?.constraint ?? '').includes('profiles_username')) {
        throw new Error('Handle already taken.');
      }
      throw err;
    }
  }

  async searchProfiles(query: string, limit: number): Promise<ProfileRow[]> {
    const raw = (query || '').trim();
    if (!raw) return [];
    const iso = raw.toLowerCase();
    const pattern = `%${iso}%`;
    const max = Math.max(1, Math.min(100, limit));

    if (supabaseAdmin) {
      const { data, error } = await supabaseAdmin
        .from('profiles')
        .select('*')
        .or(`username.ilike.${pattern},display_name.ilike.${pattern}`)
        .limit(max);
      if (error) throw error;
      return ((data as ProfileRow[] | null) ?? []).map((row) => this.normalize(row)!).filter(Boolean);
    }

    const { rows } = await pool.query(
      `
      with q as (
        select websearch_to_tsquery('simple', $1) as tsq
      )
      select *,
        coalesce(country_name, 'Unknown') as country_name,
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

    return (rows as ProfileRow[]).map((row) => this.normalize(row)!).filter(Boolean);
  }

  private async findProfileById(userId: string): Promise<ProfileRow | null> {
    if (!userId) return null;

    if (supabaseAdmin) {
      try {
        const { data, error } = await supabaseAdmin
          .from('profiles')
          .select('*')
          .eq('user_id', userId)
          .limit(1)
          .maybeSingle();
        if (!error && data) return data as ProfileRow;
        if (error) console.error('profiles supabaseAdmin lookup failed', error);
      } catch (error) {
        console.error('profiles supabaseAdmin threw', error);
      }
    }

    try {
      const { rows } = await pool.query(
        `select *, coalesce(country_name, 'Unknown') as country_name from public.profiles where user_id = $1 limit 1`,
        [userId]
      );
      if (rows[0]) return rows[0] as ProfileRow;
    } catch (error) {
      console.error('profiles raw pool lookup failed', error);
    }

    try {
      return await withRequestContext({ userId, role: 'authenticated' }, async (client) => {
        const { rows } = await client.query(
          `select *, coalesce(country_name, 'Unknown') as country_name from public.profiles where user_id = $1 limit 1`,
          [userId]
        );
        return (rows[0] as ProfileRow) ?? null;
      });
    } catch (error) {
      console.error('profiles request-context lookup failed', error);
      return null;
    }
  }

  private async findProfileByUsername(username: string): Promise<ProfileRow | null> {
    if (!username) return null;

    if (supabaseAdmin) {
      try {
        const { data, error } = await supabaseAdmin
          .from('profiles')
          .select('*')
          .ilike('username', username)
          .limit(1)
          .maybeSingle();
        if (!error && data) return data as ProfileRow;
        if (error) console.error('profiles username supabaseAdmin lookup failed', error);
      } catch (error) {
        console.error('profiles username supabaseAdmin threw', error);
      }
    }

    try {
      const { rows } = await pool.query(
        `
        select *, coalesce(country_name, 'Unknown') as country_name from public.profiles
        where lower(username) = lower($1)
        limit 1
        `,
        [username]
      );
      if (rows[0]) return rows[0] as ProfileRow;
    } catch (error) {
      console.error('profiles username raw pool lookup failed', error);
    }

    try {
      return await withRequestContext({ role: 'anon' }, async (client) => {
        const { rows } = await client.query(
          `
          select *, coalesce(country_name, 'Unknown') as country_name from public.profiles
          where lower(username) = lower($1)
          limit 1
          `,
          [username]
        );
        return (rows[0] as ProfileRow) ?? null;
      });
    } catch (error) {
      console.error('profiles username request-context lookup failed', error);
      return null;
    }
  }
}
