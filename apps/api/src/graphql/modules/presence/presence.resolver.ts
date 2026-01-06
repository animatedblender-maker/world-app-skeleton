// apps/api/src/graphql/modules/presence/presence.resolver.ts
import { PresenceService, type AuthedUser } from './presence.service.ts';

type Context = {
  user: AuthedUser | null;
};

function requireAuth(ctx: Context): AuthedUser {
  if (!ctx.user?.id) throw new Error('UNAUTHENTICATED');
  return ctx.user;
}

function svc(): PresenceService {
  return new PresenceService();
}

export const presenceResolvers = {
  Query: {
    globalStats: async (_: any, __: any, _ctx: Context) => {
      // ✅ allow public global stats (you can lock later)
      return await svc().globalStats();
    },

    countryStats: async (_: any, args: { iso: string }, _ctx: Context) => {
      // ✅ allow public country stats (you can lock later)
      return await svc().countryStats(args.iso);
    },
  },

  Mutation: {
    heartbeat: async (_: any, args: { iso?: string | null }, ctx: Context) => {
      const u = requireAuth(ctx);
      return await svc().heartbeat(u, args?.iso ?? null);
    },

    setOffline: async (_: any, __: any, ctx: Context) => {
      const u = requireAuth(ctx);
      return await svc().setOffline(u);
    },
  },
};
