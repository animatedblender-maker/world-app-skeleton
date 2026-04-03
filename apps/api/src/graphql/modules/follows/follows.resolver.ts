import { GraphQLError } from 'graphql';
import { FollowsService } from './follows.service.js';
import { NotificationsService } from '../notifications/notifications.service.js';

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

const svc = () => new FollowsService();
const notify = () => new NotificationsService();

export const followsResolvers = {
  Query: {
    followCounts: async (_: any, args: { user_id: string }) => {
      if (!args?.user_id) throw new Error('user_id is required');
      return await svc().counts(args.user_id);
    },

    followingIds: async (_: any, __: any, ctx: Context) => {
      const user = requireAuth(ctx);
      return await svc().followingIds(user.id);
    },

    isFollowing: async (_: any, args: { user_id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.user_id) throw new Error('user_id is required');
      return await svc().isFollowing(user.id, args.user_id);
    },
  },

  Mutation: {
    followUser: async (_: any, args: { target_id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.target_id) throw new Error('target_id is required');
      const created = await svc().follow(user.id, args.target_id);
      if (created) {
        await notify().notifyFollow(args.target_id, user.id);
      }
      return true;
    },

    unfollowUser: async (_: any, args: { target_id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.target_id) throw new Error('target_id is required');
      await svc().unfollow(user.id, args.target_id);
      return true;
    },
  },
};
