import { pool } from '../../../db.ts';

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
  async getMeProfile(userId: string): Promise<ProfileRow | null> {
    return await this.getProfileById(userId);
  }

  async getProfileById(userId: string): Promise<ProfileRow | null> {
    const { rows } = await pool.query(
      `select * from public.profiles where user_id = $1 limit 1`,
      [userId]
    );
    return (rows[0] as ProfileRow) ?? null;
  }

  async getProfileByUsername(username: string): Promise<ProfileRow | null> {
    const { rows } = await pool.query(
      `
      select * from public.profiles
      where lower(username) = lower($1)
      limit 1
      `,
      [username]
    );
    return (rows[0] as ProfileRow) ?? null;
  }

  async updateProfile(userId: string, input: UpdateProfileInput): Promise<ProfileRow> {
    // ensure row exists
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
  }
}
