import { GraphQLError } from 'graphql';
import { NotificationsService } from './notifications.service.js';

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

const svc = () => new NotificationsService();

export const notificationsResolvers = {
  Query: {
    notifications: async (_: any, args: { limit?: number; before?: string | null }, ctx: Context) => {
      const user = requireAuth(ctx);
      const limit = typeof args?.limit === 'number' ? args.limit : 40;
      const before = args?.before ?? null;
      console.log('RESOLVER HIT', { field: 'notifications', userId: user.id, limit });
      try {
        return await svc().listForUser(user.id, limit, before);
      } catch (error) {
        console.error('notifications query failed', error);
        return [];
      }
    },

    notificationsUnreadCount: async (_: any, __: any, ctx: Context) => {
      const user = requireAuth(ctx);
      console.log('RESOLVER HIT', { field: 'notificationsUnreadCount', userId: user.id });
      try {
        return await svc().unreadCount(user.id);
      } catch (error) {
        console.error('notifications unread count failed', error);
        return 0;
      }
    },
  },

  Mutation: {
    markNotificationRead: async (_: any, args: { id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.id) throw new Error('id is required');
      return await svc().markRead(user.id, args.id);
    },

    markAllNotificationsRead: async (_: any, __: any, ctx: Context) => {
      const user = requireAuth(ctx);
      return await svc().markAllRead(user.id);
    },
  },
};
