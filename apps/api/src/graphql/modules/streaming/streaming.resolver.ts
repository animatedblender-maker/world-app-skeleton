import { GraphQLError } from 'graphql';
import { StreamingService } from './streaming.service.js';

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

const svc = () => new StreamingService();

export const streamingResolvers = {
  Query: {
    myStreamingConnections: async (_: any, __: any, ctx: Context) => {
      const user = requireAuth(ctx);
      return await svc().myConnections(user.id);
    },

    myNowPlaying: async (_: any, __: any, ctx: Context) => {
      const user = requireAuth(ctx);
      return await svc().myNowPlaying(user.id);
    },

    friendsStreamingActivity: async (_: any, args: { limit?: number }, ctx: Context) => {
      const user = requireAuth(ctx);
      const limit = typeof args.limit === 'number' ? args.limit : 20;
      return await svc().friendsActivity(user.id, limit);
    },

    momentRooms: async (_: any, args: { limit?: number }, ctx: Context) => {
      const user = requireAuth(ctx);
      const limit = typeof args.limit === 'number' ? args.limit : 12;
      return await svc().momentRooms(user.id, limit);
    },

    momentRoomComments: async (
      _: any,
      args: { room_key: string; limit?: number },
      ctx: Context
    ) => {
      const user = requireAuth(ctx);
      if (!args?.room_key) throw new Error('room_key is required');
      const limit = typeof args.limit === 'number' ? args.limit : 40;
      return await svc().momentRoomComments(args.room_key, user.id, limit);
    },
  },

  Mutation: {
    linkStreamingPlatform: async (_: any, args: { platform: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.platform) throw new Error('platform is required');
      return await svc().linkPlatform(user.id, args.platform);
    },

    unlinkStreamingPlatform: async (_: any, args: { platform: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.platform) throw new Error('platform is required');
      return await svc().unlinkPlatform(user.id, args.platform);
    },

    setPlatformSharing: async (
      _: any,
      args: { platform: string; enabled: boolean },
      ctx: Context
    ) => {
      const user = requireAuth(ctx);
      if (!args?.platform) throw new Error('platform is required');
      return await svc().setPlatformSharing(user.id, args.platform, !!args.enabled);
    },

    updateNowPlaying: async (_: any, args: { input: any }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.input?.platform || !args?.input?.title) {
        throw new Error('platform and title are required');
      }
      return await svc().updateNowPlaying(user.id, args.input);
    },

    clearNowPlaying: async (_: any, args: { platform: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.platform) throw new Error('platform is required');
      return await svc().clearNowPlaying(user.id, args.platform);
    },

    addMomentRoomComment: async (
      _: any,
      args: { room_key: string; body: string },
      ctx: Context
    ) => {
      const user = requireAuth(ctx);
      if (!args?.room_key) throw new Error('room_key is required');
      return await svc().addMomentRoomComment(user.id, args.room_key, args.body ?? '');
    },
  },
};