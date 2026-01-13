import { GraphQLError } from 'graphql';
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
  if (!ctx.user) {
    throw new GraphQLError('Authentication required.', {
      extensions: { code: 'UNAUTHENTICATED' },
    });
  }
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
    postById: async (_: any, args: { post_id: string }, ctx: Context) => {
      if (!args?.post_id) throw new Error('post_id is required.');
      return await svc().postById(args.post_id, ctx.user?.id ?? null);
    },
    commentsByPost: async (_: any, args: { post_id: string; limit?: number; before?: string | null }, ctx: Context) => {
      const limit = typeof args.limit === 'number' ? args.limit : 20;
      const before = args?.before ?? null;
      return await svc().commentsByPost(args.post_id ?? '', limit, before, ctx.user?.id ?? null);
    },
    postLikes: async (_: any, args: { post_id: string; limit?: number }, ctx: Context) => {
      if (!args?.post_id) throw new Error('post_id is required.');
      const limit = typeof args.limit === 'number' ? args.limit : 25;
      return await svc().likesByPost(args.post_id, limit, ctx.user?.id ?? null);
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
    likePost: async (_: any, args: { post_id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      return await svc().likePost(args.post_id, user.id);
    },
    unlikePost: async (_: any, args: { post_id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      return await svc().unlikePost(args.post_id, user.id);
    },
    addComment: async (_: any, args: { post_id: string; body: string; parent_id?: string | null }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      if (!args?.body) throw new Error('body is required.');
      return await svc().addComment(args.post_id, user.id, args.body, args.parent_id ?? null);
    },
    likeComment: async (_: any, args: { comment_id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.comment_id) throw new Error('comment_id is required.');
      return await svc().likeComment(args.comment_id, user.id);
    },
    unlikeComment: async (_: any, args: { comment_id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.comment_id) throw new Error('comment_id is required.');
      return await svc().unlikeComment(args.comment_id, user.id);
    },
    reportPost: async (_: any, args: { post_id: string; reason: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      if (!args?.reason) throw new Error('reason is required.');
      return await svc().reportPost(args.post_id, user.id, args.reason);
    },
  },
};
