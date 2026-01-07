import { PostsService } from './posts.service.js';

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
    postsByCountry: async (_: any, args: { country_code: string; limit?: number }, ctx: Context) => {
      const limit = typeof args.limit === 'number' ? args.limit : 25;
      return await svc().postsByCountry(args.country_code ?? '', limit, ctx.user?.id ?? null);
    },
    postsByAuthor: async (_: any, args: { user_id: string; limit?: number }, ctx: Context) => {
      const limit = typeof args.limit === 'number' ? args.limit : 25;
      return await svc().postsByAuthor(args.user_id ?? '', limit, ctx.user?.id ?? null);
    },
  },

  Mutation: {
    createPost: async (_: any, args: { input: any }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.input?.body) throw new Error('Body is required.');
      return await svc().createPost(user.id, args.input);
    },
    updatePost: async (_: any, args: { post_id: string; input: any }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      return await svc().updatePost(args.post_id, user.id, args.input ?? {});
    },
    deletePost: async (_: any, args: { post_id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      return await svc().deletePost(args.post_id, user.id);
    },
  },
};
