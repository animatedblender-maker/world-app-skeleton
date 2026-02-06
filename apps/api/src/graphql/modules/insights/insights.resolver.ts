import { getCountryMood } from './insights.service.js';

export const insightsResolvers = {
  Query: {
    countryMood: async (_: any, args: { country_code: string }) => {
      const code = String(args?.country_code ?? '').trim().toUpperCase();
      if (!code) throw new Error('country_code is required');
      return await getCountryMood(code);
    },
    globalMood: async () => {
      return await getCountryMood(null);
    },
  },
};
