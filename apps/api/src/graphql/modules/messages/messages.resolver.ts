import { GraphQLError } from 'graphql';
import { MessagesService } from './messages.service.js';

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

const svc = () => new MessagesService();

export const messagesResolvers = {
  Query: {
    conversations: async (_: any, args: { limit?: number }, ctx: Context) => {
      const user = requireAuth(ctx);
      const limit = typeof args?.limit === 'number' ? args.limit : 20;
      return await svc().listConversations(user.id, limit);
    },
    conversationById: async (_: any, args: { conversation_id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.conversation_id) throw new Error('conversation_id is required.');
      return await svc().getConversationById(args.conversation_id, user.id);
    },
    messagesByConversation: async (
      _: any,
      args: { conversation_id: string; limit?: number; before?: string | null },
      ctx: Context
    ) => {
      const user = requireAuth(ctx);
      if (!args?.conversation_id) throw new Error('conversation_id is required.');
      const limit = typeof args.limit === 'number' ? args.limit : 30;
      const before = args?.before ?? null;
      return await svc().messagesByConversation(args.conversation_id, limit, before, user.id);
    },
    messagesUnreadCount: async (_: any, _args: unknown, ctx: Context) => {
      const user = requireAuth(ctx);
      return await svc().unreadCount(user.id);
    },
  },

  Mutation: {
    startConversation: async (_: any, args: { target_id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.target_id) throw new Error('target_id is required.');
      return await svc().startConversation(args.target_id, user.id);
    },
    sendMessage: async (
      _: any,
      args: {
        conversation_id: string;
        body?: string | null;
        media_type?: string | null;
        media_path?: string | null;
        media_name?: string | null;
        media_mime?: string | null;
        media_size?: number | null;
      },
      ctx: Context
    ) => {
      const user = requireAuth(ctx);
      if (!args?.conversation_id) throw new Error('conversation_id is required.');
      return await svc().sendMessage(args.conversation_id, user.id, {
        body: args?.body ?? null,
        media_type: args?.media_type ?? null,
        media_path: args?.media_path ?? null,
        media_name: args?.media_name ?? null,
        media_mime: args?.media_mime ?? null,
        media_size: args?.media_size ?? null,
      });
    },
  },
};
