import { pool } from '../../../db.ts';
export class ProfilesService {
    async getMeProfile(userId) {
        return await this.getProfileById(userId);
    }
    async getProfileById(userId) {
        const { rows } = await pool.query(`select * from public.profiles where user_id = $1 limit 1`, [userId]);
        return rows[0] ?? null;
    }
    async getProfileByUsername(username) {
        const { rows } = await pool.query(`
      select * from public.profiles
      where lower(username) = lower($1)
      limit 1
      `, [username]);
        return rows[0] ?? null;
    }
    async updateProfile(userId, input) {
        // ensure row exists
        await pool.query(`insert into public.profiles (user_id, country_name)
       values ($1, 'Unknown')
       on conflict (user_id) do nothing`, [userId]);
    const { rows } = await pool.query(`
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
      `, [
            userId,
            input.display_name ?? null,
            input.username ?? null,
            input.avatar_url ?? null,
            input.country_name ?? null,
            input.country_code ?? null,
            input.city_name ?? null,
            input.bio ?? null,
        ]);
        if (!rows[0])
            throw new Error('PROFILE_UPDATE_FAILED');
        return rows[0];
    }

    async searchProfiles(query, limit) {
        const raw = (query || '').trim();
        if (!raw)
            return [];
        const iso = raw.toLowerCase();
        const pattern = `${iso}%`;
        const max = Math.max(1, limit);
        const { rows } = await pool.query(`
      select *
      from public.profiles
      where lower(username) like $1 or lower(display_name) like $1
      order by
        case when lower(username) like $1 then 0
             when lower(display_name) like $1 then 1
             else 2
        end,
        username nulls last
      limit $2
      `, [pattern, max]);
        return rows;
    }
}
