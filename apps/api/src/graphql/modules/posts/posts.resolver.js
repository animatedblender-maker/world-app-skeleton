import { PostsService } from './posts.service.ts';
function requireAuth(ctx) {
    if (!ctx.user)
        throw new Error('UNAUTHENTICATED');
    return ctx.user;
}
const svc = () => new PostsService();
export const postsResolvers = {
    Query: {
        postsByCountry: async (_, args) => {
            const limit = typeof args.limit === 'number' ? args.limit : 25;
            return await svc().postsByCountry(args.country_code ?? '', limit);
        },
    },
    Mutation: {
        createPost: async (_, args, ctx) => {
            const user = requireAuth(ctx);
            if (!args?.input?.body)
                throw new Error('Body is required.');
            return await svc().createPost(user.id, args.input);
        },
    },
};
