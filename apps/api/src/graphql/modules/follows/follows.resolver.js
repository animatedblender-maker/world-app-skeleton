import { FollowsService } from './follows.service.ts';
function requireAuth(ctx) {
    if (!ctx.user)
        throw new Error('UNAUTHENTICATED');
    return ctx.user;
}
const svc = () => new FollowsService();
export const followsResolvers = {
    Query: {
        followCounts: async (_, args) => {
            if (!args?.user_id)
                throw new Error('user_id is required');
            return await svc().counts(args.user_id);
        },
        followingIds: async (_, __, ctx) => {
            const user = requireAuth(ctx);
            return await svc().followingIds(user.id);
        },
        isFollowing: async (_, args, ctx) => {
            const user = requireAuth(ctx);
            if (!args?.user_id)
                throw new Error('user_id is required');
            return await svc().isFollowing(user.id, args.user_id);
        },
    },
    Mutation: {
        followUser: async (_, args, ctx) => {
            const user = requireAuth(ctx);
            if (!args?.target_id)
                throw new Error('target_id is required');
            await svc().follow(user.id, args.target_id);
            return true;
        },
        unfollowUser: async (_, args, ctx) => {
            const user = requireAuth(ctx);
            if (!args?.target_id)
                throw new Error('target_id is required');
            await svc().unfollow(user.id, args.target_id);
            return true;
        },
    },
};
