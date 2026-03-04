import { GraphQLError } from 'graphql';

import {
  AdsService,
  type AdCampaignInput,
  type AdCreativeInput,
  type ServeVideoAdInput,
} from './ads.service.js';

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

const svc = () => new AdsService();

export const adsResolvers = {
  Query: {
    myAdAdvertiser: async (_: any, __: any, ctx: Context) => {
      const user = requireAuth(ctx);
      return await svc().myAdvertiser(user.id);
    },
    myAdCampaigns: async (_: any, __: any, ctx: Context) => {
      const user = requireAuth(ctx);
      return await svc().myCampaigns(user.id);
    },
    adCampaignById: async (_: any, args: { id: string }, ctx: Context) => {
      const user = requireAuth(ctx);
      if (!args?.id) throw new Error('id is required.');
      return await svc().campaignById(args.id, user.id);
    },
    serveVideoAd: async (_: any, args: ServeVideoAdInput, ctx: Context) => {
      return await svc().serveVideoAd(ctx.user?.id ?? null, args);
    },
  },
  Mutation: {
    createAdCampaign: async (_: any, args: { input: AdCampaignInput }, ctx: Context) => {
      const user = requireAuth(ctx);
      return await svc().createCampaign(user.id, args.input);
    },
    updateAdCampaign: async (
      _: any,
      args: { campaign_id: string; input: AdCampaignInput },
      ctx: Context
    ) => {
      const user = requireAuth(ctx);
      if (!args?.campaign_id) throw new Error('campaign_id is required.');
      try {
        return await svc().updateCampaign(args.campaign_id, user.id, args.input);
      } catch (error: any) {
        throw new GraphQLError(error?.message ?? 'Failed to update ad campaign.', {
          extensions: { code: 'BAD_USER_INPUT' },
        });
      }
    },
    createAdCreative: async (
      _: any,
      args: { campaign_id: string; input: AdCreativeInput },
      ctx: Context
    ) => {
      const user = requireAuth(ctx);
      if (!args?.campaign_id) throw new Error('campaign_id is required.');
      return await svc().createCreative(args.campaign_id, user.id, args.input);
    },
    logAdImpression: async (_: any, args: { impression_token: string }, ctx: Context) => {
      if (!args?.impression_token) throw new Error('impression_token is required.');
      return { ok: await svc().logImpression(args.impression_token, ctx.user?.id ?? null) };
    },
    logAdClick: async (_: any, args: { impression_token: string }, ctx: Context) => {
      if (!args?.impression_token) throw new Error('impression_token is required.');
      return { ok: await svc().logClick(args.impression_token, ctx.user?.id ?? null) };
    },
  },
};
