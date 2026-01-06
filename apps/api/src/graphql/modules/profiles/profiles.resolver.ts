import { ProfilesService } from './profiles.service.ts';

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

function svc(): ProfilesService {
  // create on demand (not at import time)
  return new ProfilesService();
}

export const profilesResolvers = {
  Query: {
    me: (_: any, __: any, ctx: Context) => {
      if (!ctx.user) return null;
      return { id: ctx.user.id, email: ctx.user.email, role: ctx.user.role };
    },

    privatePing: (_: any, __: any, ctx: Context) => {
      const u = requireAuth(ctx);
      return `pong (authed as ${u.id})`;
    },

    meProfile: async (_: any, __: any, ctx: Context) => {
      const u = requireAuth(ctx);
      return await svc().getMeProfile(u.id);
    },

    profileById: async (_: any, args: { user_id: string }) => {
      if (!args?.user_id) return null;
      return await svc().getProfileById(args.user_id);
    },

    profileByUsername: async (_: any, args: { username: string }) => {
      if (!args?.username) return null;
      return await svc().getProfileByUsername(args.username);
    },
  },

  Mutation: {
    updateProfile: async (_: any, args: any, ctx: Context) => {
      const u = requireAuth(ctx);
      return await svc().updateProfile(u.id, args.input ?? {});
    },
  },
};
