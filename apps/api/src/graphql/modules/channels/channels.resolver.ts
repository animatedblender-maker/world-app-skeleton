import { GraphQLError } from 'graphql';
import { ChannelsService } from './channels.service.js';

function requireAuth(ctx: any) {
  if (!ctx.user) {
    throw new GraphQLError('Authentication required.', {
      extensions: { code: 'UNAUTHENTICATED' },
    });
  }
  return ctx.user;
}

function mapError(err: unknown): never {
  const message = err instanceof Error ? err.message : String(err ?? 'Channel error');
  const codeMap: Record<string, string> = {
    CHANNEL_FORBIDDEN: 'FORBIDDEN',
    CHANNEL_OWNER_REQUIRED: 'FORBIDDEN',
    CHANNEL_NOT_FOUND: 'NOT_FOUND',
    CHANNEL_ALREADY_EXISTS: 'BAD_USER_INPUT',
    CHANNEL_NAME_REQUIRED: 'BAD_USER_INPUT',
    CHANNEL_HANDLE_TAKEN: 'BAD_USER_INPUT',
    CHANNEL_BAD_INPUT: 'BAD_USER_INPUT',
    CHANNEL_CANNOT_ADD_SELF: 'BAD_USER_INPUT',
    CHANNEL_TARGET_IS_OWNER: 'BAD_USER_INPUT',
    CHANNEL_CANNOT_REMOVE_OWNER: 'FORBIDDEN',
    CHANNEL_TARGET_ALREADY_OWNS: 'BAD_USER_INPUT',
    CHANNEL_ADD_ADMIN_FAILED: 'INTERNAL_SERVER_ERROR',
    CHANNEL_CREATE_FAILED: 'INTERNAL_SERVER_ERROR',
    USER_NOT_FOUND: 'NOT_FOUND',
    USER_NOT_ACTIVE: 'BAD_USER_INPUT',
    POST_NOT_ON_CHANNEL: 'BAD_USER_INPUT',
    COMMENT_FORBIDDEN: 'FORBIDDEN',
  };
  throw new GraphQLError(message, {
    extensions: { code: codeMap[message] ?? 'INTERNAL_SERVER_ERROR' },
  });
}

const svc = () => new ChannelsService();

export const channelsResolvers = {
  Query: {
    myChannel: async (_: any, __: any, ctx: any) => {
      const user = requireAuth(ctx);
      try {
        return await svc().myChannel(user.id);
      } catch (err) {
        mapError(err);
      }
    },
    channel: async (_: any, args: any, ctx: any) => {
      try {
        return await svc().channelById(args?.id ?? '', ctx.user?.id ?? null);
      } catch (err) {
        mapError(err);
      }
    },
    channelByOwner: async (_: any, args: any, ctx: any) => {
      try {
        return await svc().channelByOwner(args?.user_id ?? '', ctx.user?.id ?? null);
      } catch (err) {
        mapError(err);
      }
    },
    channelByHandle: async (_: any, args: any, ctx: any) => {
      try {
        return await svc().channelByHandle(args?.handle ?? '', ctx.user?.id ?? null);
      } catch (err) {
        mapError(err);
      }
    },
    channelMembers: async (_: any, args: any) => {
      try {
        return await svc().members(args?.channel_id ?? '');
      } catch (err) {
        mapError(err);
      }
    },
    channelsIAdmin: async (_: any, __: any, ctx: any) => {
      const user = requireAuth(ctx);
      try {
        return await svc().channelsIAdmin(user.id);
      } catch (err) {
        mapError(err);
      }
    },
  },

  Mutation: {
    createChannel: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      try {
        return await svc().createChannel(user.id, args?.input ?? {});
      } catch (err) {
        mapError(err);
      }
    },
    updateChannel: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      try {
        return await svc().updateChannel(args?.id ?? '', user.id, args?.input ?? {});
      } catch (err) {
        mapError(err);
      }
    },
    deleteChannel: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      try {
        return await svc().deleteChannel(args?.id ?? '', user.id);
      } catch (err) {
        mapError(err);
      }
    },
    addChannelAdmin: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      try {
        return await svc().addChannelAdmin(
          args?.channel_id ?? '',
          user.id,
          args?.user_id ?? ''
        );
      } catch (err) {
        mapError(err);
      }
    },
    removeChannelAdmin: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      try {
        return await svc().removeChannelAdmin(
          args?.channel_id ?? '',
          user.id,
          args?.user_id ?? ''
        );
      } catch (err) {
        mapError(err);
      }
    },
    transferChannelOwnership: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      try {
        return await svc().transferChannelOwnership(
          args?.channel_id ?? '',
          user.id,
          args?.new_owner_user_id ?? ''
        );
      } catch (err) {
        mapError(err);
      }
    },
    setChannelPostHidden: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      try {
        return await svc().setChannelPostHidden(
          args?.post_id ?? '',
          user.id,
          args?.hidden === true
        );
      } catch (err) {
        mapError(err);
      }
    },
    deleteChannelComment: async (_: any, args: any, ctx: any) => {
      const user = requireAuth(ctx);
      try {
        return await svc().deleteChannelComment(args?.comment_id ?? '', user.id);
      } catch (err) {
        mapError(err);
      }
    },
  },

  Channel: {
    members: async (parent: any) => {
      if (!parent?.id) return [];
      try {
        return await svc().members(parent.id);
      } catch {
        return [];
      }
    },
  },
};
