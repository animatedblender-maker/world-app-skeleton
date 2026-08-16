import { GraphQLError } from 'graphql';
import { PostsService } from './posts.service.js';

function requireAuth(ctx: any) {
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
    postsByCountry: async (_: any, args: any, ctx: any) => {
      const limit = typeof args.limit === 'number' ? args.limit : 25;
      return await svc().postsByCountry(args.country_code ?? '', limit, ctx.user?.id ?? null);
    },
    postsByAuthor: async (_: any, args: any, ctx: any) => {
      const limit = typeof args.limit === 'number' ? args.limit : 25;
      return await svc().postsByAuthor(args.user_id ?? '', limit, ctx.user?.id ?? null);
    },
    recentPosts: async (_: any, args: any, ctx: any) => {
      const limit = typeof args.limit === 'number' ? args.limit : 25;
      const before = args?.before ?? null;
      try {
        return await svc().recentPosts(limit, ctx.user?.id ?? null, before);
      } catch (err: any) {
        console.warn('[recentPosts]', err?.message ?? err);
        // Bad cursor / transient PG — empty page beats GraphQL 500 + pool thrash.
        return [];
      }
    },
    discoverSparks: async (_: any, args: any, ctx: any) => {
      const limit = typeof args.limit === 'number' ? args.limit : 48;
      const exclude = Array.isArray(args?.exclude_ids)
        ? args.exclude_ids.map((x: any) => String(x)).filter(Boolean)
        : [];
      try {
        return await svc().discoverSparks(limit, exclude, ctx.user?.id ?? null);
      } catch (err: any) {
        console.warn('[discoverSparks]', err?.message ?? err);
        return [];
      }
    },
    postById: async (_: any, args: any, ctx: any) => {
      if (!args?.post_id) return null;
      try {
        return await svc().postById(args.post_id, ctx.user?.id ?? null);
      } catch (err: any) {
        // Never 500 the client on seed ids / bad UUID — return null.
        console.warn('[postById]', err?.message ?? err);
        return null;
      }
    },
    playbackMedia: async (_: any, args: any, ctx: any) => {
      if (!args?.post_id) return null;
      try {
        return await svc().playbackMedia(args.post_id, ctx.user?.id ?? null);
      } catch (err: any) {
        console.warn('[playbackMedia]', err?.message ?? err);
        return null;
      }
    },
    commentsByPost: async (_: any, args: any, ctx: any) => {
      // Default high enough for full R2 threads (often 50–300+). Client can still pass a limit.
      const limit = typeof args.limit === 'number' ? args.limit : 2000;
      const before = args?.before ?? null;
      return await svc().commentsByPost(args.post_id ?? '', limit, before, ctx.user?.id ?? null);
    },
    postLikes: async (_: any, args: any, ctx: any) => {
      if (!args?.post_id) throw new Error('post_id is required.');
      const limit = typeof args.limit === 'number' ? args.limit : 25;
      return await svc().likesByPost(args.post_id, limit, ctx.user?.id ?? null);
    },
    savedPosts: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      const limit = typeof args.limit === 'number' ? args.limit : 25;
      return await svc().savedPosts(user.id, limit);
    },
    searchPosts: async (_: any, args: any, ctx: any) => {
      const limit = typeof args.limit === 'number' ? args.limit : 25;
      return await svc().searchPosts(args.query ?? '', limit, ctx.user?.id ?? null);
    },
  },

  Mutation: {
    createPost: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      if (args?.input?.body === undefined || args?.input?.body === null) {
        throw new GraphQLError('Body is required.', {
          extensions: { code: 'BAD_USER_INPUT' },
        });
      }
      return await svc().createPost(user.id, args.input);
    },
    updatePost: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      return await svc().updatePost(args.post_id, user.id, args.input ?? {});
    },
    deletePost: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      return await svc().deletePost(args.post_id, user.id);
    },
    likePost: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      return await svc().likePost(args.post_id, user.id);
    },
    unlikePost: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      return await svc().unlikePost(args.post_id, user.id);
    },
    savePost: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      return await svc().savePost(args.post_id, user.id);
    },
    unsavePost: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      return await svc().unsavePost(args.post_id, user.id);
    },
    addComment: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      if (!args?.body) throw new Error('body is required.');
      return await svc().addComment(args.post_id, user.id, args.body, args.parent_id ?? null);
    },
    reportPost: async (_: any, args: { post_id: string; reason: string }, ctx: any) => {
      const user = requireAuth(ctx);
      if (!args?.post_id) throw new Error('post_id is required.');
      if (!args?.reason) throw new Error('reason is required.');
      return await svc().reportPost(args.post_id, user.id, args.reason);
    },
    likeComment: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      if (!args?.comment_id) throw new Error('comment_id is required.');
      return await svc().likeComment(args.comment_id, user.id);
    },
    unlikeComment: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      if (!args?.comment_id) throw new Error('comment_id is required.');
      return await svc().unlikeComment(args.comment_id, user.id);
    },
  },
};
