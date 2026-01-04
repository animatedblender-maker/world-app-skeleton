import { countriesResolvers } from './modules/countries/countries.resolver.ts';
import { pool } from '../db.ts';

function requireAuth(ctx: any) {
  const u = ctx.user;
  if (!u?.id) throw new Error('UNAUTHENTICATED');
  return u as { id: string; email?: string };
}

async function reverseGeocodeNominatim(lat: number, lng: number) {
  const url = new URL('https://nominatim.openstreetmap.org/reverse');
  url.searchParams.set('format', 'jsonv2');
  url.searchParams.set('lat', String(lat));
  url.searchParams.set('lon', String(lng));

  const ua = process.env.NOMINATIM_UA ?? 'WorldAppMVP/1.0 (local dev)';

  const res = await fetch(url.toString(), {
    headers: {
      'User-Agent': ua,
      Accept: 'application/json',
    },
  });

  if (!res.ok) throw new Error(`Nominatim failed: ${res.status}`);
  const json: any = await res.json();
  const addr = json.address ?? {};

  const countryName = addr.country ?? 'Unknown';
  const countryCode = String(addr.country_code ?? '').toUpperCase() || 'XX';
  const cityName =
    addr.city ??
    addr.town ??
    addr.village ??
    addr.municipality ??
    addr.state_district ??
    addr.state ??
    null;

  return { countryName, countryCode, cityName };
}

export const resolvers = {
  Query: {
    ...countriesResolvers.Query,

    meProfile: async (_: any, __: any, ctx: any) => {
      const u = requireAuth(ctx);

      const { rows } = await pool.query(
        `select * from public.profiles where user_id = $1 limit 1`,
        [u.id]
      );

      return rows[0] ?? null;
    },
  },

  Mutation: {
    detectLocation: async (_: any, { lat, lng }: any) => {
      const { countryName, countryCode, cityName } = await reverseGeocodeNominatim(lat, lng);
      return { countryCode, countryName, cityName, source: 'nominatim' };
    },

    updateProfile: async (_: any, { input }: any, ctx: any) => {
      const u = requireAuth(ctx);

      await pool.query(
        `insert into public.profiles (user_id, email, country_name)
         values ($1,$2,'Unknown')
         on conflict (user_id) do nothing`,
        [u.id, u.email ?? null]
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
          u.id,
          input.display_name ?? null,
          input.username ?? null,
          input.avatar_url ?? null,
          input.country_name ?? null,
          input.country_code ?? null,
          input.city_name ?? null,
          input.bio ?? null,
        ]
      );

      return rows[0];
    },
  },
};
