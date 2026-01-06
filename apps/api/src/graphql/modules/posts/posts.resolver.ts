import { PostsService } from './posts.service.ts';

type AuthedUser = {
  id: string;
  email?: string;
  role?: string;
};

type Context = {
  user: AuthedUser | null;
};

function requireAuth(ctx: Context): AuthedUser {
  if (!ctx.user) throw new Error('UNAUTHENTICATED');
  return ctx.user;
}

const svc = () => new PostsService();

export const postsResolvers = {
  Query: {
    postsByCountry: async (_: any, args: { country_code: string; limit?: number }) => {
      const limit = typeof args.limit === 'number' ? args.limit : 25;
      return await svc().postsByCountry(args.country_code ?? '', limit);
    },
  },

  Mutation: {
    createPost: async (_: any, args: { input: any }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.input?.body) throw new Error('Body is required.');
      return await svc().createPost(user.id, args.input);
    },
  },
};
