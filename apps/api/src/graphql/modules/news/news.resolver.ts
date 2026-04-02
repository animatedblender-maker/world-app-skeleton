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
    countryConflictUpdates: async (
      _: any,
      args: { country_code: string; limit?: number; offset?: number },
      ctx: Context
    ) => {
      requireAuth(ctx);
      return await svc().getCountryConflictUpdates(
        args.country_code,
        args.limit ?? 10,
        args.offset ?? 0
      );
    },

    globalConflictUpdates: async (
      _: any,
      args: { limit?: number; offset?: number },
      ctx: Context
    ) => {
      requireAuth(ctx);
      return await svc().getGlobalConflictUpdates(args.limit ?? 10, args.offset ?? 0);
    },

    externalNewsComments: async (
      _: any,
      args: { news_item_id: string; limit?: number; before?: string | null },
      ctx: Context
    ) => {
      requireAuth(ctx);
      return await svc().getExternalNewsComments(
        args.news_item_id,
        args.limit ?? 25,
        args.before ?? null
      );
    },
  },

  Mutation: {
    addExternalNewsComment: async (
      _: any,
      args: { news_item_id: string; body: string; parent_id?: string | null },
      ctx: Context
    ) => {
      const user = requireAuth(ctx);
      return await svc().addExternalNewsComment(
        user.id,
        args.news_item_id,
        args.body,
        args.parent_id ?? null
      );
    },

    shareExternalNewsToCountry: async (
      _: any,
      args: { news_item_id: string; body?: string | null; visibility?: string | null },
      ctx: Context
    ) => {
      const user = requireAuth(ctx);
      return await svc().shareExternalNewsToCountry(
        user.id,
        args.news_item_id,
        args.body ?? null,
        String(args.visibility ?? 'country')
      );
    },

    refreshCountryConflictUpdates: async (
      _: any,
      args: { country_code: string },
      ctx: Context
    ) => {
      requireAuth(ctx);
      return await svc().refreshCountryConflictUpdates(args.country_code);
    },
  },
};
