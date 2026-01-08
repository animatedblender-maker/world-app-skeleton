import { NotificationsService } from './notifications.service.js';

function requireAuth(ctx) {
  if (!ctx.user) throw new Error('UNAUTHENTICATED');
  return ctx.user;
}

const svc = () => new NotificationsService();

export const notificationsResolvers = {
  Query: {
    notifications: async (_, args, ctx) => {
      const user = requireAuth(ctx);
      const limit = typeof args?.limit === 'number' ? args.limit : 40;
      const before = args?.before ?? null;
      return await svc().listForUser(user.id, limit, before);
    },

    notificationsUnreadCount: async (_, __, ctx) => {
      const user = requireAuth(ctx);
      return await svc().unreadCount(user.id);
    },
  },

  Mutation: {
    markNotificationRead: async (_, args, ctx) => {
      const user = requireAuth(ctx);
      if (!args?.id) throw new Error('id is required');
      return await svc().markRead(user.id, args.id);
    },

    markAllNotificationsRead: async (_, __, ctx) => {
      const user = requireAuth(ctx);
      return await svc().markAllRead(user.id);
    },
  },
};
