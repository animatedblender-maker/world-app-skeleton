// apps/api/src/graphql/modules/presence/presence.resolver.ts
import { GraphQLError } from 'graphql';
import { PresenceService } from './presence.service.ts';
function requireAuth(ctx) {
    if (!ctx.user?.id)
        throw new GraphQLError('Authentication required.', {
            extensions: { code: 'UNAUTHENTICATED' },
        });
    return ctx.user;
}
function svc() {
    return new PresenceService();
}
export const presenceResolvers = {
    Query: {
        globalStats: async (_, __, _ctx) => {
            // ✅ allow public global stats (you can lock later)
            return await svc().globalStats();
        },
        countryStats: async (_, args, _ctx) => {
            // ✅ allow public country stats (you can lock later)
            return await svc().countryStats(args.iso);
        },
    },
    Mutation: {
        heartbeat: async (_, args, ctx) => {
            const u = requireAuth(ctx);
            return await svc().heartbeat(u, args?.iso ?? null);
        },
        setOffline: async (_, __, ctx) => {
            const u = requireAuth(ctx);
            return await svc().setOffline(u);
        },
    },
};
