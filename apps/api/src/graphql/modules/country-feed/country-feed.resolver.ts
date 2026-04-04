import { CountryFeedService } from './country-feed.service.js';

type Context = {
  user: { id: string } | null;
};

function svc(): CountryFeedService {
  return new CountryFeedService();
}

export const countryFeedResolvers = {
  Query: {
    countryPulse: async (_: any, args: { country_code: string }) => {
      return await svc().countryPulse(args.country_code ?? '');
    },
    countryIntelligence: async (_: any, args: { country_code: string }, ctx: Context) => {
      return await svc().countryIntelligence(args.country_code ?? '', ctx.user?.id ?? null);
    },
  },
};
