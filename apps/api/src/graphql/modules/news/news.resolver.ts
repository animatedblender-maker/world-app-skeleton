import { GraphQLError } from 'graphql';

import { NewsService } from './news.service.js';

type AuthedUser = {
  id: string;
  email?: string;
  role?: string;
};

type Context = {
  user: AuthedUser | null;
};

function requireAuth(ctx: Context): AuthedUser {
  if (!ctx.user) {
    throw new GraphQLError('Authentication required.', {
      extensions: { code: 'UNAUTHENTICATED' },
    });
  }
  return ctx.user;
}

const svc = () => new NewsService();

export const newsResolvers = {
  Query: {
    countryConflictUpdates: async (_: any, args: { country_code: string; limit?: number; offset?: number }, ctx: Context) => {
      return await svc().countryConflictUpdates(
        args.country_code ?? '',
        typeof args.limit === 'number' ? args.limit : 10,
        typeof args.offset === 'number' ? args.offset : 0,
        ctx.user?.id ?? null
      );
    },
    globalConflictUpdates: async (_: any, args: { limit?: number; offset?: number }, ctx: Context) => {
      return await svc().globalConflictUpdates(
        typeof args.limit === 'number' ? args.limit : 10,
        typeof args.offset === 'number' ? args.offset : 0,
        ctx.user?.id ?? null
      );
    },
    externalNewsItem: async (_: any, args: { news_item_id: string }, ctx: Context) => {
      return await svc().externalNewsItem(args.news_item_id ?? '', ctx.user?.id ?? null);
    },
    externalNewsComments: async (_: any, args: { news_item_id: string; limit?: number; before?: string | null }) => {
      return await svc().externalNewsComments(
        args.news_item_id ?? '',
        typeof args.limit === 'number' ? args.limit : 25,
        args.before ?? null
      );
    },
  },
  Mutation: {
    addExternalNewsComment: async (_: any, args: { news_item_id: string; body: string; parent_id?: string | null }, ctx: Context) => {
      const user = requireAuth(ctx);
      return await svc().addExternalNewsComment(
        args.news_item_id ?? '',
        user.id,
        args.body ?? '',
        args.parent_id ?? null
      );
    },
    likeExternalNews: async (_: any, args: { news_item_id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      return await svc().likeExternalNews(args.news_item_id ?? '', user.id);
    },
    unlikeExternalNews: async (_: any, args: { news_item_id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      return await svc().unlikeExternalNews(args.news_item_id ?? '', user.id);
    },
    shareExternalNewsToCountry: async (_: any, args: { news_item_id: string; body?: string | null; visibility?: string | null }, ctx: Context) => {
      const user = requireAuth(ctx);
      return await svc().shareExternalNewsToCountry(
        args.news_item_id ?? '',
        user.id,
        args.body ?? null,
        args.visibility ?? 'country'
      );
    },
  },
};
