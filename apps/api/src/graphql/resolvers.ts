// apps/api/src/graphql/resolvers.ts
import { countriesResolvers } from './modules/countries/countries.resolver.ts';
import { profilesResolvers } from './modules/profiles/profiles.resolver.ts';
import { presenceResolvers } from './modules/presence/presence.resolver.ts';

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
    ...(countriesResolvers.Query ?? {}),
    ...(profilesResolvers.Query ?? {}),
    ...(presenceResolvers.Query ?? {}),
  },

  Mutation: {
    detectLocation: async (_: any, { lat, lng }: any) => {
      const { countryName, countryCode, cityName } = await reverseGeocodeNominatim(lat, lng);
      return { countryCode, countryName, cityName, source: 'nominatim' };
    },

    ...(profilesResolvers.Mutation ?? {}),
    ...(presenceResolvers.Mutation ?? {}),
  },
};
