import { NewsService } from './news.service.js';

const svc = () => new NewsService();

export const newsResolvers = {
  Query: {
    countryConflictUpdates: async (_: any, args: { country_code: string; limit?: number; offset?: number }) => {
      return await svc().countryConflictUpdates(
        args.country_code ?? '',
        typeof args.limit === 'number' ? args.limit : 10,
        typeof args.offset === 'number' ? args.offset : 0
      );
    },
    globalConflictUpdates: async (_: any, args: { limit?: number; offset?: number }) => {
      return await svc().globalConflictUpdates(
        typeof args.limit === 'number' ? args.limit : 10,
        typeof args.offset === 'number' ? args.offset : 0
      );
    },
  },
};
