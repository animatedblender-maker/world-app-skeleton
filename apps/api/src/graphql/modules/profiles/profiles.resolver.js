import { GraphQLError } from 'graphql';
import { ProfilesService } from './profiles.service.ts';
function requireAuth(ctx) {
    if (!ctx.user)
        throw new GraphQLError('Authentication required.', { extensions: { code: 'UNAUTHENTICATED' } });
    return ctx.user;
}
function svc() {
    // create on demand (not at import time)
    return new ProfilesService();
}
export const profilesResolvers = {
    Query: {
        me: (_, __, ctx) => {
            if (!ctx.user)
                return null;
            return { id: ctx.user.id, email: ctx.user.email, role: ctx.user.role };
        },
        privatePing: (_, __, ctx) => {
            const u = requireAuth(ctx);
            return `pong (authed as ${u.id})`;
        },
        meProfile: async (_, __, ctx) => {
            const u = requireAuth(ctx);
            return await svc().getMeProfile(u.id);
        },
        profileById: async (_, args) => {
            if (!args?.user_id)
                return null;
            return await svc().getProfileById(args.user_id);
        },
        profileByUsername: async (_, args) => {
            if (!args?.username)
                return null;
            return await svc().getProfileByUsername(args.username);
        },
        searchProfiles: async (_, args) => {
            const raw = (args?.query ?? '').trim();
            if (!raw)
                return [];
            return await svc().searchProfiles(raw, args?.limit ?? 6);
        },
    },
    Mutation: {
        updateProfile: async (_, args, ctx) => {
            const u = requireAuth(ctx);
            return await svc().updateProfile(u.id, args.input ?? {});
        },
    },
};
